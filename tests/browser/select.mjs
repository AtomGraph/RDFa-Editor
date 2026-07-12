// Region-scoped select-all and cross-host selection delete: two-stage Ctrl/Cmd+A
// (native in-host stage 1, whole-region stage 2, never the host page), one delete
// machine for stage-2 and mouse-sweep selections (Backspace/Delete from a host or
// from body), Google-Docs edge-remnant merge, composite (table/figure) grid
// preservation under partial sweeps, cross-region clamping, gesture suppression
// (typing/Enter/paste inert over a cross-host selection), and the I1-I5 invariants
// plus exact one-undo baseline restore after every mutating case
// (fixture-nesting.html).
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

// stage 1 relies on the browser's NATIVE select-all, which follows the platform
// modifier (CI is Linux; local macOS needs Meta) - the dispatcher accepts both
const selectAllKey = (process.platform === 'darwin' ? 'Meta' : 'Control') + '+a';
const undoKey = 'Control+z';

const load = async () => {
    await page.goto(BASE + '/tests/fixture-nesting.html');
    await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 })
        .catch(() => errors.push('chrome never injected'));
};
// caret inside the editable host whose direct text carries the needle
const caretIn = (needle, offset = 2) => page.evaluate(([txt, off]) => {
    const host = [...document.querySelectorAll('#content [contenteditable=true]')]
        .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
    if (!host) return false;
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
    window.getSelection().collapse(t, off === -1 ? t.textContent.length : off);
    return true;
}, [needle, offset]);
// a document-level range between two text offsets, located by needle (any region)
const sweep = (fromNeedle, fromOffset, toNeedle, toOffset) => page.evaluate(([fn, fo, tn, to]) => {
    const textIn = needle => {
        const host = [...document.querySelectorAll('[contenteditable=true]')]
            .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(needle)));
        return [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(needle));
    };
    const r = document.createRange();
    r.setStart(textIn(fn), fo);
    r.setEnd(textIn(tn), to);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
    return sel.toString().length > 0;
}, [fromNeedle, fromOffset, toNeedle, toOffset]);

// the I1-I5 net from invariants.mjs
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
    for (const r of region.querySelectorAll('.rdfa-editor-run')) {
        if (r.tagName !== 'P') v.push('run wrapper is ' + r.tagName.toLowerCase());
        if (r.getAttribute('contenteditable') !== 'true') v.push('uneditable run wrapper');
        if (r.parentElement === region) v.push('top-level run wrapper');
    }
    if (document.getElementById('lint-badge').style.display !== 'none')
        v.push('lint: ' + document.getElementById('lint-badge').textContent);
    return v;
});
const baselineOf = () => page.evaluate(() => document.getElementById('content').innerHTML);
// every mutating case must satisfy the invariants and unwind with ONE undo
const settle = async (name, baseline) => {
    const v = await invariants();
    if (v.length) errors.push(`${name} invariants: ${v.join('; ')}`);
    await page.keyboard.press(undoKey);
    return page.evaluate(html => document.getElementById('content').innerHTML === html, baseline);
};

// ==== A. two-stage Ctrl/Cmd+A =======================================================
await load();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
results.stage1 = await page.evaluate(() => {
    const sel = window.getSelection();
    const r = sel.getRangeAt(0);
    const host = n => (n.nodeType === 3 ? n.parentElement : n).closest('[contenteditable=true]');
    return {
        selectsHostText: sel.toString() === 'Intro paragraph.',
        confined: host(r.startContainer) === host(r.endContainer),
    };
});

await page.keyboard.press(selectAllKey);
results.stage2 = await page.evaluate(() => {
    const sel = window.getSelection();
    const r = sel.getRangeAt(0);
    const region = document.getElementById('content');
    return {
        regionLevel: r.startContainer === region && r.endContainer === region,
        coversFirst: sel.toString().includes('Nesting demo'),
        coversLast: sel.toString().includes('caption for gestures'),
        excludesEmbedded: !sel.toString().includes('Embedded paragraph'),
        excludesHostPage: !sel.toString().includes('host item before'),
    };
});

