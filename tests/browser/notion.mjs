// Slash menu and markdown input rules (ported from PR #10 onto the content-model
// era): the / menu opens in an empty host with only the commands the caret
// context admits, converts/inserts via the existing toolbar machinery, and the
// markdown shorthands act on the HOST (top-level p, quote-p, cell-p) with
// content-model gating - '> ' WRAPS in a blockquote (blockquote > p), a
// shorthand in a non-paragraph host stays literal. Every mutation must satisfy
// the I1-I5 invariants (fixture-nesting.html).
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

const load = async () => {
    await page.goto(BASE + '/tests/fixture-nesting.html');
    await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
        .catch(() => errors.push('chrome never injected'));
};
const visible = id => page.evaluate(i => {
    const el = document.getElementById(i);
    return !!el && getComputedStyle(el).display !== 'none';
}, id);
const shownCommands = () => page.evaluate(() =>
    [...document.querySelectorAll('#slash-menu li.slash-item')]
        .filter(li => getComputedStyle(li).display !== 'none').map(li => li.dataset.command));
// caret at the end of the host carrying the needle, then a fresh empty paragraph after it
const freshPara = async (needle = 'Intro paragraph') => {
    await page.evaluate(txt => {
        const host = [...document.querySelectorAll('#content [contenteditable=true]')]
            .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
        host.focus();
        const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
        window.getSelection().collapse(t, t.textContent.length);
    }, needle);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(50);
};
// empty the host carrying the needle via a within-host selection + native delete
const emptyHost = async needle => {
    await page.evaluate(txt => {
        const host = [...document.querySelectorAll('#content [contenteditable=true]')]
            .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
        host.focus();
        const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
        const r = document.createRange();
        r.setStart(t, 0); r.setEnd(t, t.textContent.length);
        const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
    }, needle);
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(50);
};
const invariants = () => page.evaluate(() => {
    const v = [];
    const region = document.getElementById('content');
    const walker = document.createTreeWalker(region, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) {
        if (!n.textContent.trim()) continue;
        if (n.parentElement.closest('[data-role]')) continue;
        if (!n.parentElement.closest('[contenteditable=true]'))
            v.push('orphan text: "' + n.textContent.trim().slice(0, 30) + '"');
    }
    for (const h of region.querySelectorAll('[contenteditable=true] [contenteditable=true]'))
        v.push('nested host: ' + h.tagName.toLowerCase());
    for (const c of region.querySelectorAll('[data-role=chrome]'))
        if (c.parentElement.parentElement !== region)
            v.push('nested chrome in: ' + c.parentElement.tagName.toLowerCase());
    if (document.getElementById('lint-badge').style.display !== 'none')
        v.push('lint: ' + document.getElementById('lint-badge').textContent);
    return v;
});
const clean = async name => {
    const v = await invariants();
    assert(name + '.invariants', v.length === 0);
    if (v.length) errors.push(`${name}: ${v.join('; ')}`);
};

// ---------------------------------------------------------------- slash menu

await load();
await freshPara();
await page.keyboard.type('/');
await page.waitForTimeout(150);
assert('slash.opens', await visible('slash-menu'));
assert('slash.filterFocused', await page.evaluate(() =>
    document.activeElement.classList.contains('slash-filter')));
assert('slash.allCommandsAtTopLevel', (await shownCommands()).length === 10);

// filter narrows to a single command
await page.fill('#slash-menu input.slash-filter', 'quote');
await page.waitForTimeout(80);
assert('slash.filters', JSON.stringify(await shownCommands()) === '["blockquote"]');

// picking Heading 2 converts the empty block in place, caret returns
await page.fill('#slash-menu input.slash-filter', '');
await page.waitForTimeout(50);
await page.click('#slash-menu li.slash-item[data-command="h2"]');
await page.waitForTimeout(80);
assert('slash.convertsToHeading', await page.evaluate(() => {
    const h = [...document.querySelectorAll('#content > h2')].find(x => x.textContent.replace(/⠿/g, '') === '');
    return !!h && h.getAttribute('contenteditable') === 'true'
        && !!h.querySelector(':scope > [data-role=chrome]')
        && h.contains(window.getSelection().anchorNode);
}));
assert('slash.closed', !(await visible('slash-menu')));
await clean('slash.convert');
// one undo unwinds the conversion back to a paragraph
await page.keyboard.press('Control+z');
await page.waitForTimeout(80);
assert('slash.undo', await page.evaluate(() =>
    ![...document.querySelectorAll('#content > h2')].some(x => x.textContent.replace(/⠿/g, '') === '')));

// keyboard path: / then ArrowDown+Enter picks the second visible item (Heading 1)
await load();
await freshPara();
await page.keyboard.type('/');
await page.waitForTimeout(120);
await page.keyboard.press('ArrowDown');
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
assert('slash.keyboardPick', await page.evaluate(() =>
    [...document.querySelectorAll('#content > h1')].some(h => h.textContent.replace(/⠿/g, '') === '')));

// list command replaces the empty paragraph with a single-item list
await load();
await freshPara();
await page.keyboard.type('/');
await page.waitForTimeout(120);
await page.click('#slash-menu li.slash-item[data-command="ol"]');
await page.waitForTimeout(80);
assert('slash.list', await page.evaluate(() => {
    const ol = document.querySelector('#content > ol');
    const li = ol?.querySelector('li');
    return !!li && li.getAttribute('contenteditable') === 'true'
        && !!ol.querySelector(':scope > [data-role=chrome]')
        && li.contains(window.getSelection().anchorNode);
}));
await clean('slash.list');

