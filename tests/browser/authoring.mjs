// Phase 2 authoring gestures: quote toggle (wrap/unwrap/RDFa refusal/inner
// convert), nested-list Tab/Shift+Tab indent/outdent with container collapse,
// progressive Enter/Backspace exits, container merges (B2b/B7), Tab dispatch in
// flow cells, and toolbar enable/disable state (fixture-nesting.html).
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

const undoKey = 'Control+z';
const load = async () => {
    await page.goto(BASE + '/tests/fixture-nesting.html');
    await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
        .catch(() => errors.push('chrome never injected'));
};
const caretIn = (selector, offset = 2) => page.evaluate(([sel, off]) => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, off === -1 ? t.textContent.length : off);
}, [selector, offset]);
const paste = (selector, html, plain) => page.evaluate(([sel, h, p]) => {
    const dt = new DataTransfer();
    if (h) dt.setData('text/html', h);
    if (p) dt.setData('text/plain', p);
    document.querySelector(sel).dispatchEvent(
        new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
}, [selector, html, plain]);
// caret inside the editable host whose DIRECT text carries the needle (a leaf li,
// or the run wrapper of a container item)
const caretInLi = (needle, offset = 0) => page.evaluate(([txt, off]) => {
    const host = [...document.querySelectorAll('#content [contenteditable=true]')]
        .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
    window.getSelection().collapse(t, off === -1 ? t.textContent.length : off);
}, [needle, offset]);

// ==== A. quote toggle + toolbar state ===============================================
await load();

// toolbar state: caret in a plain list item disables the block-type select
await caretInLi('Plain item', 1);
await page.waitForTimeout(100);
results.toolbar = await page.evaluate(() => ({
    selectDisabledInLi: document.querySelector('#edit-toolbar select[name=block-type]').disabled,
    // an li cannot wrap in a blockquote (ul holds only li) - the toggle disables
    quoteDisabledInLi: document.querySelector('#edit-toolbar button.format-quote').disabled,
}));
// caret in the quote's paragraph: select enabled and reads Paragraph, toggle pressed
await caretIn('#content > blockquote > p', 2);
await page.waitForTimeout(100);
Object.assign(results.toolbar, await page.evaluate(() => ({
    selectEnabledInQuoteP: !document.querySelector('#edit-toolbar select[name=block-type]').disabled,
    selectReadsParagraph: document.querySelector('#edit-toolbar select[name=block-type]').value === 'p',
    quotePressed: document.querySelector('#edit-toolbar button.format-quote').getAttribute('aria-pressed') === 'true',
})));

// quote ON: wrap the intro paragraph
await caretIn('#content > p', 2);
await page.click('#edit-toolbar button.format-quote');
results.quoteOn = await page.evaluate(() => {
    const bq = [...document.querySelectorAll('#content > blockquote')]
        .find(b => b.textContent.includes('Intro paragraph'));
    return {
        wrapped: !!bq && bq.querySelector(':scope > p')?.getAttribute('contenteditable') === 'true',
        chromeOnQuote: !!bq?.querySelector(':scope > [data-role=chrome]'),
        chromeOnInnerP: !!bq?.querySelector(':scope > p > [data-role=chrome]'),
        notEditableItself: bq?.getAttribute('contenteditable') !== 'true',
    };
});

// inner convert: the paragraph inside the quote becomes a heading, quote intact
await page.evaluate(() => {
    const bq = [...document.querySelectorAll('#content > blockquote')]
        .find(b => b.textContent.includes('Intro paragraph'));
    const p = bq.querySelector(':scope > p');
    p.focus();
    window.getSelection().collapse([...p.childNodes].find(n => n.nodeType === 3), 2);
});
await page.selectOption('#edit-toolbar select[name=block-type]', 'h2');
results.innerConvert = await page.evaluate(() => {
    const bq = [...document.querySelectorAll('#content > blockquote')]
        .find(b => b.textContent.includes('Intro paragraph'));
    return {
        converted: !!bq?.querySelector(':scope > h2'),
        quoteIntact: !!bq,
        editable: bq?.querySelector(':scope > h2')?.getAttribute('contenteditable') === 'true',
    };
});

// quote OFF: the heading releases to the top level with chrome
await page.click('#edit-toolbar button.format-quote');
results.quoteOff = await page.evaluate(() => {
    const h2 = [...document.querySelectorAll('#content > h2')]
        .find(h => h.textContent.includes('Intro paragraph'));
    return {
        released: !!h2,
        chromeRestored: !!h2?.querySelector(':scope > [data-role=chrome]'),
        quoteGone: ![...document.querySelectorAll('#content > blockquote')]
            .some(b => b.textContent.includes('Intro paragraph')),
    };
});
// undo restores the quote, second undo the paragraph
await page.keyboard.press(undoKey);
results.quoteOff.undoRestoresQuote = await page.evaluate(() =>
    [...document.querySelectorAll('#content > blockquote')]
        .some(b => b.querySelector(':scope > h2')?.textContent.includes('Intro paragraph')));

// RDFa refusal: an annotated quote refuses to unwrap
await page.evaluate(() => {
    const bq = [...document.querySelectorAll('#content > blockquote')]
        .find(b => b.textContent.includes('Intro paragraph'));
    bq.setAttribute('property', 'http://purl.org/dc/terms/description');
    const h = bq.querySelector('[contenteditable=true]');
    h.focus();
    window.getSelection().collapse([...h.childNodes].find(n => n.nodeType === 3), 1);
});
await page.click('#edit-toolbar button.format-quote');
results.rdfaRefusal = await page.evaluate(() =>
    [...document.querySelectorAll('#content > blockquote')]
        .some(b => b.getAttribute('property') && b.textContent.includes('Intro paragraph')));

// ==== B. nested-list indent/outdent ================================================
await load();

// Tab indents the second item under the first
await caretInLi('Mixed item', 1);
await page.keyboard.press('Tab');
results.indent = await page.evaluate(() => {
    const plain = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.textContent.includes('Plain item'));
    const mixed = plain?.querySelector(':scope > ul > li');
    return {
        nested: !!mixed && mixed.textContent.includes('Mixed item'),
        prevBecameContainer: plain?.getAttribute('contenteditable') !== 'true',
        prevRunWrapper: plain?.querySelector(':scope > p.rdfa-editor-run')?.textContent === 'Plain item',
        prevRunEditable: plain?.querySelector(':scope > p.rdfa-editor-run')
            ?.getAttribute('contenteditable') === 'true',
        subtreeIntact: !!mixed?.querySelector(':scope > ul > li'), // Mixed item kept its own sublist
    };
});
// canonical source shows the conventional mixed form
await page.click('#view-source');
const src = await page.evaluate(() => document.getElementById('output-content').textContent);
results.indent.canonicalConventional = /<li>Plain item<ul>/.test(src.replace(/>\s+</g, '><'))
    && !src.includes('rdfa-editor-run');