await page.keyboard.press(selectAllKey);
results.stage2Idempotent = await page.evaluate(() => {
    const r = window.getSelection().getRangeAt(0);
    const region = document.getElementById('content');
    return { still: r.startContainer === region && r.endContainer === region };
});

// an empty host escalates on the first press (nothing to select in-block)
await load();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
await page.keyboard.press('Backspace'); // within-host full selection: native delete empties the host
await page.keyboard.press(selectAllKey);
results.emptyHostEscalates = await page.evaluate(() => {
    const r = window.getSelection().getRangeAt(0);
    const region = document.getElementById('content');
    return { regionLevel: r.startContainer === region && r.endContainer === region };
});

// ==== B. stage 2 + Backspace empties and reseeds the region =========================
await load();
const baselineB = await baselineOf();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
await page.keyboard.press('Backspace');
results.deleteAll = await page.evaluate(() => {
    const region = document.getElementById('content');
    const blocks = [...region.children].filter(b => !b.hasAttribute('data-role'));
    const sel = window.getSelection();
    return {
        seeded: blocks.length === 1 && blocks[0].tagName === 'P'
            && blocks[0].getAttribute('contenteditable') === 'true'
            && !!blocks[0].querySelector(':scope > [data-role=chrome]')
            && !!blocks[0].querySelector(':scope > br'),
        caretInSeed: sel.rangeCount === 1 && sel.isCollapsed && blocks[0].contains(sel.anchorNode),
        embeddedIntact: document.getElementById('embedded').textContent.includes('Embedded paragraph'),
    };
});
results.deleteAll.undoRestores = await settle('deleteAll', baselineB);

// ==== C. sweep delete with edge-remnant merge (host-focus route) ====================
await load();
const baselineC = await baselineOf();
await sweep('Intro paragraph', 6, 'Plain item', 6); // "Intro |paragraph." -> "Plain |item"
await page.keyboard.press('Backspace');
results.sweepMerge = await page.evaluate(() => {
    const region = document.getElementById('content');
    const p = [...region.querySelectorAll(':scope > p')].find(x => x.textContent.includes('Intro'));
    const items = [...region.querySelector(':scope > ul').children].filter(c => c.tagName === 'LI');
    const sel = window.getSelection();
    return {
        merged: !!p && p.textContent.replace(/⠿/g, '') === 'Intro item',
        mergedItemGone: items.length === 2 && items[0].textContent.includes('Mixed item'),
        caretAtSeam: sel.isCollapsed && sel.anchorNode.textContent === 'item' && sel.anchorOffset === 0,
    };
});
results.sweepMerge.undoRestores = await settle('sweepMerge', baselineC);

// Delete-key parity
await load();
await sweep('Intro paragraph', 6, 'Plain item', 6);
await page.keyboard.press('Delete');
results.deleteKeyParity = await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('Intro'));
    return { merged: !!p && p.textContent.replace(/⠿/g, '') === 'Intro item' };
});
results.deleteKeyParity.undoRestores = await settle('deleteKeyParity', baselineC);

// same-list li -> li: items merge, the nested list keeps one item
await load();
const baselineC2 = await baselineOf();
await sweep('Sub one', 5, 'Sub two', 4);
await page.keyboard.press('Backspace');
results.sameListMerge = await page.evaluate(() => {
    const nested = document.querySelector('#content > ul > li > ul');
    const items = nested ? [...nested.children].filter(c => c.tagName === 'LI') : [];
    return { oneItem: items.length === 1, mergedText: items[0]?.textContent === 'Sub otwo' };
});
results.sameListMerge.undoRestores = await settle('sameListMerge', baselineC2);