// / with existing text is left literal (not a trigger)
await load();
await freshPara();
await page.keyboard.type('a/');
await page.waitForTimeout(100);
assert('slash.literalWithText', !(await visible('slash-menu'))
    && await page.evaluate(() => document.activeElement.textContent.includes('a/')));

// context filtering: an emptied list item only offers figure/table
await load();
await emptyHost('Plain item');
await page.keyboard.type('/');
await page.waitForTimeout(120);
assert('slash.liContext', JSON.stringify(await shownCommands()) === '["figure","table"]');
await page.keyboard.press('Escape');
await page.waitForTimeout(80);
assert('slash.escapeCloses', !(await visible('slash-menu'))
    && await page.evaluate(() => !!document.activeElement.closest('#content')));

// an emptied cell paragraph (flow context) offers everything
await load();
await emptyHost('Cell para');
await page.keyboard.type('/');
await page.waitForTimeout(120);
assert('slash.cellContext', (await shownCommands()).length === 10);
await page.keyboard.press('Escape');

// figure command routes to the existing dialog, inserting after the TOP-LEVEL block
await load();
await emptyHost('Plain cell');
await page.keyboard.type('/');
await page.waitForTimeout(120);
await page.click('#slash-menu li.slash-item[data-command="figure"]');
await page.waitForTimeout(80);
assert('slash.figureDialogOpens', await visible('figure-dialog'));
await page.fill('#figure-dialog input[name="src"]', 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==');
await page.click('#figure-dialog button.figure-save');
await page.waitForTimeout(80);
assert('slash.figureAfterTable', await page.evaluate(() => {
    const table = document.querySelector('#content > table');
    return table?.nextElementSibling?.tagName === 'FIGURE';
}));
await clean('slash.figure');

// ---------------------------------------------------------------- markdown rules

await load();
await freshPara();
await page.keyboard.type('# ');
await page.waitForTimeout(80);
assert('md.heading', await page.evaluate(() => {
    const h = [...document.querySelectorAll('#content > h1')].find(x => x.textContent.replace(/⠿/g, '') === '');
    return !!h && h.contains(window.getSelection().anchorNode);
}));
await clean('md.heading');
// one undo restores the paragraph with the literal marker
await page.keyboard.press('Control+z');
await page.waitForTimeout(80);
assert('md.headingUndo', await page.evaluate(() =>
    [...document.querySelectorAll('#content > p')].some(p => p.textContent.replace(/⠿/g, '') === '#')));

await load();
await freshPara();
await page.keyboard.type('- ');
await page.waitForTimeout(80);
assert('md.bulletList', await page.evaluate(() => {
    const ul = [...document.querySelectorAll('#content > ul')]
        .find(u => u.querySelector('li') && u.textContent.replace(/⠿/g, '').trim() === '');
    return !!ul && ul.querySelector('li').contains(window.getSelection().anchorNode);
}));
await clean('md.bulletList');

await load();
await freshPara();
await page.keyboard.type('1. ');
await page.waitForTimeout(80);
assert('md.orderedList', await page.evaluate(() =>
    [...document.querySelectorAll('#content > ol')].some(ol => ol.querySelector('li'))));

// '> ' WRAPS per the content model: blockquote > p, chrome on the quote
await load();
await freshPara();
await page.keyboard.type('> ');
await page.waitForTimeout(80);
assert('md.quoteWraps', await page.evaluate(() => {
    const q = [...document.querySelectorAll('#content > blockquote')].find(b => !b.textContent.includes('Bare quote'));
    const p = q?.querySelector(':scope > p');
    return !!p && p.getAttribute('contenteditable') === 'true'
        && p.textContent === '' && !!q.querySelector(':scope > [data-role=chrome]')
        && !p.querySelector('[data-role=chrome]');
}));
await clean('md.quoteWraps');

await load();
await freshPara();
await page.keyboard.type('```');
await page.waitForTimeout(80);
assert('md.pre', await page.evaluate(() =>
    [...document.querySelectorAll('#content > pre')].some(pre => pre.textContent.replace(/⠿/g, '') === '')));

// a shorthand inside a quote paragraph converts the nested host alone
await load();
await emptyHost('Bare quote text');
await page.keyboard.type('## ');
await page.waitForTimeout(80);
assert('md.nestedQuoteHeading', await page.evaluate(() => {
    const q = [...document.querySelectorAll('#content > blockquote')][0];
    return !!q?.querySelector(':scope > h2[contenteditable=true]');
}));
await clean('md.nestedQuoteHeading');

// a shorthand in a non-paragraph host stays literal (an li is not a p)
await load();
await emptyHost('Plain item');
await page.keyboard.type('- ');
await page.waitForTimeout(80);
assert('md.literalInLi', await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')][0];
    // contenteditable renders a trailing space as NBSP
    return li.textContent.replace(/ /g, ' ') === '- ' && !li.querySelector('ul');
}));

// mid-text marker stays literal
await load();
await page.evaluate(() => {
    const host = [...document.querySelectorAll('#content > p')].find(p => p.textContent.includes('Intro'));
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, t.textContent.length);
});
await page.keyboard.type('# ');
await page.waitForTimeout(80);
assert('md.literalMidText', await page.evaluate(() =>
    [...document.querySelectorAll('#content > p')].some(p =>
        p.textContent.replace(/ /g, ' ').includes('Intro paragraph.# '))));

console.log(JSON.stringify({ results, errors: errors.slice(0, 8) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
