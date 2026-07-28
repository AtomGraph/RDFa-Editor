import { chromium } from 'playwright';
import { typeIri, committedIri } from './typeahead-helper.mjs';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#rdfa-editor-overlay', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('overlay never rendered'));
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 5000 })
    .catch(() => errors.push('chrome never injected'));

const FOAF = 'http://xmlns.com/foaf/0.1/';
const TITLE = 'http://purl.org/dc/terms/title';
const pWrap = '#rdfa-editor-overlay .typeahead-field[data-field=property]';
const tWrap = '#rdfa-editor-overlay .typeahead-field[data-field=typeof]';
const pIn = `${pWrap} input.typeahead-input`;
const menuOpen = (w) => page.evaluate(s =>
    getComputedStyle(document.querySelector(s + ' .typeahead-menu')).display !== 'none', w);
const activeUri = (w) => page.evaluate(s =>
    document.querySelector(s + ' .typeahead-option[aria-selected=true]')?.getAttribute('data-uri') ?? '', w);
const optionCount = (w) => page.locator(w + ' .typeahead-option').count();

// select the first occurrence of a substring within a single #content text node
const selectText = (substr) => page.evaluate(s => {
    const walker = document.createTreeWalker(document.getElementById('content'), NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
        const i = node.textContent.indexOf(s);
        if (i >= 0) {
            node.parentElement.closest('[contenteditable=true]')?.focus();
            const range = document.createRange();
            range.setStart(node, i); range.setEnd(node, i + s.length);
            const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
            return true;
        }
    }
    return false;
}, substr);

// right-click the centre of the current selection to open the overlay
const rightClickSelection = async () => {
    const box = await page.evaluate(() => {
        const sel = window.getSelection();
        const el = sel.anchorNode.nodeType === 3 ? sel.anchorNode.parentElement : sel.anchorNode;
        el.scrollIntoView({ block: 'center' });
        const r = sel.getRangeAt(0).getBoundingClientRect();
        return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    });
    await page.mouse.click(box.x, box.y, { button: 'right' });
    await page.waitForTimeout(250);
};

const annotate = async (substr) => { await selectText(substr); await rightClickSelection(); };
const cancel = async () => { await page.click('#rdfa-editor-overlay button.cancel-action'); await page.waitForTimeout(80); };

// select an existing annotation (the h1 that carries @property=dct:title) and open it
const openTitleEdit = async () => {
    await page.evaluate(() => {
        const h1 = document.querySelector('#content > h1');
        h1.closest('[contenteditable=true]')?.focus();
        const range = document.createRange(); range.selectNodeContents(h1);
        const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
    });
    await rightClickSelection();
};

// ---- 1. typing filters the list down to the matches, menu shown -----------------
await annotate('official');
await page.fill(pIn, 'know');
await page.waitForTimeout(120);
assert('filter.knowsShown', await page.locator(`${pWrap} .typeahead-option[data-uri="${FOAF}knows"]`).count() === 1);
assert('filter.menuOpen', await menuOpen(pWrap));
const narrow = await optionCount(pWrap);
await page.fill(pIn, '');
await page.waitForTimeout(120);
const broad = await optionCount(pWrap);
assert('filter.narrows', narrow >= 1 && narrow < broad);

// ---- 2. keyboard: ArrowDown moves the active option, Enter commits it ------------
await page.fill(pIn, 'a');
await page.waitForTimeout(120);
const first = await activeUri(pWrap);
await page.press(pIn, 'ArrowDown');
const second = await activeUri(pWrap);
assert('keyboard.arrowMoves', first !== '' && second !== '' && first !== second);
await page.press(pIn, 'Enter');
await page.waitForTimeout(80);
assert('keyboard.enterCommitsActive', await committedIri(page, 'property') === second);
await cancel();

// ---- 3. mouse: clicking an option commits it (typeof, in the disclosure) ---------
await annotate('official');
await page.evaluate(() => { document.getElementById('advanced-fields').open = true; });
await page.fill(`${tWrap} input.typeahead-input`, 'Person');
await page.waitForTimeout(120);
await page.locator(`${tWrap} .typeahead-option[data-uri="${FOAF}Person"]`).dispatchEvent('mousedown');
await page.waitForTimeout(80);
assert('mouse.selectCommits', await committedIri(page, 'typeof') === FOAF + 'Person');
await cancel();

// ---- 4. a full IRI typed directly is accepted as a free entry -------------------
await annotate('company');
await typeIri(page, 'property', 'https://schema.org/birthDate');
await page.click('#rdfa-editor-overlay button.spo-action');
await page.waitForTimeout(120);
assert('freeIri.written', await page.evaluate(() =>
    !!document.querySelector('#content span[property="https://schema.org/birthDate"]')));

// ---- 5. non-IRI free text yields no value (nothing committed, no @property) ------
await annotate('graduated');
await page.fill(pIn, 'notaterm');
await page.waitForTimeout(80);
assert('nonIri.notCommitted', await committedIri(page, 'property') === '');
await page.click('#rdfa-editor-overlay button.spo-action');
await page.waitForTimeout(120);
assert('nonIri.noProperty', await page.evaluate(() =>
    !document.querySelector('#content [property="notaterm"]')));

// ---- 6. editing an existing annotation shows the committed button + label -------
await openTitleEdit();
assert('editPrefill.button', await page.locator(`${pWrap} .typeahead-value`).count() === 1);
assert('editPrefill.iri', await committedIri(page, 'property') === TITLE);
assert('editPrefill.label', await page.evaluate(w =>
    (document.querySelector(w + ' .typeahead-label')?.textContent ?? '').length > 0, pWrap));
await cancel();

// ---- 7a. clicking the committed button re-opens it for editing ------------------
await openTitleEdit();
await page.click(`${pWrap} .typeahead-value`);
await page.waitForTimeout(80);
assert('stale.reopened', await page.locator(pIn).count() === 1);
assert('stale.inputFocused', await page.evaluate(w =>
    document.activeElement === document.querySelector(w + ' input.typeahead-input'), pWrap));
assert('stale.editingIriParked', await page.evaluate(([w, t]) =>
    document.querySelector(w)?.getAttribute('data-editing-iri') === t, [pWrap, TITLE]));
await cancel();

// ---- 7b. an untouched button->edit preserves the IRI on save --------------------
await openTitleEdit();
await page.click(`${pWrap} .typeahead-value`);
await page.waitForTimeout(80);
await page.click('#rdfa-editor-overlay button.spo-action');
await page.waitForTimeout(120);
assert('stale.untouchedPreserves', await page.evaluate(t =>
    document.querySelector('#content > h1')?.getAttribute('property') === t, TITLE));

// ---- 7c. the first keystroke invalidates the stale selection --------------------
await openTitleEdit();
await page.click(`${pWrap} .typeahead-value`);
await page.waitForTimeout(80);
await page.type(pIn, 'x');
await page.waitForTimeout(80);
assert('stale.typingClearsEditingIri', await page.evaluate(w =>
    !document.querySelector(w)?.hasAttribute('data-editing-iri'), pWrap));
await cancel();

console.log(JSON.stringify({ results, errors: errors.slice(0, 8) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