// ==== D. body-focus route: region-level sweep, whole blocks removed ================
await load();
const baselineD = await baselineOf();
await page.evaluate(() => {
    if (document.activeElement) document.activeElement.blur();
    const region = document.getElementById('content');
    const kids = [...region.childNodes];
    const p = [...region.children].find(b => b.textContent.includes('Intro paragraph'));
    const ul = [...region.children].find(b => b.tagName === 'UL');
    const r = document.createRange();
    r.setStart(region, kids.indexOf(p));
    r.setEnd(region, kids.indexOf(ul) + 1);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
});
results.bodyRoute = { bodyFocused: await page.evaluate(() => document.activeElement === document.body) };
await page.keyboard.press('Backspace');
Object.assign(results.bodyRoute, await page.evaluate(() => {
    const region = document.getElementById('content');
    const sel = window.getSelection();
    return {
        blocksGone: !region.textContent.includes('Intro paragraph') && !region.textContent.includes('Plain item'),
        neighborsIntact: region.textContent.includes('Nesting demo')
            && region.textContent.includes('Bare quote text'),
        caretLanded: sel.rangeCount === 1 && sel.isCollapsed && region.contains(sel.anchorNode),
    };
}));
results.bodyRoute.undoRestores = await settle('bodyRoute', baselineD);

// ==== E. composites: partial sweeps clear cells, never the grid ====================
// "af|ter" paragraph -> "Plain |cell": the container cell (Cell para + cell item)
// is fully covered - cleared and collapsed to a text host; the boundary cell keeps
// its remnant; the grid survives; no merge across the table
await load();
const baselineE = await baselineOf();
await sweep('after', 2, 'Plain cell', 6);
await page.keyboard.press('Backspace');
results.compositePartial = await page.evaluate(() => {
    const region = document.getElementById('content');
    const table = region.querySelector(':scope > table');
    const cells = table ? [...table.querySelectorAll('td')] : [];
    const headP = [...region.querySelectorAll(':scope > p')].find(x => x.textContent.replace(/⠿/g, '') === 'af');
    const sel = window.getSelection();
    return {
        gridIntact: !!table && cells.length === 2 && !!table.querySelector('tbody > tr'),
        containerCellCollapsed: cells[0]?.getAttribute('contenteditable') === 'true'
            && !cells[0]?.querySelector('p, ul') && !!cells[0]?.querySelector('br'),
        boundaryCellRemnant: cells[1]?.textContent === 'cell',
        headRemnantKept: !!headP,
        noMerge: !headP?.textContent.includes('cell'),
        caretAtHeadEnd: sel.isCollapsed && !!headP && headP.contains(sel.anchorNode),
    };
});
results.compositePartial.undoRestores = await settle('compositePartial', baselineE);

// fully covered composite goes whole; a boundary inside the NEXT composite only
// clears content: "Quote |in item" -> "A caption |for gestures" removes the table
// but keeps figure, image and the caption remnant
await load();
const baselineE2 = await baselineOf();
await sweep('Quote in item', 6, 'A caption for gestures', 10);
await page.keyboard.press('Backspace');
results.compositeFull = await page.evaluate(() => {
    const region = document.getElementById('content');
    const figure = region.querySelector(':scope > figure');
    const quoteP = [...region.querySelectorAll('li blockquote p')]
        .find(x => x.textContent.replace(/⠿/g, '').startsWith('Quote'));
    return {
        tableGone: !region.querySelector(':scope > table'),
        middleBlocksGone: !region.textContent.includes('Bare quote text')
            && !region.textContent.includes('parser-fostered'),
        figureKept: !!figure && !!figure.querySelector('img'),
        captionRemnant: figure?.querySelector('figcaption')?.textContent === 'for gestures',
        headRemnant: quoteP?.textContent.replace(/⠿/g, '') === 'Quote ',
        noMergeAcrossFigure: !quoteP?.textContent.includes('for gestures'),
    };
});
results.compositeFull.undoRestores = await settle('compositeFull', baselineE2);

