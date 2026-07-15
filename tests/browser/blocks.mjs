// Object blocks (LDH extension): RDF-defined blocks embedded as atomic RDFa
// islands wherever the content model admits a div. Runs against
// fixture-blocks.html (the ldh-editor SEF): a top-level ResultSetChart and a
// View nested in a list item, hydrated by conneg fetches (run.mjs negotiates).
// Asserts init/locking, the storage-form round-trip, island navigation and
// deletion, hard boundaries, dialog insertion (top-level and nested), the
// stage-2/sweep delete machine, canonical copy, and the invariants after every
// mutation.
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';
const selectAllKey = process.platform === 'darwin' ? 'Meta+a' : 'Control+a';
const undoKey = process.platform === 'darwin' ? 'Meta+z' : 'Control+z';

const errors = [];
const results = {};
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

const CHART = '#content > div.rdfa-editor-island';
const NESTED = '#content li div.rdfa-editor-island';

// load and let both islands hydrate, so undo baselines are render-stable
const load = async () => {
    await page.goto(BASE + '/tests/fixture-blocks.html');
    await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 });
    await page.waitForSelector(`${CHART} [data-role=rendering] table tbody tr`, { state: 'attached', timeout: 15000 });
    await page.waitForSelector(`${NESTED} [data-role=rendering] table`, { state: 'attached', timeout: 15000 });
};
const caretIn = (needle, offset = 2) => page.evaluate(([txt, off]) => {
    const host = [...document.querySelectorAll('#content [contenteditable=true]')]
        .find(el => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(txt)));
    if (!host) return false;
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.includes(txt));
    window.getSelection().collapse(t, off === -1 ? t.textContent.length : off);
    return true;
}, [needle, offset]);
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
const invariants = () => page.evaluate(() => {
    const v = [];
    const region = document.getElementById('content');
    const walker = document.createTreeWalker(region, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) {
        if (!n.textContent.trim()) continue;
        if (n.parentElement.closest('[data-role]')) continue;
        if (n.parentElement.closest('.rdfa-editor-island')) continue; // island definition spans are locked, not hosted
        if (!n.parentElement.closest('[contenteditable=true]'))
            v.push('orphan text: "' + n.textContent.trim().slice(0, 30) + '"');
    }
    for (const h of region.querySelectorAll('[contenteditable=true] [contenteditable=true]'))
        v.push('nested host: ' + h.tagName.toLowerCase());
    for (const h of region.querySelectorAll('.rdfa-editor-island [contenteditable=true]'))
        v.push('editable inside island: ' + h.tagName.toLowerCase());
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
    if (document.getElementById('lint-badge').style.display !== 'none')
        v.push('lint: ' + document.getElementById('lint-badge').textContent);
    return v;
});
const clean = async name => {
    const v = await invariants();
    assert(name + '.invariants', v.length === 0);
    if (v.length) errors.push(`${name}: ${v.join('; ')}`);
};
const islandState = sel => page.evaluate(s => {
    const isl = document.querySelector(s);
    if (!isl) return null;
    return {
        editable: isl.getAttribute('contenteditable'),
        tabindex: isl.getAttribute('tabindex'),
        spans: isl.querySelectorAll(':scope > span[property]').length,
        renderings: isl.querySelectorAll(':scope > div[data-role=rendering]').length,
        rows: isl.querySelectorAll('[data-role=rendering] tbody tr').length,
        chrome: isl.querySelectorAll(':scope > span[data-role=chrome]').length,
        loading: isl.classList.contains('rdfa-editor-loading'),
        focused: document.activeElement === isl,
    };
}, sel);

// ==== A. init: islands locked, rendered, chrome on every draggable block =========
await load();
const chartInit = await islandState(CHART);
assert('init.chart.locked', chartInit.editable === null && chartInit.tabindex === '-1');
assert('init.chart.spansIntact', chartInit.spans === 4);
assert('init.chart.rendered', chartInit.renderings === 1 && chartInit.rows === 5 && !chartInit.loading);
assert('init.chart.chrome', chartInit.chrome === 1);
assert('init.chart.heading', await page.evaluate(s =>
    document.querySelector(s + ' [data-role=rendering] strong')?.textContent === 'BarChart · country × population', CHART));
const nestedInit = await islandState(NESTED);
assert('init.nested.locked', nestedInit.editable === null && nestedInit.tabindex === '-1');
assert('init.nested.rendered', nestedInit.renderings === 1 && !nestedInit.loading);
assert('init.nested.chrome', nestedInit.chrome === 1);
assert('init.nested.liContainer', await page.evaluate(() => {
    const li = document.querySelector('#content li div.rdfa-editor-island').closest('li');
    return li.getAttribute('contenteditable') !== 'true'
        && !!li.querySelector(':scope > p.rdfa-editor-run[contenteditable=true]');
}));
await clean('init');