await page.keyboard.press('Escape');

// Shift+Tab outdents it again and the emptied container collapses to a text host
await caretInLi('Mixed item', 1);
await page.keyboard.press('Shift+Tab');
results.outdent = await page.evaluate(() => {
    const top = [...document.querySelectorAll('#content > ul > li')];
    const plain = top.find(l => l.textContent.includes('Plain item'));
    return {
        backAtTopLevel: top.some(l => l.textContent.includes('Mixed item')),
        containerCollapsed: plain?.getAttribute('contenteditable') === 'true',
        noRunWrapperLeft: !plain?.querySelector(':scope > p.rdfa-editor-run'),
    };
});

// first item flashes and stays put
await caretInLi('Plain item', 1);
await page.keyboard.press('Tab');
results.firstItemInert = await page.evaluate(() =>
    [...document.querySelectorAll('#content > ul > li')].some(l => l.textContent.startsWith('Plain item')));

// Shift+Tab with followers: outdenting Sub one demotes Sub two under it
await caretInLi('Sub one', 1);
await page.keyboard.press('Shift+Tab');
results.outdentFollowers = await page.evaluate(() => {
    const top = [...document.querySelectorAll('#content > ul > li')];
    const subOne = top.find(l => l.textContent.includes('Sub one'));
    const mixed = top.find(l => l.textContent.includes('Mixed item'));
    return {
        subOneAtTop: !!subOne,
        subTwoDemoted: !!subOne?.querySelector(':scope > ul > li')
            && subOne.querySelector(':scope > ul > li').textContent.includes('Sub two'),
        subOneRunEditable: subOne?.querySelector(':scope > p.rdfa-editor-run')
            ?.getAttribute('contenteditable') === 'true',
        mixedCollapsed: mixed?.getAttribute('contenteditable') === 'true',
    };
});
await page.keyboard.press(undoKey);
results.outdentFollowers.undone = await page.evaluate(() => {
    const mixed = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.textContent.includes('Mixed item'));
    return !!mixed?.querySelector(':scope > ul > li') // sublist back inside Mixed item
        && mixed.getAttribute('contenteditable') !== 'true';
});