// ==== F. cross-region clamp: a sweep leaking into another region ===================
await load();
const baselineF = await baselineOf();
const embeddedBefore = await page.evaluate(() => document.getElementById('embedded').innerHTML);
await sweep('A caption for gestures', 2, 'Embedded quote', 6);
await page.keyboard.press('Backspace');
results.crossRegionClamp = await page.evaluate(html => {
    const region = document.getElementById('content');
    const figure = region.querySelector(':scope > figure');
    return {
        embeddedByteIdentical: document.getElementById('embedded').innerHTML === html,
        captionTruncated: figure?.querySelector('figcaption')?.textContent === 'A ',
        imageKept: !!figure?.querySelector('img'),
    };
}, embeddedBefore);
results.crossRegionClamp.undoRestores = await settle('crossRegionClamp', baselineF);

// ==== G. type-to-replace: a printable character replaces the selection ============
await load();
const baselineG = await baselineOf();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
await page.keyboard.type('x');
results.typeReplace = await page.evaluate(() => {
    const region = document.getElementById('content');
    const blocks = [...region.children].filter(b => !b.hasAttribute('data-role'));
    const sel = window.getSelection();
    return {
        replaced: blocks.length === 1 && blocks[0].tagName === 'P'
            && blocks[0].textContent.replace(/⠿/g, '') === 'x',
        caretAfterChar: sel.isCollapsed && sel.anchorNode.textContent === 'x' && sel.anchorOffset === 1,
    };
});
results.typeReplace.undoRestores = await settle('typeReplace', baselineG);

// sweep + type: the character lands at the merge seam
await load();
await sweep('Intro paragraph', 6, 'Plain item', 6);
await page.keyboard.type('Z');
results.typeReplaceSweep = await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('Intro'));
    return { seamChar: !!p && p.textContent.replace(/⠿/g, '') === 'Intro Zitem' };
});
results.typeReplaceSweep.undoRestores = await settle('typeReplaceSweep', baselineG);

// Enter/Tab/paste stay suppressed; the selection survives them
await load();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
const beforeSuppress = await baselineOf();
await page.keyboard.press('Enter');
await page.keyboard.press('Tab');
await page.evaluate(() => {
    const dt = new DataTransfer();
    dt.setData('text/html', '<p>pasted</p>');
    dt.setData('text/plain', 'pasted');
    document.querySelector('#content [contenteditable=true]').dispatchEvent(
        new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
});
results.suppression = {
    inert: await page.evaluate(html => document.getElementById('content').innerHTML === html, beforeSuppress),
    selectionSurvives: await page.evaluate(() => {
        const r = window.getSelection().getRangeAt(0);
        return r.startContainer === document.getElementById('content');
    }),
};

// ==== J. canonical copy / cut ======================================================
// copy of a stage-2 selection: the clipboard gets the storage form, not the
// editing DOM - no chrome/contenteditable/marker classes, RDFa attributes kept
await load();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
const copied = await page.evaluate(() => {
    const dt = new DataTransfer();
    document.activeElement.dispatchEvent(
        new ClipboardEvent('copy', { clipboardData: dt, bubbles: true, cancelable: true }));
    return { html: dt.getData('text/html'), plain: dt.getData('text/plain') };
});
results.canonicalCopy = {
    intercepted: copied.html.length > 0,
    noChrome: !copied.html.includes('data-role') && !copied.html.includes('⠿'),
    noEditingAttrs: !copied.html.includes('contenteditable') && !copied.html.includes('rdfa-editor'),
    rdfaKept: copied.html.includes('property="http://purl.org/dc/terms/title"'),
    blocksKept: copied.html.includes('<h1') && copied.html.includes('<table') && copied.html.includes('<figure'),
    plainText: copied.plain.startsWith('Nesting demo') && copied.plain.includes('Plain item'),
    contentUntouched: await page.evaluate(() =>
        document.getElementById('content').textContent.includes('Intro paragraph.')),
};

// within-host copy stays native (no interception, clipboardData untouched by us)
await load();
await caretIn('Intro paragraph', 3);
await page.keyboard.press(selectAllKey); // stage 1: within-host
results.nativeCopyWithinHost = {
    notIntercepted: await page.evaluate(() => {
        const dt = new DataTransfer();
        const e = new ClipboardEvent('copy', { clipboardData: dt, bubbles: true, cancelable: true });
        document.activeElement.dispatchEvent(e);
        return !e.defaultPrevented && dt.getData('text/html') === '';
    }),
};

// cut: clipboard set AND the selection deleted with merge, one undo restores
await load();
const baselineJ = await baselineOf();
await sweep('Intro paragraph', 6, 'Plain item', 6);
const cutData = await page.evaluate(() => {
    const dt = new DataTransfer();
    document.activeElement.dispatchEvent(
        new ClipboardEvent('cut', { clipboardData: dt, bubbles: true, cancelable: true }));
    return { html: dt.getData('text/html') };
});
results.canonicalCut = {
    clipboardSet: cutData.html.includes('paragraph.') && cutData.html.includes('Plain'),
    deletedAndMerged: await page.evaluate(() => {
        const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('Intro'));
        return !!p && p.textContent.replace(/⠿/g, '') === 'Intro item';
    }),
};
results.canonicalCut.undoRestores = await settle('canonicalCut', baselineJ);

