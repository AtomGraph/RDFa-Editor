// Phase 1 content-model foundation: recursive editability init, mixed-flow run
// wrappers, load normalization, blockquote-as-container editing, nested paste,
// nesting lint and undo across nested hosts (fixture-nesting.html).
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/tests/fixture-nesting.html');
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('chrome never injected'));

const undoKey = 'Control+z';
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

// ---- 1. recursive editability init -----------------------------------------------
results.init = await page.evaluate(() => {
    const editable = el => el?.getAttribute('contenteditable') === 'true';
    const mixed = [...document.querySelectorAll('#content > ul > li')]
        .find(li => li.textContent.includes('Mixed item'));
    const blockItem = [...document.querySelectorAll('#content > ul > li')]
        .find(li => li.textContent.includes('Block item'));
    const bq = document.querySelector('#content > blockquote');
    const cell = document.querySelector('#content td');
    const plainCell = [...document.querySelectorAll('#content td')]
        .find(td => td.textContent.includes('Plain cell'));
    return {
        plainLiEditable: editable([...document.querySelectorAll('#content > ul > li')]
            .find(li => li.textContent.startsWith('Plain item'))),
        mixedLiIsContainer: mixed && !editable(mixed),
        mixedLiRunWrapper: editable(mixed?.querySelector(':scope > p.rdfa-editor-run'))
            && mixed?.querySelector(':scope > p.rdfa-editor-run').textContent === 'Mixed item',
        mixedLiSubEditable: editable(mixed?.querySelector(':scope > ul > li')),
        blockItemIsContainer: blockItem && !editable(blockItem),
        blockItemPEditable: editable(blockItem?.querySelector(':scope > p')),
        nestedQuotePEditable: editable(blockItem?.querySelector(':scope > blockquote > p')),
        // drag handles are direct children of top-level blocks only, never nested deeper
        noChromeBelowTopLevel: [...document.querySelectorAll('#content [data-role=chrome]')]
            .every(c => c.parentElement.parentElement === document.getElementById('content')),
        chromeOnTopLevel: !!document.querySelector('#content > ul > [data-role=chrome]'),
        cellIsContainer: cell && !editable(cell),
        cellPEditable: editable(cell?.querySelector(':scope > p')),
        cellNestedLiEditable: editable(cell?.querySelector(':scope > ul > li')),
        plainCellEditable: editable(plainCell),
    };
});

// ---- 2. load normalization ---------------------------------------------------------
results.loadNormalize = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    const content = document.getElementById('content');
    return {
        // bare quote text got a paragraph host
        quoteWrapped: !!bq.querySelector(':scope > p')
            && bq.querySelector(':scope > p').textContent.includes('Bare quote text'),
        quoteNoBareText: ![...bq.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()),
        quoteNotEditable: bq.getAttribute('contenteditable') !== 'true',
        // the HTML parser fostered "after" out of <p>Before<ul>; load init wrapped it
        noStrayRegionText: ![...content.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()),
        afterWrapped: [...content.querySelectorAll(':scope > p')]
            .some(p => [...p.childNodes].some(n => n.nodeType === 3 && n.textContent.trim() === 'after')),
    };
});

// ---- 3. canonical source round-trips the mixed li, unwraps run wrappers ------------
await page.click('#view-source');
const source = await page.evaluate(() => document.getElementById('output-content').textContent);
results.source = {
    mixedLiIntact: /<li>Mixed item<ul>/.test(source.replace(/\s+</g, '<')),
    noRunMarker: !source.includes('rdfa-editor-run'),
    quoteHasParagraph: /<blockquote><p>Bare quote text/.test(source.replace(/>\s+</g, '><')),
    clean: !/data-role|contenteditable|draggable|aria-|⠿/.test(source),
};
await page.keyboard.press('Escape');

// ---- 4. editing inside the blockquote container ------------------------------------
await caretInText('#content > blockquote > p', 4);
await page.keyboard.press('Enter');
results.quoteEnter = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    return {
        splitIntoTwo: bq.querySelectorAll(':scope > p').length === 2,
        noChromeInside: !bq.querySelector('p [data-role=chrome], :scope > p > [data-role=chrome]'),
        caretInSecond: bq.querySelectorAll(':scope > p')[1].contains(window.getSelection().anchorNode),
    };
});
// Backspace at the start of the second paragraph merges back
await page.keyboard.press('Backspace');
results.quoteBackspace = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    return {
        mergedBack: bq.querySelectorAll(':scope > p').length === 1,
        textIntact: bq.textContent.includes('Bare quote text to normalize.'),
    };
});

// ---- 5. block paste into a list item nests (no flattening) -------------------------
await caretInText('#content > ul > li', 2);
await paste('#content > ul > li', '<p>Pasted para</p><ul><li>pasted item</li></ul>');
results.pasteIntoLi = await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.textContent.includes('Pasted para'));
    return {
        nested: !!li && !!li.querySelector(':scope > ul > li') && !!li.querySelector(':scope > p'),
        liIsContainer: li?.getAttribute('contenteditable') !== 'true',
        headRunKept: li?.textContent.includes('Pl') && li?.textContent.includes('ain item'),
        pastedItemEditable: li?.querySelector(':scope > ul > li')?.getAttribute('contenteditable') === 'true',
    };
});
// one undo reverts the whole paste
await page.keyboard.press(undoKey);
results.pasteIntoLi.undone = await page.evaluate(() =>
    ![...document.querySelectorAll('#content li')].some(l => l.textContent.includes('Pasted para')));

// ---- 6. nesting lint surfaces live violations --------------------------------------
results.lintBadgeHiddenWhenValid = await page.evaluate(() =>
    document.getElementById('lint-badge').style.display === 'none');
await page.evaluate(() => {
    // inject stray text into a structural container behind the editor's back
    document.querySelector('#content > ul').appendChild(document.createTextNode('stray in list'));
});
await caretInText('#content > p:first-of-type');
await page.keyboard.type('x'); // any mutation runs lint via after-mutation
await page.waitForTimeout(100);
results.lint = await page.evaluate(() => ({
    badgeVisible: document.getElementById('lint-badge').style.display !== 'none',
    badgeCounts: /issue/.test(document.getElementById('lint-badge').textContent),
}));
await page.evaluate(() => {
    const ul = document.querySelector('#content > ul');
    [...ul.childNodes].filter(n => n.nodeType === 3 && n.textContent.includes('stray')).forEach(n => n.remove());
});
await page.keyboard.press(undoKey); // revert the 'x'

// ---- 7. undo across a nested-host edit ---------------------------------------------
await caretInText('#content > blockquote > p', 4);
await page.keyboard.type('XYZ');
await page.waitForTimeout(1100);
await page.keyboard.press(undoKey);
results.nestedUndo = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    return {
        reverted: !bq.textContent.includes('XYZ'),
        stillContainer: bq.getAttribute('contenteditable') !== 'true'
            && bq.querySelector(':scope > p')?.getAttribute('contenteditable') === 'true',
    };
});

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
const flat = JSON.stringify(results);
process.exit(errors.length || flat.includes('false') ? 1 : 0);