// progressive Enter: split at the end of the last nested item, then outdent
await caretInLi('Sub two', -1);
await page.keyboard.press('Enter');   // new empty item in the nested list
await page.keyboard.press('Enter');   // E4a: outdents one level
results.progressiveEnter = await page.evaluate(() => {
    const sel = window.getSelection();
    const li = sel.anchorNode?.nodeType === 1 ? sel.anchorNode : sel.anchorNode?.parentElement;
    const item = li?.closest('li');
    return {
        outdentedToTop: !!item && item.parentElement.parentElement.id === 'content',
        empty: item?.textContent.trim() === '',
    };
});

// Backspace at the start of the first nested item outdents (B4b)
await load();
await caretInLi('Sub one', 0);
await page.keyboard.press('Backspace');
results.backspaceOutdent = await page.evaluate(() => {
    const top = [...document.querySelectorAll('#content > ul > li')];
    const subOne = top.find(l => l.textContent.includes('Sub one'));
    return {
        outdented: !!subOne,
        followersDemoted: !!subOne?.querySelector(':scope > ul > li'),
    };
});

// ==== C. container merges ==========================================================
await load();

// B7: Backspace at the start of the quote's first block exits upward
await caretIn('#content > blockquote > p', 0);
await page.keyboard.press('Backspace');
results.quoteExit = await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')]
        .find(x => x.textContent.includes('Bare quote text'));
    return {
        released: !!p && p.getAttribute('contenteditable') === 'true',
        chrome: !!p?.querySelector(':scope > [data-role=chrome]'),
        emptyQuoteRemoved: ![...document.querySelectorAll('#content > blockquote')]
            .some(b => b.textContent.trim().replace('⣿', '') === ''),
    };
});
await page.keyboard.press(undoKey);
results.quoteExit.undone = await page.evaluate(() =>
    [...document.querySelectorAll('#content > blockquote > p')]
        .some(p => p.textContent.includes('Bare quote text')));

// B2b: Backspace at the start of the block after the quote merges into its last host
await caretIn('#content > blockquote + p', 0);
await page.keyboard.press('Backspace');
results.mergeIntoQuote = await page.evaluate(() => {
    const bq = document.querySelector('#content > blockquote');
    return {
        merged: bq?.querySelector(':scope > p')?.textContent.includes('Before'),
        hostGone: ![...document.querySelectorAll('#content > p')]
            .some(p => p.textContent.trim().replace('⣿', '') === 'Before'),
    };
});
await page.keyboard.press(undoKey);

// B2b: Backspace after a list merges into its last item
await load();
await caretIn('#content > ul + blockquote > p', 0); // move to a known spot first
await caretIn('#content > blockquote + p', 0);
await page.evaluate(() => { // place the caret at the start of the p after the fostered ul
    const p = [...document.querySelectorAll('#content > p')]
        .find(x => [...x.childNodes].some(n => n.nodeType === 3 && n.textContent.trim() === 'after'));
    p.focus();
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim());
    window.getSelection().collapse(t, 0);
});
await page.keyboard.press('Backspace');
results.mergeIntoList = await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.textContent.includes('parser-fostered list'));
    return { merged: !!li && li.textContent.includes('after') };
});

// ==== D. Tab dispatch in flow cells ================================================
await load();

// Tab from a paragraph inside a container cell traverses to the next cell
await page.evaluate(() => {
    const p = document.querySelector('#content td > p');
    p.focus();
    window.getSelection().collapse([...p.childNodes].find(n => n.nodeType === 3), 2);
});
await page.keyboard.press('Tab');
results.cellTab = await page.evaluate(() => {
    const plain = [...document.querySelectorAll('#content td')]
        .find(td => td.textContent.includes('Plain cell'));
    return { landedInNextCell: plain?.contains(window.getSelection().anchorNode) };
});