// ==== B. round-trip: view-source shows the clean placeholder =====================
await page.click('#view-source');
await page.waitForTimeout(200);
const source = await page.evaluate(() => document.getElementById('output-content').textContent);
assert('roundtrip.placeholderKept', source.includes('about="#chart"')
    && source.includes('typeof="https://w3id.org/atomgraph/linkeddatahub#ResultSetChart"')
    && source.includes('property="http://spinrdf.org/spin#query"')
    && source.includes('about="#nested-view"')
    && source.includes('>country</span>'));
assert('roundtrip.ephemeraGone', !source.includes('data-role') && !source.includes('tabindex')
    && !source.includes('rdfa-editor-island') && !source.includes('contenteditable'));

// ==== C. navigation: arrows select the island, Backspace deletes it, undo ========
await load();
await caretIn('Before chart', -1);
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(80);
assert('nav.arrowSelects', (await islandState(CHART)).focused);
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(80);
assert('nav.arrowLeaves', await page.evaluate(() =>
    document.activeElement.textContent.includes('After chart.')));
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(80);
assert('nav.arrowBack', (await islandState(CHART)).focused);
await page.keyboard.press('Backspace');
await page.waitForTimeout(120);
assert('nav.deleteRemovesWhole', await page.evaluate(() =>
    !document.querySelector('#content div[typeof*="ResultSetChart"]')
    && !document.querySelector('#content > span[property]')));
await clean('nav.delete');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
const afterUndo = await islandState(CHART);
assert('nav.undoRestores', !!afterUndo && afterUndo.spans === 4 && afterUndo.renderings === 1
    && afterUndo.editable === null && afterUndo.tabindex === '-1');
await clean('nav.undo');

// ==== D. hard boundary: Backspace-at-start after an island =======================
await load();
await caretIn('After chart', 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(100);
assert('boundary.inert', await page.evaluate(() =>
    [...document.querySelectorAll('#content > p')].some(p => p.textContent.includes('After chart.'))
    && !!document.querySelector('#content div[typeof*="ResultSetChart"]')));
// emptied host: Backspace removes it and SELECTS the island (B3)
await page.evaluate(() => {
    const host = [...document.querySelectorAll('#content > p')].find(p => p.textContent.includes('After chart.'));
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3);
    const r = document.createRange();
    r.setStart(t, 0); r.setEnd(t, t.textContent.length);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
});
await page.keyboard.press('Backspace');
await page.waitForTimeout(100);
await page.keyboard.press('Backspace');
await page.waitForTimeout(120);
assert('boundary.emptyHostRemovedIslandSelected', await page.evaluate(() =>
    ![...document.querySelectorAll('#content > p')].some(p => p.textContent.includes('After chart.'))
    && document.activeElement === document.querySelector('#content div[typeof*="ResultSetChart"]')));
await clean('boundary');

// ==== E. slash-menu insert (top level) ============================================
await load();
await caretIn('Tail paragraph', -1);
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
await page.keyboard.type('/');
await page.waitForTimeout(150);
assert('slash.itemOffered', await page.evaluate(() => {
    const li = document.querySelector('#slash-menu li[data-command="ldh-block"]');
    return !!li && getComputedStyle(li).display !== 'none';
}));
await page.click('#slash-menu li[data-command="ldh-block"]');
await page.waitForTimeout(120);
assert('slash.dialogOpens', await page.evaluate(() =>
    getComputedStyle(document.getElementById('ldh-block-dialog')).display !== 'none'));
await page.selectOption('#ldh-block-dialog select[name="block-type-iri"]', 'https://w3id.org/atomgraph/linkeddatahub#View');
await page.fill('#ldh-block-dialog input[name="about"]', '#t-view');
await page.fill('#ldh-block-dialog input[name="view-query"]', '../demo/queries/population/#this');
await page.click('#ldh-block-dialog button.ldh-block-save');
await page.waitForTimeout(150);
assert('slash.inserted', await page.evaluate(() => {
    const isl = document.querySelector('#content > div[about="#t-view"]');
    return !!isl && isl.classList.contains('rdfa-editor-island')
        && isl.getAttribute('contenteditable') === null
        && document.activeElement === isl
        && !!isl.querySelector(':scope > span[data-role=chrome]');
}));
await page.waitForSelector('#content > div[about="#t-view"] [data-role=rendering] table', { state: 'attached', timeout: 15000 });
assert('slash.hydrates', true);
await clean('slash.insert');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
assert('slash.undo', await page.evaluate(() => !document.querySelector('#content div[about="#t-view"]')));

