import { chromium } from 'playwright';

// @-mention, slash menu, markdown input rules and the block-handle menu.
// Follows the tables.mjs convention: assert() records to results AND fails the suite.
const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('chrome never injected'));

const PROP = 'http://xmlns.com/foaf/0.1/homepage';
const blockCount = () => page.evaluate(() => document.getElementById('content').children.length);
const visible = id => page.evaluate(i => {
    const el = document.getElementById(i);
    return !!el && getComputedStyle(el).display !== 'none';
}, id);
// focus a block and insert a fresh empty paragraph after it (caret lands inside it)
const freshPara = async () => {
    await page.evaluate(() => document.querySelector('#content > h1').focus());
    await page.click('#edit-toolbar button.insert-block');
    await page.waitForTimeout(50);
};

// ---------------------------------------------------------------- @-mention

// collapsed caret: @ opens the picker; property + free-form IRI emit a relation triple
await freshPara();
await page.keyboard.type('@');
await page.waitForTimeout(150);
assert('mention.opensOnAt', await visible('mention-dialog'));
await page.selectOption('#mention-dialog select[name=property]', PROP);
await page.fill('#mention-dialog input[name=resource]', 'https://example.org/jane');
await page.click('#mention-dialog button.mention-save');
await page.waitForTimeout(100);
results.mention = await page.evaluate(p => {
    const span = document.querySelector(`#content span[property="${p}"][resource="https://example.org/jane"]`);
    return { exists: !!span, label: span?.textContent, closed: getComputedStyle(document.getElementById('mention-dialog')).display === 'none' };
}, PROP);
assert('mention.tripleSpan', results.mention.exists);
assert('mention.labelIsLocalName', results.mention.label === 'jane');
assert('mention.dialogClosed', results.mention.closed);
// undo removes the whole mention in one step
await page.keyboard.press('Control+z');
await page.waitForTimeout(80);
assert('mention.undo', await page.evaluate(p => !document.querySelector(`#content span[property="${p}"]`), PROP));

// mid-word @ (e.g. an email) stays literal - no picker
await freshPara();
await page.keyboard.type('a@');
await page.waitForTimeout(120);
assert('mention.literalMidWord', !(await visible('mention-dialog'))
    && await page.evaluate(() => document.activeElement.textContent.includes('a@')));

// selection: @ wraps the selected text as the labelled relation
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('will launch'));
    p.closest('[contenteditable=true]').focus();
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.includes('product'));
    const i = t.textContent.indexOf('product');
    const r = document.createRange(); r.setStart(t, i); r.setEnd(t, i + 7);
    const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
});
await page.keyboard.type('@');
await page.waitForTimeout(150);
assert('mention.opensOnSelection', await visible('mention-dialog'));
await page.selectOption('#mention-dialog select[name=property]', PROP);
await page.fill('#mention-dialog input[name=resource]', 'https://example.org/product');
await page.click('#mention-dialog button.mention-save');
await page.waitForTimeout(100);
assert('mention.wrapsSelection', await page.evaluate(p => {
    const span = document.querySelector(`#content span[property="${p}"][resource="https://example.org/product"]`);
    return span?.textContent === 'product';
}, PROP));

// ---------------------------------------------------------------- slash menu

await freshPara();
await page.keyboard.type('/');
await page.waitForTimeout(150);
assert('slash.opens', await visible('slash-menu'));
// filter narrows to a single command
await page.fill('#slash-menu input.slash-filter', 'quote');
await page.waitForTimeout(80);
assert('slash.filters', await page.evaluate(() => {
    const shown = [...document.querySelectorAll('#slash-menu li.slash-item')].filter(li => getComputedStyle(li).display !== 'none');
    return shown.length === 1 && shown[0].dataset.command === 'blockquote';
}));
// picking Heading 2 converts the empty block in place
await page.fill('#slash-menu input.slash-filter', '');
await page.waitForTimeout(50);
await page.click('#slash-menu li.slash-item[data-command="h2"]');
await page.waitForTimeout(80);
assert('slash.convertsToHeading', await page.evaluate(() =>
    [...document.querySelectorAll('#content > h2')].some(h => h.textContent.replace(/⠿/g, '').trim() === '')));
