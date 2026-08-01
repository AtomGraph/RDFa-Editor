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
    const BLOCK = new Set(['P', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'DIV', 'UL', 'OL', 'DL',
        'PRE', 'BLOCKQUOTE', 'ADDRESS', 'FIELDSET', 'TABLE', 'FIGURE']);
    const FLOW = new Set(['LI', 'DD', 'TD', 'TH', 'DIV', 'FIGURE', 'FIGCAPTION']);
    for (const c of region.querySelectorAll('[data-role=chrome]')) {
        const b = c.parentElement;
        const ok = BLOCK.has(b.tagName) && !b.classList.contains('rdfa-editor-run')
            && (b.parentElement === region || FLOW.has(b.parentElement.tagName)
                || b.parentElement.tagName === 'BLOCKQUOTE');
        if (!ok) v.push('stray chrome in: ' + b.tagName.toLowerCase());
    }
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

// the last engaged region wins (rdfae:active-root activeBlock precedence)
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

// ==== K. real gestures: drag takeover, Shift+Click, Shift+Up/Down ==================
// everything above builds ranges programmatically (the machinery); these cases
// assert the GESTURES produce them. Chromium clamps a native drag-selection to
// the host it starts in, so the select.xsl mousemove takeover is what makes
// these pass - they fail on a build without the gesture layer.

// viewport point of a character offset within the host containing needle (-1 = end)
const pointAt = (needle, off) => page.evaluate(([n, o]) => {
    const host = [...document.querySelectorAll('[contenteditable=true]')]
        .find(el => [...el.childNodes].some(t => t.nodeType === 3 && t.textContent.includes(n)));
    const t = [...host.childNodes].find(t => t.nodeType === 3 && t.textContent.includes(n));
    const r = document.createRange();
    r.setStart(t, o === -1 ? t.textContent.length : o);
    r.collapse(true);
    const rect = r.getBoundingClientRect();
    return { x: rect.x, y: rect.y + rect.height / 2 };
}, [needle, off]);

const dragReal = async (from, to) => {
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    for (let i = 1; i <= 8; i++)
        await page.mouse.move(from.x + (to.x - from.x) * i / 8, from.y + (to.y - from.y) * i / 8);
    await page.mouse.up();
};

// anchor/focus hosts and range text; sel.toString() truncates at the first host
// boundary in Chromium, so extent is asserted via the RANGE
const selInfo = () => page.evaluate(() => {
    const sel = window.getSelection();
    if (!sel.rangeCount) return { crosses: false, rangeText: '' };
    const hostOf = n => { const el = n.nodeType === 1 ? n : n.parentElement; return el.closest('[contenteditable=true]'); };
    const a = hostOf(sel.anchorNode), f = hostOf(sel.focusNode);
    return {
        collapsed: sel.isCollapsed,
        crosses: !sel.isCollapsed && (a !== f || !a || !f),
        anchorText: a ? a.textContent.replace(/⠿/g, '').trim() : '(region)',
        focusText: f ? f.textContent.replace(/⠿/g, '').trim() : '(region)',
        rangeText: sel.getRangeAt(0).toString().replace(/⠿/g, ''),
        disarmed: window.rdfaEditor.sweepAnchorNode == null,
    };
});

// K1: a real drag across three blocks paints one selection
await load();
{
    await dragReal(await pointAt('Intro paragraph', 6), await pointAt('Sub two', 4));
    const s = await selInfo();
    results.realDrag = {
        crosses: s.crosses,
        spansBlocks: s.rangeText.includes('paragraph.') && s.rangeText.includes('Plain item')
            && s.rangeText.includes('Sub one'),
        disarmedOnMouseup: s.disarmed,
    };
}

// K2: real drag + Backspace = the same edge-remnant merge as the programmatic sweep
// (pointer-to-offset resolution is approximate: assertions tolerate a char or two)
await load();
const baselineK = await baselineOf();
{
    await dragReal(await pointAt('Intro paragraph', 6), await pointAt('Plain item', 6));
    await page.keyboard.press('Backspace');
    results.realDragDelete = await page.evaluate(() => {
        const region = document.getElementById('content');
        const p = [...region.querySelectorAll(':scope > p')].find(x => x.textContent.includes('Intro'));
        const items = [...region.querySelector(':scope > ul').children].filter(c => c.tagName === 'LI');
        const sel = window.getSelection();
        const text = p ? p.textContent.replace(/⠿/g, '') : '';
        return {
            merged: !!p && text.startsWith('Intro') && text.endsWith('item')
                && !text.includes('paragraph'),
            firstItemGone: items.length === 2 && items[0].textContent.includes('Mixed item'),
            caretCollapsed: sel.rangeCount === 1 && sel.isCollapsed,
        };
    });
    results.realDragDelete.undoRestores = await settle('realDragDelete', baselineK);
}

// K3: a backward (upward) drag keeps the anchor fixed - Docs semantics
await load();
{
    await dragReal(await pointAt('Plain item', 6), await pointAt('Intro paragraph', 6));
    const s = await selInfo();
    results.backwardDrag = {
        crosses: s.crosses,
        anchorStaysAtStart: s.anchorText.includes('Plain item'),
        focusAtDragEnd: s.focusText.includes('Intro'),
    };
    await page.keyboard.press('Delete');
    results.backwardDrag.deletes = await page.evaluate(() => {
        const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('Intro'));
        return !!p && p.textContent.endsWith('item') && !p.textContent.includes('paragraph');
    });
    results.backwardDrag.undoRestores = await settle('backwardDrag', baselineK);
}

