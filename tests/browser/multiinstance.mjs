import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/index.html');
await page.waitForSelector('#notes > * > [data-role=chrome]', { state: 'attached', timeout: 15000 });

const caretIn = async (selector, offset = 2) => page.evaluate(([sel, off]) => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, off);
}, [selector, offset]);

// ---- both regions initialized ----
results.init = await page.evaluate(() => ({
    notesChrome: [...document.querySelectorAll('#notes > *')].every(b => b.querySelector(':scope > [data-role=chrome]')),
    notesEditable: document.querySelector('#notes > p').getAttribute('contenteditable') === 'true',
}));

// ---- region-keyed undo: edits interleaved across regions revert independently ----
await caretIn('#content > p:first-of-type');
await page.keyboard.type('AAA');
await page.waitForTimeout(1100); // close the coalescing burst
await caretIn('#notes > p');
await page.keyboard.type('BBB');
await page.waitForTimeout(1100);
const both = await page.evaluate(() => ({
    c: document.querySelector('#content > p').textContent.includes('AAA'),
    n: document.querySelector('#notes > p').textContent.includes('BBB'),
}));
await page.keyboard.press('Control+z'); // undoes the LAST edit (notes), content untouched
const afterFirst = await page.evaluate(() => ({
    c: document.querySelector('#content > p').textContent.includes('AAA'),
    n: document.querySelector('#notes > p').textContent.includes('BBB'),
}));
await page.keyboard.press('Control+z'); // undoes the content edit
const afterSecond = await page.evaluate(() => ({
    c: document.querySelector('#content > p').textContent.includes('AAA'),
    n: document.querySelector('#notes > p').textContent.includes('BBB'),
}));
results.undoKeyed = {
    bothTyped: both.c && both.n,
    lastEditReverted: !afterFirst.n && afterFirst.c,
    firstEditReverted: !afterSecond.c && !afterSecond.n,
};

// ---- blocks never move between regions ----
const orders = () => page.evaluate(() => ({
    c: [...document.getElementById('content').children].map(e => e.tagName).join(','),
    n: [...document.getElementById('notes').children].map(e => e.tagName).join(','),
}));
const before = await orders();
await page.evaluate(() => {
    const block = document.querySelector('#content > p');
    const target = document.querySelector('#notes > p');
    block.querySelector('.drag-handle').dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-block', '');
    block.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    for (const type of ['dragover', 'drop']) {
        target.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt,
            clientX: rect.x + 20, clientY: rect.y + rect.height - 2 }));
    }
    block.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
});
const after = await orders();
results.noCrossRegionDrag = { contentKept: before.c === after.c, notesKept: before.n === after.n };

// ---- toolbar inserts into the active region ----
await caretIn('#notes > p');
const notesBlocks = await page.evaluate(() => document.getElementById('notes').children.length);
await page.click('#edit-toolbar .insert-block');
results.insertActiveRegion = await page.evaluate(nb => ({
    addedToNotes: document.getElementById('notes').children.length === nb + 1,
}), notesBlocks);
await page.keyboard.press('Control+z');

// ---- view-source shows the active region ----
await caretIn('#notes > p');
await page.click('#view-source');
const src = await page.evaluate(() => document.getElementById('output-content').textContent);
results.sourceActiveRegion = {
    showsNotes: src.includes('independent editable region'),
    notContent: !src.includes('ACME'),
};
await page.click('#output-modal .modal-close');

// ---- links: pointer cursor, Ctrl+Click opens, plain click edits ----
await page.evaluate(() => {
    window.openedUrls = [];
    window.open = (url, target) => { window.openedUrls.push({ url, target }); return null; };
});
results.links = await page.evaluate(() => {
    const a = document.querySelector('#content a[href]');
    return { pointer: getComputedStyle(a).cursor === 'pointer' };
});
await page.click('#content a[href]', { modifiers: ['ControlOrMeta'] });
results.links.ctrlClickOpens = await page.evaluate(() =>
    window.openedUrls.length === 1 && window.openedUrls[0].target === '_blank'
    && /^https?:/.test(window.openedUrls[0].url));
await page.click('#content a[href]');
results.links.plainClickStays = await page.evaluate(() => window.openedUrls.length === 1);

// ---- annotation selection stays visible while the overlay is open ----
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('official website'));
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(t, 1); range.setEnd(t, 8);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content > p', { hasText: 'official website' }).first()
    .click({ button: 'right', position: { x: 30, y: 8 } });
await page.waitForTimeout(200);
results.selectionHint = await page.evaluate(() => ({
    overlayShown: getComputedStyle(document.getElementById('overlay')).display !== 'none',
    hintBoxes: document.querySelectorAll('.rdfa-editor-selection-hint').length > 0,
}));
await page.keyboard.press('Escape');
results.selectionHint.clearedOnClose = await page.evaluate(() =>
    document.querySelectorAll('.rdfa-editor-selection-hint').length === 0);

console.log(JSON.stringify({ results, errors: errors.slice(0, 4) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