assert('slash.closed', !(await visible('slash-menu')));

// keyboard path: / then ArrowDown+Enter picks the second item (Heading 1)
await freshPara();
await page.keyboard.type('/');
await page.waitForTimeout(120);
await page.keyboard.press('ArrowDown');
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
assert('slash.keyboardPick', await page.evaluate(() =>
    [...document.querySelectorAll('#content > h1')].some(h => h.textContent.replace(/⠿/g, '').trim() === '')));

// / with existing text is left literal (not an insert trigger)
await freshPara();
await page.keyboard.type('a/');
await page.waitForTimeout(100);
assert('slash.literalWithText', !(await visible('slash-menu'))
    && await page.evaluate(() => document.activeElement.textContent.includes('a/')));

// ---------------------------------------------------------------- markdown rules

const emptyOf = tag => page.evaluate(t => [...document.querySelectorAll(`#content > ${t}`)].some(e => e.textContent.replace(/⠿/g, '').trim() === ''), tag);

await freshPara();
await page.keyboard.type('# ');
await page.waitForTimeout(80);
assert('md.heading', await emptyOf('h1'));
// undo restores a paragraph (marker + p), not a heading
await page.keyboard.press('Control+z');
await page.waitForTimeout(80);
assert('md.headingUndo', await page.evaluate(() => document.activeElement.tagName === 'P'));

await freshPara();
await page.keyboard.type('- ');
await page.waitForTimeout(80);
assert('md.bulletList', await page.evaluate(() =>
    [...document.querySelectorAll('#content > ul')].some(ul => ul.querySelector('li') && ul.querySelector('li').textContent.trim() === '')));

await freshPara();
await page.keyboard.type('> ');
await page.waitForTimeout(80);
assert('md.blockquote', await emptyOf('blockquote'));

await freshPara();
await page.keyboard.type('1. ');
await page.waitForTimeout(80);
assert('md.orderedList', await page.evaluate(() =>
    [...document.querySelectorAll('#content > ol')].some(ol => ol.querySelector('li'))));

// ---------------------------------------------------------------- block-handle menu

const openHandleMenu = sel => page.evaluate(s => {
    const h = document.querySelector(`${s} > [data-role=chrome]`);
    const r = h.getBoundingClientRect();
    h.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: r.left, clientY: r.top }));
}, sel);

// duplicate a paragraph
const n0 = await blockCount();
await openHandleMenu('#content > p:first-of-type');
await page.waitForTimeout(80);
assert('menu.opens', await visible('block-menu'));
await page.click('#block-menu button.block-duplicate');
await page.waitForTimeout(80);
assert('menu.duplicate', (await blockCount()) === n0 + 1
    && await page.evaluate(() => {
        const p = document.querySelector('#content > p:first-of-type');
        const next = p.nextElementSibling;
        return next && next.tagName === 'P' && !!next.querySelector(':scope > [data-role=chrome]');
    }));

// turn-into: convert a paragraph to Heading 3
await openHandleMenu('#content > p:first-of-type');
await page.waitForTimeout(80);
assert('menu.turnEnabledForText', await page.evaluate(() =>
    !document.querySelector('#block-menu button.block-turn').disabled));
await page.click('#block-menu button.block-turn[data-name="h3"]');
await page.waitForTimeout(80);
assert('menu.turnInto', await page.evaluate(() => document.querySelector('#content > *:first-child, #content > h1') && document.querySelector('#content > h3') !== null));

// turn-into disabled for a locked structural block (the list)
await openHandleMenu('#content > ul');
await page.waitForTimeout(80);
assert('menu.turnDisabledForList', await page.evaluate(() =>
    document.querySelector('#block-menu button.block-turn').disabled === true));
await page.keyboard.press('Escape');

// delete removes the block (confirm auto-accepted)
const n1 = await blockCount();
await openHandleMenu('#content > blockquote');
await page.waitForTimeout(80);
await page.click('#block-menu button.block-delete');
await page.waitForTimeout(80);
assert('menu.delete', (await blockCount()) === n1 - 1);

console.log(JSON.stringify({ results, errors: errors.slice(0, 8) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
