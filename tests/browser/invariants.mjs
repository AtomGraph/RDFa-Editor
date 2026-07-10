// Invariant-based nesting suite: a uniform gesture battery runs in EVERY caret
// context (top-level, quote paragraph, leaf/container/nested list items, leaf and
// container cells, caption, figcaption), and after every gesture the editing DOM
// must satisfy properties that hold regardless of what the gesture did:
//   I1 every non-ws text node sits inside an editable host (nothing uneditable)
//   I2 hosts never nest (contenteditable inside contenteditable)
//   I3 chrome only as a direct child of top-level blocks
//   I4 run wrappers are editable, marker-classed paragraphs inside containers
//   I5 the lint badge stays hidden (editor gestures never produce invalid nesting)
// and after the battery, undo unwinds back to the exact post-init baseline.
// This is the cross-product net that hand-picked scenario tests cannot be.
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

// caret contexts: needle fragments chosen to survive prefix insertions (typing
// lands at offset 1, so the needle drops the first characters)
const CONTEXTS = [
    { name: 'top-level-p', needle: 'ntro paragraph' },
    { name: 'quote-p', needle: 'are quote text' },
    { name: 'leaf-li', needle: 'lain item' },
    { name: 'container-li-run', needle: 'ixed item' },
    { name: 'nested-li', needle: 'ub one' },
    { name: 'leaf-td', needle: 'lain cell' },
    { name: 'cell-p', needle: 'ell para' },
    { name: 'li-in-td', needle: 'ell item' },
    { name: 'figcaption', needle: 'caption for gestures' },
];

// place the caret in the editable host whose direct text carries the needle;
// false when the host no longer exists (a gesture may legitimately restructure)
const place = needle => page.evaluate(txt => {
    const host = [...document.querySelectorAll('#content [contenteditable=true]')]
        .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
    if (!host) return false;
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
    window.getSelection().collapse(t, 1);
    return true;
}, needle);

const invariants = () => page.evaluate(() => {
    const v = [];
    const region = document.getElementById('content');
    // I1: no orphan text
    const walker = document.createTreeWalker(region, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) {
        if (!n.textContent.trim()) continue;
        if (n.parentElement.closest('[data-role]')) continue;
        if (!n.parentElement.closest('[contenteditable=true]'))
            v.push('orphan text: "' + n.textContent.trim().slice(0, 30) + '"');
    }
    // I2: no nested hosts
    for (const h of region.querySelectorAll('[contenteditable=true] [contenteditable=true]'))
        v.push('nested host: ' + h.tagName.toLowerCase());
    // I3: chrome only on top-level blocks
    for (const c of region.querySelectorAll('[data-role=chrome]'))
        if (c.parentElement.parentElement !== region)
            v.push('nested chrome in: ' + c.parentElement.tagName.toLowerCase());
    // I4: run wrappers are editable p's inside containers
    for (const r of region.querySelectorAll('.rdfa-editor-run')) {
        if (r.tagName !== 'P') v.push('run wrapper is ' + r.tagName.toLowerCase());
        if (r.getAttribute('contenteditable') !== 'true') v.push('uneditable run wrapper');
        if (r.parentElement === region) v.push('top-level run wrapper');
    }
    // I5: gestures never produce invalid nesting (lint refreshes on after-mutation)
    if (document.getElementById('lint-badge').style.display !== 'none')
        v.push('lint: ' + document.getElementById('lint-badge').textContent);
    return v;
});

const gesture = async (name, act) => {
    await act();
    const v = await invariants();
    if (v.length) return `${name}: ${v.join('; ')}`;
    return null;
};

for (const ctx of CONTEXTS) {
    await page.goto(BASE + '/tests/fixture-nesting.html');
    await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
        .catch(() => errors.push('chrome never injected'));
    const baseline = await page.evaluate(() => document.getElementById('content').innerHTML);
    const fails = [];

    const battery = [
        ['type', async () => { if (await place(ctx.needle)) await page.keyboard.type('xy'); }],
        ['enter', async () => { if (await place(ctx.needle)) await page.keyboard.press('Enter'); }],
        ['backspace-at-start', async () => {
            if (await place(ctx.needle)) {
                await page.evaluate(() => { // move to the very start of the host
                    const sel = window.getSelection();
                    const host = sel.anchorNode.parentElement.closest('[contenteditable=true]');
                    sel.collapse(host, 0);
                });
                await page.keyboard.press('Backspace');
            }
        }],
        ['tab', async () => { if (await place(ctx.needle)) await page.keyboard.press('Tab'); }],
        ['shift-tab', async () => { if (await place(ctx.needle)) await page.keyboard.press('Shift+Tab'); }],
        ['insert-list', async () => {
            if (await place(ctx.needle)) await page.click('#edit-toolbar button.insert-list[data-list=ol]');
        }],
        ['insert-paragraph', async () => {
            if (await place(ctx.needle)) await page.click('#edit-toolbar button.insert-block');
        }],
        ['quote-toggle-on', async () => {
            if (await place(ctx.needle)
                    && !await page.evaluate(() => document.querySelector('#edit-toolbar button.format-quote').disabled))
                await page.click('#edit-toolbar button.format-quote');
        }],
        ['quote-toggle-off', async () => {
            if (await place(ctx.needle)
                    && !await page.evaluate(() => document.querySelector('#edit-toolbar button.format-quote').disabled))
                await page.click('#edit-toolbar button.format-quote');
        }],
        ['convert-h2', async () => {
            if (await place(ctx.needle)) await page.evaluate(() => {
                const s = document.querySelector('#edit-toolbar select[name=block-type]');
                if (!s.disabled) { s.value = 'h2'; s.dispatchEvent(new Event('change', { bubbles: true })); }
            });
        }],
        ['paste-blocks', async () => {
            if (await place(ctx.needle)) await page.evaluate(() => {
                const dt = new DataTransfer();
                dt.setData('text/html', '<p>pasted para</p><ul><li>pasted item</li></ul>');
                dt.setData('text/plain', 'pasted para pasted item');
                const host = window.getSelection().anchorNode.parentElement.closest('[contenteditable=true]');
                host.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
            });
        }],
    ];
    for (const [name, act] of battery) {
        try {
            const fail = await gesture(name, act);
            if (fail) fails.push(fail);
        } catch (e) {
            fails.push(`${name}: threw ${String(e).slice(0, 120)}`);
        }
    }

    // the battery unwinds to the exact post-init state
    await page.evaluate(() => document.querySelector('#content [contenteditable=true]')?.focus());
    for (let i = 0; i < 20; i++) await page.keyboard.press('Control+z');
    const restored = await page.evaluate(() => document.getElementById('content').innerHTML);
    if (restored !== baseline) fails.push('undo did not restore the baseline');

    results[ctx.name] = fails.length ? fails : true;
}

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
process.exit(errors.length || Object.values(results).some(r => r !== true) ? 1 : 0);
