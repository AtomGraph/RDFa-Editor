import { chromium } from 'playwright';

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

// place the caret inside a block whose in-scope subject is the document (about="")
const caretIn = (substr) => page.evaluate(s => {
    const walker = document.createTreeWalker(document.getElementById('content'), NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
        const i = node.textContent.indexOf(s);
        if (i >= 0) {
            node.parentElement.closest('[contenteditable=true]')?.focus();
            const range = document.createRange();
            range.setStart(node, i + 1); range.collapse(true);
            const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
            document.querySelector('#content [contenteditable=true]')
                ?.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
            return true;
        }
    }
    return false;
}, substr);

const bodyText = () => page.evaluate(() => document.getElementById('inspector-body').textContent);
const subjectText = () => page.evaluate(() => document.getElementById('inspector-subject').textContent);
const drawerOpen = () => page.evaluate(() =>
    getComputedStyle(document.getElementById('inspector-drawer')).display !== 'none');

// ---- 1. drawer is hidden until toggled -----------------------------------------
assert('inspector.hiddenByDefault', !(await drawerOpen()));

await page.click('#inspector-toggle');
await page.waitForTimeout(150);
assert('inspector.opensOnToggle', await drawerOpen());

// ---- 2. document subject: dc:title + schema:name are both listed ---------------
await caretIn('Demo document');
await page.waitForTimeout(150);
const docBody = await bodyText();
const docSubject = await subjectText();
assert('inspector.docTitleRow', docBody.includes('Demo document'));           // dc:title literal
assert('inspector.docNameRow', docBody.includes('ACME Corporation'));         // schema:name literal (same subject)
assert('inspector.docTypeBadge', docSubject.includes('document-hierarchy#Container')
    || docSubject.toLowerCase().includes('container'));                       // rdf:type badge

// ---- 3. caret tracking: moving into #notes switches the subject ----------------
await page.evaluate(() => {
    const p = document.querySelector('#notes p');
    p.focus();
    const range = document.createRange(); range.selectNodeContents(p); range.collapse(true);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
    p.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
});
await page.waitForTimeout(150);
const notesSubject = await subjectText();
assert('inspector.tracksCaretToNotes', notesSubject.includes('#notes'));

// ---- 4. toggle closes it -------------------------------------------------------
await page.click('#inspector-toggle');
await page.waitForTimeout(100);
assert('inspector.closesOnToggle', !(await drawerOpen()));

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
