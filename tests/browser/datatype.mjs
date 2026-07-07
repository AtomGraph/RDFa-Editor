import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

// enforcing convention (see tables.mjs): every assertion also fails the suite via
// the errors channel, so a datatype/language regression surfaces in CI
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#overlay', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('overlay never rendered'));
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 5000 })
    .catch(() => errors.push('chrome never injected'));

const XSD = 'http://www.w3.org/2001/XMLSchema#';

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

// right-click the exact centre of the current selection: a real contextmenu event
// whose target is the selected text, so create/edit mode resolves correctly
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
    await page.evaluate(() => { document.getElementById('advanced-fields').open = true; });
};

const spanAttrs = (property) => page.evaluate(p => {
    const s = document.querySelector(`#content span[property="${p}"]`);
    return s && { datatype: s.getAttribute('datatype'), content: s.getAttribute('content'),
        lang: s.getAttribute('lang'), text: s.textContent };
}, property);

// ---- 1. typed literal: xsd:date + machine-readable @content --------------------
await selectText('Q4 2024');
await rightClickSelection();
await page.selectOption('#overlay select[name=property]', 'urn:rdfa-editor:custom');
await page.fill('#overlay input[name=custom-property]', 'http://purl.org/dc/terms/date');
await page.selectOption('#overlay select[name=datatype]', XSD + 'date');
await page.fill('#overlay input[name=value]', '2024-10-01');
await page.click('#overlay button.spo-action');
await page.waitForTimeout(150);

const dateSpan = await spanAttrs('http://purl.org/dc/terms/date');
assert('date.created', !!dateSpan);
assert('date.datatypeAbsoluteIri', dateSpan?.datatype === XSD + 'date');
assert('date.contentEmitted', dateSpan?.content === '2024-10-01');
assert('date.noLang', dateSpan?.lang === null);

// extraction emits an rdf:datatype-typed literal
await page.click('#parse-rdf');
await page.waitForTimeout(200);
const dateRdf = await page.evaluate(() => document.getElementById('output-content').textContent);
assert('date.extractedTyped', dateRdf.includes(`rdf:datatype="${XSD}date"`) && dateRdf.includes('2024-10-01'));
await page.click('#output-modal .modal-close');

// ---- 2. language-tagged literal (no datatype) ----------------------------------
await selectText('information');
await rightClickSelection();
await page.selectOption('#overlay select[name=property]', 'http://purl.org/dc/terms/description');
await page.fill('#overlay input[name=lang]', 'fr');
await page.click('#overlay button.spo-action');
await page.waitForTimeout(150);

const langSpan = await spanAttrs('http://purl.org/dc/terms/description');
assert('lang.created', !!langSpan);
assert('lang.attrWritten', langSpan?.lang === 'fr');
assert('lang.noDatatype', langSpan?.datatype === null);

await page.click('#parse-rdf');
await page.waitForTimeout(200);
const langRdf = await page.evaluate(() => document.getElementById('output-content').textContent);
assert('lang.extractedTagged', langRdf.includes('xml:lang="fr"'));
await page.click('#output-modal .modal-close');

// ---- 3. mutual exclusion: a chosen datatype disables the language input --------
await selectText('graduated');
await rightClickSelection();
await page.selectOption('#overlay select[name=datatype]', XSD + 'integer');
assert('mutex.langDisabledWithDatatype',
    await page.evaluate(() => document.querySelector('#overlay input[name=lang]').disabled === true));
await page.selectOption('#overlay select[name=datatype]', '');
assert('mutex.langEnabledWithoutDatatype',
    await page.evaluate(() => document.querySelector('#overlay input[name=lang]').disabled === false));
await page.click('#overlay button.cancel-action');
await page.waitForTimeout(100);

// ---- 4. edit round-trip: prefill, then clear the datatype ----------------------
await page.evaluate(() => {
    const s = document.querySelector('#content span[property="http://purl.org/dc/terms/date"]');
    s.closest('[contenteditable=true]').focus();
    const range = document.createRange(); range.selectNodeContents(s);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await rightClickSelection();
assert('edit.detailsAutoOpened',
    await page.evaluate(() => document.getElementById('advanced-fields').open === true));
assert('edit.datatypePrefilled',
    await page.evaluate(dt => document.querySelector('#overlay select[name=datatype]').value === dt, XSD + 'date'));
// clear the datatype -> plain literal, keeping @content
await page.selectOption('#overlay select[name=datatype]', '');
await page.click('#overlay button.spo-action');
await page.waitForTimeout(150);
const cleared = await spanAttrs('http://purl.org/dc/terms/date');
assert('edit.datatypeClearedOnRemove', cleared !== null && cleared.datatype === null);
assert('edit.contentRetained', cleared?.content === '2024-10-01');

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