// ==== E. toolbar insert follows the caret context ==================================
// a numbered list inserts INSIDE the cell the caret is in, not after the table
await page.evaluate(() => {
    const td = [...document.querySelectorAll('#content td')]
        .find(t => t.textContent.includes('Plain cell'));
    td.focus();
    window.getSelection().collapse([...td.childNodes].find(n => n.nodeType === 3), 2);
});
await page.click('#edit-toolbar button.insert-list[data-list=ol]');
results.insertListInCell = await page.evaluate(() => {
    const td = [...document.querySelectorAll('#content td')]
        .find(t => t.textContent.includes('Plain cell'));
    return {
        nestedInCell: !!td.querySelector(':scope > ol > li'),
        cellIsContainer: td.getAttribute('contenteditable') !== 'true',
        textKeptAsRun: td.querySelector(':scope > p.rdfa-editor-run')?.textContent === 'Plain cell',
        runEditable: td.querySelector(':scope > p.rdfa-editor-run')?.getAttribute('contenteditable') === 'true',
        chromeOnCellList: !!td.querySelector(':scope > ol > [data-role=chrome]'),
        notAfterTable: !document.querySelector('#content > table + ol'),
        caretInNewItem: td.querySelector(':scope > ol > li').contains(window.getSelection().anchorNode)
            || td.querySelector(':scope > ol > li') === window.getSelection().anchorNode,
    };
});
// the original cell text must remain EDITABLE: type into it and verify
await page.evaluate(() => {
    const run = [...document.querySelectorAll('#content td > p.rdfa-editor-run')]
        .find(p => p.textContent.includes('Plain cell'));
    run.focus();
    window.getSelection().collapse([...run.childNodes].find(n => n.nodeType === 3), 5);
});
await page.keyboard.type('QQ');
results.insertListInCell.originalTextTypable = await page.evaluate(() =>
    [...document.querySelectorAll('#content td')].some(t => t.textContent.includes('PlainQQ cell')));
await page.waitForTimeout(1100);
await page.keyboard.press(undoKey); // the QQ burst
await page.keyboard.press(undoKey); // the list insert
results.insertListInCell.undone = await page.evaluate(() =>
    ![...document.querySelectorAll('#content td')].some(t => t.querySelector(':scope > ol')));

// Backspace at the start of the first item of a cell-nested list merges it back
// into the preceding line and dissolves the list (B4c)
await page.evaluate(() => {
    const td = [...document.querySelectorAll('#content td')]
        .find(t => t.textContent.includes('Plain cell'));
    td.focus();
    window.getSelection().collapse([...td.childNodes].find(n => n.nodeType === 3), 2);
});
await page.click('#edit-toolbar button.insert-list[data-list=ol]');
await page.keyboard.type('item text');
await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content td li')]
        .find(l => l.textContent.includes('item text'));
    li.focus();
    window.getSelection().collapse([...li.childNodes].find(n => n.nodeType === 3), 0);
});
await page.keyboard.press('Backspace');
results.backspaceDissolvesCellList = await page.evaluate(() => {
    const td = [...document.querySelectorAll('#content td')]
        .find(t => t.textContent.includes('Plain cell'));
    return {
        listGone: !td.querySelector('ol'),
        textMerged: td.textContent.includes('Plain cellitem text'),
        cellCollapsed: td.getAttribute('contenteditable') === 'true',
        noRunWrapperLeft: !td.querySelector('p.rdfa-editor-run'),
        caretAtJunction: td.contains(window.getSelection().anchorNode),
    };
});
// typing continues seamlessly at the junction
await page.keyboard.type('Z');
results.backspaceDissolvesCellList.typableAfter = await page.evaluate(() =>
    [...document.querySelectorAll('#content td')].some(t => t.textContent.includes('Plain cellZitem text')));