// K4: an in-host drag stays native and confined
await load();
{
    await dragReal(await pointAt('Intro paragraph', 0), await pointAt('Intro paragraph', 10));
    const s = await selInfo();
    results.inHostDrag = {
        selected: !s.collapsed && s.rangeText.length > 0,
        confined: !s.crosses && s.anchorText.includes('Intro') && s.focusText.includes('Intro'),
        disarmedOnMouseup: s.disarmed,
    };
}

// K5: a drag from the region's gutter (padding, left of the text) sweeps blocks
await load();
{
    const from = await page.evaluate(() => {
        const region = document.getElementById('content');
        const p = [...region.children].find(b => b.textContent.includes('Intro paragraph'));
        const rp = p.getBoundingClientRect();
        return { x: region.getBoundingClientRect().x + 8, y: rp.y + rp.height / 2 };
    });
    await dragReal(from, await pointAt('Plain item', 6));
    results.gutterDrag = { crosses: (await selInfo()).crosses };
}

// K6: Shift+Click extends from the caret; a second Shift+Click keeps the anchor
await load();
{
    await caretIn('Intro paragraph', 6);
    await page.keyboard.down('Shift');
    await page.mouse.click(...Object.values(await pointAt('Plain item', 6)));
    await page.keyboard.up('Shift');
    const first = await selInfo();
    await page.keyboard.down('Shift');
    await page.mouse.click(...Object.values(await pointAt('Bare quote', 5)));
    await page.keyboard.up('Shift');
    const second = await selInfo();
    results.shiftClick = {
        extends: first.crosses && first.anchorText.includes('Intro'),
        anchorSurvivesSecond: second.crosses && second.anchorText.includes('Intro')
            && second.focusText.includes('Bare quote'),
    };
}

// K7: Shift+Click then typing replaces the selection (one undo entry)
await load();
{
    await caretIn('Intro paragraph', 6);
    await page.keyboard.down('Shift');
    await page.mouse.click(...Object.values(await pointAt('Plain item', 6)));
    await page.keyboard.up('Shift');
    await page.keyboard.press('X');
    results.shiftClickType = await page.evaluate(() => {
        const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('Intro'));
        const sel = window.getSelection();
        const text = p ? p.textContent.replace(/⠿/g, '') : '';
        return {
            replaced: !!p && text.startsWith('Intro') && text.includes('X')
                && !text.includes('paragraph'),
            caretCollapsed: sel.rangeCount === 1 && sel.isCollapsed,
        };
    });
    results.shiftClickType.undoRestores = await settle('shiftClickType', baselineK);
}

// K8: Shift+Down at the host end steps block-wise; Shift+Up steps back
await load();
{
    await caretIn('Intro paragraph', -1);
    await page.keyboard.press('Shift+ArrowDown');
    const one = await selInfo();
    await page.keyboard.press('Shift+ArrowDown');
    const two = await selInfo();
    await page.keyboard.press('Shift+ArrowUp');
    const back = await selInfo();
    results.shiftArrows = {
        firstCrosses: one.crosses,
        secondTakesList: two.rangeText.includes('Plain item') && two.rangeText.includes('Sub two'),
        upReleasesList: !back.rangeText.includes('Plain item'),
        baselineIntact: await page.evaluate(html =>
            document.getElementById('content').innerHTML === html, baselineK),
    };
}

// K9: a drag toward another region clamps to the region it started in
await load();
{
    const to = await page.evaluate(() => {
        const p = [...document.querySelectorAll('#embedded [contenteditable=true]')]
            .find(el => el.textContent.includes('Embedded paragraph'));
        const r = p.getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    await dragReal(await pointAt('Intro paragraph', 6), to);
    // Chromium may remap the region-level focus to the nearest editing position
    // INSIDE the region - equally clamped; assert containment, not identity
    results.dragRegionClamp = await page.evaluate(() => {
        const sel = window.getSelection();
        const embedded = document.getElementById('embedded');
        const region = document.getElementById('content');
        return {
            crosses: !sel.isCollapsed,
            clampedToStartRegion: sel.focusNode === region || region.contains(sel.focusNode),
            embeddedUntouched: !sel.getRangeAt(0).intersectsNode(embedded),
        };
    });
}

// K10: a press on the drag handle never arms a sweep (block reordering intact)
await load();
{
    const handle = await page.evaluate(() => {
        const h = document.querySelector('#content > h1 > [data-role=chrome]');
        const r = h.getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    await page.mouse.move(handle.x, handle.y);
    await page.mouse.down();
    const to = await pointAt('Plain item', 6);
    for (let i = 1; i <= 4; i++)
        await page.mouse.move(handle.x + (to.x - handle.x) * i / 4, handle.y + (to.y - handle.y) * i / 4);
    results.handleNotHijacked = {
        neverArmed: await page.evaluate(() => window.rdfaEditor.sweepAnchorNode == null),
        noSweepSelection: !(await selInfo()).crosses,
    };
    await page.mouse.up();
}

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
const flat = JSON.stringify(results);
process.exit(errors.length || flat.includes('false') ? 1 : 0);
