import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 });

const caretInText = async (selector, offset = 2) => page.evaluate(([sel, off]) => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, off);
}, [selector, offset]);
const paste = (selector, html, plain) => page.evaluate(([sel, h, p]) => {
    const dt = new DataTransfer();
    if (h) dt.setData('text/html', h);
    if (p) dt.setData('text/plain', p);
    document.querySelector(sel).dispatchEvent(
        new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
}, [selector, html, plain]);

// ---- P2: HTML paste ----
// inline formatted paste: junk canonicalized, handlers stripped
await caretInText('#content > p:first-of-type');
await paste('#content > p:first-of-type',
    '<b onclick="evil()">bold</b> and <span style="color:red">styled</span> <a href="javascript:x">bad</a><script>evil()</script>',
    'fallback');
results.pasteInline = await page.evaluate(() => {
    const p = document.querySelector('#content > p');
    return {
        strongInserted: [...p.querySelectorAll('strong')].some(s => s.textContent === 'bold'),
        spanUnwrapped: !p.querySelector('span[style]'),
        noHandler: !p.querySelector('[onclick]'),
        badHrefDropped: [...p.querySelectorAll('a')].every(a => !(a.getAttribute('href') || '').startsWith('javascript')),
        noScript: !p.querySelector('script'),
        textPresent: p.textContent.includes('bold') && p.textContent.includes('styled'),
    };
});
await caretInText('#content > p:first-of-type');
await page.keyboard.press('Control+z');
results.pasteInline.undone = await page.evaluate(() =>
    !document.querySelector('#content > p').textContent.includes('styled'));

// block-level Word-ish paste splits and inserts blocks
const blocksBefore = await page.evaluate(() => document.getElementById('content').children.length);
await caretInText('#content > p:first-of-type', 5);
await paste('#content > p:first-of-type',
    '<html><body><!--StartFragment--><p class="MsoNormal">First para</p><h2>Pasted heading</h2>loose text<ul><li>item</li></ul><!--EndFragment--></body></html>',
    'plain fallback');
results.pasteBlocks = await page.evaluate(bc => {
    const content = document.getElementById('content');
    const kids = [...content.children].map(e => e.tagName);
    const pasted = [...content.querySelectorAll(':scope > *')].filter(e => e.textContent.includes('Pasted heading'));
    const loose = [...content.querySelectorAll(':scope > p')].find(p => p.textContent.trim().replace('⠿','') === 'loose text');
    const firstPara = [...content.querySelectorAll(':scope > p')].find(p => p.textContent.includes('First para'));
    return {
        blocksAdded: content.children.length === bc + 4 + 1, // 4 pasted + split second half
        headingBlock: pasted.length === 1 && pasted[0].tagName === 'H2',
        looseWrappedInP: !!loose,
        chromeOnPasted: !!firstPara?.querySelector(':scope > [data-role=chrome]'),
        editablePasted: firstPara?.getAttribute('contenteditable') === 'true',
        noMsoClass: !firstPara?.hasAttribute('class') || !firstPara.className.includes('Mso'),
    };
}, blocksBefore);
await caretInText('#content > p:first-of-type');
await page.keyboard.press('Control+z');
results.pasteBlocks.singleUndoReverts = await page.evaluate(bc =>
    document.getElementById('content').children.length === bc, blocksBefore);

// paste blocks into li -> flattened text
await page.evaluate(() => {
    const li = document.querySelector('#content li');
    li.focus();
    window.getSelection().collapse(li.firstChild, 2);
});
await paste('#content li', '<p>flat one</p><p>flat two</p>', '');
results.pasteLi = await page.evaluate(() => {
    const ul = document.querySelector('#content > ul');
    return {
        noNestedBlocks: !ul.querySelector('p'),
        textFlattened: ul.textContent.includes('flat one') && ul.textContent.includes('flat two'),
    };
});
await page.evaluate(() => document.querySelector('#content li').focus());
await page.keyboard.press('Control+z');

// ---- P3: a11y/keys ----
// Escape closes the find dialog
await page.click('#find-open');
await page.keyboard.press('Escape');
results.escape = { findClosed: await page.evaluate(() =>
    getComputedStyle(document.getElementById('find-dialog')).display === 'none') };
// Escape closes the annotation overlay
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('official website'));
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(t, 1); range.setEnd(t, 6);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content > p', { hasText: 'official website' }).click({ button: 'right', position: { x: 25, y: 8 } });
await page.waitForTimeout(200);
await page.keyboard.press('Escape');
results.escape.overlayClosed = await page.evaluate(() =>
    getComputedStyle(document.getElementById('overlay')).display === 'none');

// Alt+ArrowDown moves the block; undo restores
const orderBefore = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(','));
await caretInText('#content > p:first-of-type');
await page.keyboard.press('Alt+ArrowDown');
const orderMoved = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(','));
await page.keyboard.press('Alt+ArrowUp');
results.altMove = {
    movedDown: orderMoved !== orderBefore,
    movedBack: orderBefore === await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(',')),
};

// ARIA presence
results.aria = await page.evaluate(() => ({
    toolbar: document.getElementById('edit-toolbar').getAttribute('role') === 'toolbar',
    buttonsLabelled: [...document.querySelectorAll('#edit-toolbar button')].every(b => b.getAttribute('aria-label')),
    overlayDialog: document.getElementById('overlay').getAttribute('role') === 'dialog',
    dialogsModal: ['link-dialog', 'figure-dialog', 'find-dialog'].every(id =>
        document.getElementById(id).getAttribute('aria-modal') === 'true'),
    tocNav: document.getElementById('toc-drawer').getAttribute('role') === 'navigation',
    breadcrumbNav: document.getElementById('breadcrumb').getAttribute('role') === 'navigation',
    badgeIsButton: document.getElementById('lint-badge').tagName === 'BUTTON',
}));

// ---- P4: undo caret restoration ----
await caretInText('#content > blockquote', 4);
await page.keyboard.type('ZZZ');
await page.waitForTimeout(1100);
await caretInText('#content > p:first-of-type', 1); // move caret elsewhere
await page.keyboard.type('Q');
await page.keyboard.press('Control+z'); // undo the Q burst -> caret should return to where Q was typed
results.caretRestore = await page.evaluate(() => {
    const sel = window.getSelection();
    const p = document.querySelector('#content > p');
    return { afterUndoInP: p.contains(sel.anchorNode), offset: sel.anchorOffset };
});
await page.keyboard.press('Control+z'); // undo ZZZ -> caret back in blockquote at the typing position
results.caretRestore.secondUndoInBlockquote = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    const sel = window.getSelection();
    return bq.contains(sel.anchorNode) && sel.anchorOffset === 4;
});
results.caretRestore.textReverted = await page.evaluate(() =>
    !document.querySelector('#content > blockquote').textContent.includes('ZZZ'));

// ---- sanitized canonical source regression ----
await page.click('#view-source');
const src = await page.evaluate(() => document.getElementById('output-content').textContent);
results.canonicalPure = !/onclick|javascript:|<script|rdfa-invalid|contenteditable|data-role/.test(src);

console.log(JSON.stringify({ results, errors: errors.slice(0, 4) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