// ==== F. toolbar insert inside a list item (nested placement) =====================
await load();
await caretIn('Item before', -1);
await page.click('#edit-toolbar button.insert-ldh-block');
await page.waitForTimeout(120);
await page.fill('#ldh-block-dialog input[name="about"]', '#t-obj');
await page.fill('#ldh-block-dialog input[name="object-value"]', '../demo/resources/ada/#this');
await page.click('#ldh-block-dialog button.ldh-block-save');
await page.waitForTimeout(150);
assert('toolbar.nestedInsert', await page.evaluate(() => {
    const isl = document.querySelector('#content div[about="#t-obj"]');
    if (!isl) return false;
    const li = isl.closest('li');
    return !!li && li.getAttribute('contenteditable') !== 'true'
        && !!li.querySelector(':scope > p.rdfa-editor-run')
        && !!isl.querySelector(':scope > span[data-role=chrome]');
}));
await page.waitForSelector('#content div[about="#t-obj"] [data-role=rendering] table', { state: 'attached', timeout: 15000 });
assert('toolbar.nestedHydrates', await page.evaluate(() =>
    document.querySelector('#content div[about="#t-obj"] [data-role=rendering] strong')?.textContent === 'Ada Lovelace'));
await clean('toolbar.insert');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
assert('toolbar.undo', await page.evaluate(() => !document.querySelector('#content div[about="#t-obj"]')
    && [...document.querySelectorAll('#content li')].some(li => li.getAttribute('contenteditable') === 'true'
        && li.textContent.includes('Item before'))));

// ==== G. delete machine: stage-2 select-all and sweeps ============================
await load();
await caretIn('Before chart', 2);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
await page.keyboard.press('Delete');
await page.waitForTimeout(150);
assert('stage2.reseeded', await page.evaluate(() => {
    const blocks = [...document.getElementById('content').children].filter(el => !el.dataset.role);
    return blocks.length === 1 && blocks[0].tagName === 'P'
        && !document.querySelector('#content .rdfa-editor-island')
        && !document.querySelector('#content span[property]');
}));
await clean('stage2.delete');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
assert('stage2.undo', await page.evaluate(() =>
    document.querySelectorAll('#content .rdfa-editor-island').length === 2
    && !!document.querySelector('#content .rdfa-editor-island [data-role=rendering] table')));
await clean('stage2.undo');

await load();
await sweep('Before chart', 3, 'After chart', 5);
await page.keyboard.press('Backspace');
await page.waitForTimeout(150);
assert('sweep.coveredIslandRemovedWhole', await page.evaluate(() =>
    !document.querySelector('#content div[typeof*="ResultSetChart"]')
    && !document.querySelector('#content > span[property]')
    && [...document.querySelectorAll('#content > p')].some(p => p.textContent.replace(/⠿/g, '') === 'Bef chart.')
    && !!document.querySelector('#content li div[typeof*="View"]')));
await clean('sweep.delete');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
assert('sweep.undo', await page.evaluate(() =>
    document.querySelectorAll('#content .rdfa-editor-island').length === 2));

// ==== H. canonical copy carries the storage form ==================================
await load();
await caretIn('Before chart', 2);
await page.keyboard.press(selectAllKey);
await page.keyboard.press(selectAllKey);
const copied = await page.evaluate(() => {
    const dt = new DataTransfer();
    document.activeElement.dispatchEvent(
        new ClipboardEvent('copy', { clipboardData: dt, bubbles: true, cancelable: true }));
    return dt.getData('text/html');
});
assert('copy.placeholderKept', copied.includes('typeof="https://w3id.org/atomgraph/linkeddatahub#ResultSetChart"')
    && copied.includes('property="http://spinrdf.org/spin#query"'));
assert('copy.ephemeraGone', !copied.includes('data-role') && !copied.includes('tabindex')
    && !copied.includes('rdfa-editor-island') && !copied.includes('contenteditable'));

// ==== I. breadcrumb + toolbar state on a selected island ==========================
await load();
await caretIn('Before chart', -1);
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(150);
assert('toolbarState.breadcrumb', await page.evaluate(() => {
    const crumbs = [...document.querySelectorAll('.crumb')];
    return crumbs.length > 0 && crumbs[crumbs.length - 1].textContent.startsWith('div[');
}));
assert('toolbarState.blockTypeDisabled', await page.evaluate(() =>
    document.querySelector('#edit-toolbar select[name="block-type"]').disabled === true));

console.log(JSON.stringify({ results, errors: errors.slice(0, 8) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