await page.waitForTimeout(1100);
await page.keyboard.press(undoKey); // the Z burst
await page.keyboard.press(undoKey); // the dissolve
await page.keyboard.press(undoKey); // the item typing
await page.keyboard.press(undoKey); // the list insert
results.backspaceDissolvesCellList.undoUnwinds = await page.evaluate(() =>
    [...document.querySelectorAll('#content td')].some(t =>
        t.getAttribute('contenteditable') === 'true' && t.textContent.trim() === 'Plain cell'
        && !t.querySelector('ol')));

// with the caret in a list item, the list nests inside the item
await caretInLi('Plain item', 1);
await page.click('#edit-toolbar button.insert-list[data-list=ul]');
results.insertListInLi = await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.textContent.includes('Plain item'));
    return { nestedInItem: !!li?.querySelector(':scope > ul > li') };
});
await page.keyboard.press(undoKey);

// at the top level the list still lands after the current block, with chrome
await caretIn('#content > p', 2);
await page.click('#edit-toolbar button.insert-list[data-list=ul]');
results.insertListTopLevel = await page.evaluate(() => {
    const ul = document.querySelector('#content > p + ul');
    return { afterBlock: !!ul, chrome: !!ul?.querySelector(':scope > [data-role=chrome]') };
});
await page.keyboard.press(undoKey);

// Tab on the single li inside a cell hits the list branch (flash no-op, no traversal)
const rowsBefore = await page.evaluate(() => document.querySelectorAll('#content table tr').length);
await page.evaluate(() => {
    const li = document.querySelector('#content td li');
    li.focus();
    window.getSelection().collapse([...li.childNodes].find(n => n.nodeType === 3), 1);
});
await page.keyboard.press('Tab');
results.liInCellTab = await page.evaluate(([rows]) => {
    const li = document.querySelector('#content td li');
    return {
        noTraversal: li.contains(window.getSelection().anchorNode),
        noRowGrowth: document.querySelectorAll('#content table tr').length === rows,
    };
}, [rowsBefore]);

// ==== F. review-fix regressions ====================================================
await load();

// F1: region-boundary clamp - Tab/quote in a region embedded in host-page
// li/table/blockquote must not touch the host structures
await caretIn('#embedded > p', 2);
const hostShape = () => page.evaluate(() => ({
    rows: document.querySelectorAll('#host-table tr').length,
    items: document.querySelectorAll('#host-list > li').length,
    regionInPlace: !!document.querySelector('#host-list > li > #embedded'),
    hostQuote: !!document.querySelector('body > blockquote > #host-table'),
}));
const before = await hostShape();
await page.keyboard.press('Tab');
await page.keyboard.press('Shift+Tab');
results.regionClamp = { hostUntouchedByTab: JSON.stringify(await hostShape()) === JSON.stringify(before) };
// the quote toggle must not read the host-page blockquote as "pressed"
await caretIn('#embedded > p', 2);
await page.waitForTimeout(100);
results.regionClamp.hostQuoteNotPressed = await page.evaluate(() =>
    document.querySelector('#edit-toolbar button.format-quote').getAttribute('aria-pressed') === 'false');
// toggling wraps INSIDE the region, never dissolves the host quote
await page.click('#edit-toolbar button.format-quote');
Object.assign(results.regionClamp, await page.evaluate(() => ({
    wrappedInRegion: !!document.querySelector('#embedded > blockquote > p'),
    hostQuoteIntact: !!document.querySelector('body > blockquote > #host-table'),
})));
await page.keyboard.press(undoKey);

// F2: B2b composite boundary - Backspace after a quote ENDING in a table is inert
await caretIn('#content > blockquote > p', -1);
await paste('#content > blockquote > p', '<table><tr><td>qcell</td></tr></table>');
await page.evaluate(() => { // drop the empty split half so the table is the quote's last block (B3)
    const p = [...document.querySelectorAll('#content > blockquote > p')].pop();
    p.focus();
    window.getSelection().collapse(p, 0);
});
await page.keyboard.press('Backspace');
await caretIn('#content > blockquote + p', 0);
await page.keyboard.press('Backspace');
results.compositeBoundary = await page.evaluate(() => ({
    quoteEndsWithTable: !!document.querySelector('#content > blockquote > table:last-child'),
    hostStays: [...document.querySelectorAll('#content > p')]
        .some(p => [...p.childNodes].some(n => n.nodeType === 3 && n.textContent.includes('Before'))),
    cellClean: [...document.querySelectorAll('#content blockquote td')]
        .every(td => !td.textContent.includes('Before')),
}));