// ==== H. Ctrl+A away from any caret selects the editor, never the page =============
// fresh load, focus on body, no selection: the first region is selected
await load();
await page.evaluate(() => {
    if (document.activeElement) document.activeElement.blur();
    window.getSelection().removeAllRanges();
});
await page.keyboard.press(selectAllKey);
results.bodyCtrlA = await page.evaluate(() => {
    const sel = window.getSelection();
    const r = sel.getRangeAt(0);
    const region = document.getElementById('content');
    return {
        selectsFirstRegion: r.startContainer === region && r.endContainer === region,
        excludesHostPage: !sel.toString().includes('host item before'),
    };
});

// the last engaged region wins (local:active-root activeBlock precedence)
await load();
await page.evaluate(() => {
    const host = [...document.querySelectorAll('#embedded [contenteditable=true]')]
        .find(el => el.textContent.includes('Embedded paragraph'));
    host.focus();
    document.activeElement.blur();
    window.getSelection().removeAllRanges();
});
await page.keyboard.press(selectAllKey);
results.bodyCtrlAActiveRegion = await page.evaluate(() => {
    const r = window.getSelection().getRangeAt(0);
    const embedded = document.getElementById('embedded');
    return { selectsEngagedRegion: r.startContainer === embedded && r.endContainer === embedded };
});

// ==== I. focused image island: Ctrl+A is stage 2, Backspace then runs the machine ==
await load();
const baselineI = await baselineOf();
await page.evaluate(() => document.querySelector('#content figure img').focus());
await page.keyboard.press(selectAllKey);
results.imageCtrlA = await page.evaluate(() => {
    const r = window.getSelection().getRangeAt(0);
    const region = document.getElementById('content');
    return { selectsRegion: r.startContainer === region && r.endContainer === region };
});
await page.keyboard.press('Backspace');
results.imageCtrlA.deletesSelection = await page.evaluate(() => {
    const region = document.getElementById('content');
    const blocks = [...region.children].filter(b => !b.hasAttribute('data-role'));
    return blocks.length === 1 && blocks[0].tagName === 'P'; // seeded, not figure-only delete
});
results.imageCtrlA.undoRestores = await settle('imageCtrlA', baselineI);

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
const flat = JSON.stringify(results);
process.exit(errors.length || flat.includes('false') ? 1 : 0);