// F3: E4b in a cell - exiting a sole-item list stays INSIDE the cell
await load();
await page.evaluate(() => {
    const td = [...document.querySelectorAll('#content td')].find(t => t.textContent.includes('Plain cell'));
    td.focus();
    window.getSelection().collapse([...td.childNodes].find(n => n.nodeType === 3), 2);
});
const regionBlocks = await page.evaluate(() => document.getElementById('content').children.length);
await page.click('#edit-toolbar button.insert-list[data-list=ul]');
await page.keyboard.press('Enter'); // E4b on the empty sole item
results.cellListExit = await page.evaluate(([n]) => {
    const td = [...document.querySelectorAll('#content td')].find(t => t.textContent.includes('Plain cell'));
    return {
        paragraphInCell: !!td.querySelector(':scope > p:not(.rdfa-editor-run)'),
        listGone: !td.querySelector('ul'),
        caretInCell: td.contains(window.getSelection().anchorNode),
        noRegionEndParagraph: document.getElementById('content').children.length === n,
    };
}, [regionBlocks]);
await page.keyboard.press(undoKey);
await page.keyboard.press(undoKey);

// F4: E6 nested - Enter in the figcaption of a figure pasted into an item
// starts the paragraph INSIDE the item, after the figure
await load();
await caretInLi('Plain item', -1);
await paste('#content > ul > li',
    '<figure><img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" alt="nested"/><figcaption>nested cap</figcaption></figure>');
await page.evaluate(() => {
    const cap = [...document.querySelectorAll('#content li figcaption')]
        .find(c => c.textContent.includes('nested cap'));
    cap.focus();
    window.getSelection().collapse([...cap.childNodes].find(n => n.nodeType === 3), 2);
});
await page.keyboard.press('Enter');
results.nestedCaptionEnter = await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')]
        .find(l => l.querySelector(':scope > figure'));
    return {
        paragraphInItem: !!li?.querySelector(':scope > figure + p'),
        caretInItem: li?.contains(window.getSelection().anchorNode),
    };
});

// F5: bare image island deletes ALONE, not its whole list
await load();
await caretInLi('Plain item', -1);
await paste('#content > ul > li',
    '<img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==" alt="island"/><ul><li>survivor</li></ul>');
await page.evaluate(() => {
    const img = [...document.querySelectorAll('#content li > img')].find(i => i.alt === 'island');
    img.focus();
});
await page.keyboard.press('Delete');
results.islandDelete = await page.evaluate(() => ({
    imageGone: ![...document.querySelectorAll('#content img')].some(i => i.alt === 'island'),
    listSurvives: [...document.querySelectorAll('#content li')].some(l => l.textContent.includes('survivor')),
    outerListSurvives: [...document.querySelectorAll('#content > ul > li')].some(l => l.textContent.includes('Plain item')),
}));

// F6: converting a nested host keeps the caret position
await load();
await caretIn('#content > blockquote > p', 4);
await page.evaluate(() => {
    const s = document.querySelector('#edit-toolbar select[name=block-type]');
    s.value = 'h2'; s.dispatchEvent(new Event('change', { bubbles: true }));
});
results.nestedConvertCaret = await page.evaluate(() => {
    const h2 = document.querySelector('#content > blockquote > h2');
    const sel = window.getSelection();
    return { converted: !!h2, caretKept: h2?.contains(sel.anchorNode) && sel.anchorOffset === 4 };
});

// F7: inserting at a figcaption nests inside the caption, not into the figure
await load();
await caretIn('#content figcaption', 2);
await page.click('#edit-toolbar button.insert-list[data-list=ol]');
results.figcaptionInsert = await page.evaluate(() => {
    const fig = document.querySelector('#content > figure');
    return {
        nestedInCaption: !!fig.querySelector(':scope > figcaption > ol > li'),
        figureNotGrown: fig.querySelectorAll(':scope > *:not([data-role])').length === 2, // img + figcaption
    };
});

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
const flat = JSON.stringify(results);
process.exit(errors.length || flat.includes('false') ? 1 : 0);
