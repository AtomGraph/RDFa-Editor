import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/tests-fixture.html');
await page.waitForSelector('#breadcrumb', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('breadcrumb never rendered'));
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 5000 })
    .catch(() => errors.push('chrome never injected'));

const undoKey = 'Control+z';
const redoKey = 'Control+Shift+z';
const caretInText = async (selector, offset = 2) => page.evaluate(([sel, off]) => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, off);
}, [selector, offset]);
const firstPText = () => page.evaluate(() => document.querySelector('#content > p').textContent);

// 17. undo typing coalescing: two bursts >1.1s apart undo separately
await caretInText('#content > p:first-of-type');
await page.keyboard.type('AAA');
await page.waitForTimeout(1200);
await page.keyboard.type('BBB');
const withBoth = await firstPText();
await page.keyboard.press(undoKey);
const afterUndo1 = await firstPText();
await page.keyboard.press(undoKey);
const afterUndo2 = await firstPText();
results.undoTyping = {
    typed: withBoth.includes('AAA') && withBoth.includes('BBB'),
    firstUndoRemovesSecondBurst: afterUndo1.includes('AAA') && !afterUndo1.includes('BBB'),
    secondUndoRemovesFirstBurst: !afterUndo2.includes('AAA'),
};

// 19. redo semantics
await page.keyboard.press(redoKey);
const afterRedo = await firstPText();
await page.keyboard.press('Control+y');
const afterRedo2 = await firstPText();
results.redo = {
    shiftZRestores: afterRedo.includes('AAA') && !afterRedo.includes('BBB'),
    ctrlYRestores: afterRedo2.includes('BBB'),
};
// fresh edit clears redo
await page.keyboard.press(undoKey); // back to AAA-only
await page.keyboard.type('C');
await page.keyboard.press('Control+y');
results.redo.freshEditClearsRedo = !(await firstPText()).includes('BBB');
// clean up to the original text
await page.keyboard.press(undoKey);
await page.keyboard.press(undoKey);
results.redo.cleanedUp = !(await firstPText()).includes('AAA');

// 18. structural undo
const blockCount = () => page.evaluate(() => document.getElementById('content').children.length);
const before = await blockCount();
await caretInText('#content > p:first-of-type', 5);
await page.keyboard.press('Enter');
const afterSplit = await blockCount();
await page.keyboard.press(undoKey);
results.undoStructural = { splitUndone: afterSplit === before + 1 && (await blockCount()) === before };

// delete-block undo
await caretInText('#content > blockquote');
await page.click('#edit-toolbar button.delete-block');
const afterDelete = await blockCount();
await page.evaluate(() => document.body.focus());
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
results.undoStructural.deleteUndone = afterDelete === before - 1 && (await blockCount()) === before
    && await page.evaluate(() => !!document.querySelector('#content > blockquote'));

// block DnD move undo
const orderBefore = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(','));
await page.evaluate(() => {
    const content = document.getElementById('content');
    const dragged = content.querySelector(':scope > p');
    const target = content.querySelector(':scope > blockquote');
    dragged.querySelector('.drag-handle').dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-block', '');
    dragged.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 2 }));
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 2 }));
    dragged.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
});
const orderMoved = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(','));
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
const orderRestored = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName).join(','));
results.undoStructural.dndUndone = orderMoved !== orderBefore && orderRestored === orderBefore
    && await page.evaluate(() => !document.querySelector('#content > [draggable], #content > .dragging'));

// annotation apply undo
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('official website'));
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(t, 1); range.setEnd(t, 6);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content > p', { hasText: 'official website' }).click({ button: 'right', position: { x: 25, y: 8 } });
await page.waitForTimeout(300);
await page.selectOption('#overlay select[name=property]', 'http://purl.org/dc/terms/description');
await page.click('#overlay button.spo-action');
const spanCount = await page.evaluate(() => document.querySelectorAll('#content span[property="http://purl.org/dc/terms/description"]').length);
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
results.undoStructural.annotationUndone = spanCount === 1 && await page.evaluate(() =>
    !document.querySelector('#content span[property="http://purl.org/dc/terms/description"]'));

// 20. ToC render
await page.click('#toc-toggle');
results.toc = await page.evaluate(() => {
    const drawer = document.getElementById('toc-drawer');
    const items = [...drawer.querySelectorAll('li.toc-item')];
    const labels = items.map(li => li.querySelector(':scope > .toc-label').textContent);
    const queries = items.find(li => li.querySelector(':scope > .toc-label').textContent === 'Queries');
    const publications = items.find(li => li.querySelector(':scope > .toc-label').textContent === 'Publications');
    return {
        visible: getComputedStyle(drawer).display !== 'none',
        itemCount: items.length,
        labels,
        queriesNestedInPublications: publications?.contains(queries) === true,
        chromeFree: labels.every(l => !l.includes('⠿')),
    };
});

// 21. ToC navigation
await page.evaluate(() => window.scrollTo(0, 0));
await page.click('#toc-drawer li.toc-item .toc-label >> text="Queries"');
await page.waitForTimeout(200);
results.tocNav = await page.evaluate(() => ({
    caretInH3: document.querySelector('#content > h3').contains(window.getSelection().anchorNode),
}));

// 22. ToC liveness on heading edit + undo re-render
await caretInText('#content > h2:first-of-type');
await page.keyboard.type('XX');
await page.waitForTimeout(150);
const labelAfterType = await page.evaluate(() =>
    [...document.querySelectorAll('#toc-drawer .toc-label')].some(l => l.textContent.includes('XX')));
await page.keyboard.press(undoKey);
const labelAfterUndo = await page.evaluate(() =>
    [...document.querySelectorAll('#toc-drawer .toc-label')].some(l => l.textContent.includes('XX')));
results.tocLive = { updatesOnTyping: labelAfterType, revertsOnUndo: !labelAfterUndo };

// 23. section drag: move "Company" section below "Publications" section (which runs to the end)
const tagsBefore = await page.evaluate(() => [...document.getElementById('content').children].map(e => e.tagName + ':' + e.textContent.slice(1, 12)).join('|'));
await page.evaluate(() => {
    const items = [...document.querySelectorAll('#toc-drawer li.toc-item')];
    const byLabel = t => items.find(li => li.querySelector(':scope > .toc-label').textContent === t);
    const source = byLabel('Company'), target = byLabel('Publications');
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-section', '');
    source.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 1 }));
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 1 }));
    source.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
});
await page.waitForTimeout(200);
results.sectionDrag = await page.evaluate(() => {
    const children = [...document.getElementById('content').children];
    const tags = children.map(e => e.tagName);
    const h2s = children.filter(e => e.tagName === 'H2');
    // Company section (h2 + its p) should now be the LAST two blocks, in order
    const last2 = children.slice(-2);
    return {
        movedToEnd: last2[0].textContent.includes('Company') && last2[1].textContent.includes('founded by'),
        contiguous: tags.filter(t => t === 'H2').length === 2,
        publicationsFirst: h2s[0].textContent.includes('Publications'),
    };
});
// undo restores
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
results.sectionDrag.undone = tagsBefore === await page.evaluate(() =>
    [...document.getElementById('content').children].map(e => e.tagName + ':' + e.textContent.slice(1, 12)).join('|'));
// self/containment no-op: drag the h1 section onto "Queries" (inside h1's own section)
await page.evaluate(() => {
    const items = [...document.querySelectorAll('#toc-drawer li.toc-item')];
    const byLabel = t => items.find(li => li.querySelector(':scope > .toc-label').textContent === t);
    const source = byLabel('Demo document'), target = byLabel('Queries');
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-section', '');
    source.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 1 }));
    source.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
});
results.sectionDrag.selfDropNoop = tagsBefore === await page.evaluate(() =>
    [...document.getElementById('content').children].map(e => e.tagName + ':' + e.textContent.slice(1, 12)).join('|'));
await page.click('#toc-toggle'); // close drawer

// 24. breadcrumb
await page.evaluate(() => {
    const strong = document.querySelector('#content > p strong');
    strong.closest('[contenteditable=true]').focus();
    window.getSelection().collapse(strong.firstChild, 1);
    document.dispatchEvent(new Event('x'));
});
await page.keyboard.press('ArrowRight'); // trigger keyup -> breadcrumb refresh
await page.waitForTimeout(150);
results.breadcrumb = await page.evaluate(() => ({
    path: document.getElementById('breadcrumb-path').textContent,
    subject: document.getElementById('breadcrumb-subject').textContent,
}));
results.breadcrumb.pathOk = /content›p›strong/.test(results.breadcrumb.path.replace(/\s/g, ''));
results.breadcrumb.subjectOk = results.breadcrumb.subject === BASE + '/index.html';
// annotated span label
await page.evaluate(() => {
    const span = document.querySelector('#content span[property="https://schema.org/name"]');
    span.closest('[contenteditable=true]').focus();
    window.getSelection().collapse(span.firstChild, 1);
});
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(150);
results.breadcrumb.annotatedLabel = await page.evaluate(() =>
    document.getElementById('breadcrumb-path').textContent.includes('span[name]'));
// crumb click selects the element
await page.evaluate(() => {
    const crumbs = [...document.querySelectorAll('#breadcrumb-path .crumb')];
    crumbs[crumbs.length - 1].dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
results.breadcrumb.clickSelects = await page.evaluate(() =>
    window.getSelection().toString().includes('ACME'));

// 25. lint
results.lint = { initiallyHidden: await page.evaluate(() => getComputedStyle(document.getElementById('lint-badge')).display === 'none') };
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('official website'));
    const t = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(t, 1); range.setEnd(t, 6);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content > p', { hasText: 'official website' }).click({ button: 'right', position: { x: 25, y: 8 } });
await page.waitForTimeout(300);
await page.selectOption('#overlay select[name=property]', 'urn:rdfa-editor:custom');
await page.fill('#overlay input[name=custom-property]', 'nmae');
await page.click('#overlay button.spo-action');
await page.waitForTimeout(200);
results.lint.badgeShown = await page.evaluate(() =>
    getComputedStyle(document.getElementById('lint-badge')).display !== 'none'
    && document.getElementById('lint-badge').textContent === '1 RDFa issue');
results.lint.squiggle = await page.evaluate(() =>
    document.querySelector('#content span[property="nmae"]')?.classList.contains('rdfa-invalid') === true);
await page.click('#lint-badge');
results.lint.modalLists = await page.evaluate(() =>
    document.getElementById('output-content').textContent.includes('term-unresolvable'));
await page.click('#output-modal .modal-close');
// canonical purity with lint marker present
await page.click('#view-source');
const src = await page.evaluate(() => document.getElementById('output-content').textContent);
results.lint.canonicalPure = !/rdfa-invalid|class=|contenteditable|data-role/.test(src);
await page.click('#output-modal .modal-close');
// undo clears the annotation and the badge
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
await page.waitForTimeout(150);
results.lint.clearsOnUndo = await page.evaluate(() =>
    getComputedStyle(document.getElementById('lint-badge')).display === 'none'
    && !document.querySelector('#content .rdfa-invalid'));

// 26. find & replace
await page.click('#find-open');
await page.fill('#find-dialog input[name=find]', 'company');
await page.click('#find-dialog button.find-next');
results.find = { ciMatch: await page.evaluate(() => window.getSelection().toString().toLowerCase() === 'company') };
const firstMatchText = await page.evaluate(() => window.getSelection().anchorNode.textContent);
await page.click('#find-dialog button.find-next');
results.find.advances = await page.evaluate(t =>
    window.getSelection().toString().toLowerCase() === 'company', firstMatchText);
// match case
await page.check('#find-dialog input[name=match-case]');
await page.fill('#find-dialog input[name=find]', 'ACME');
await page.click('#find-dialog button.find-next');
results.find.caseSensitive = await page.evaluate(() => window.getSelection().toString() === 'ACME');
await page.uncheck('#find-dialog input[name=match-case]');
// replace-current
await page.fill('#find-dialog input[name=find]', 'founded');
await page.fill('#find-dialog input[name=replace]', 'established');
await page.click('#find-dialog button.find-next');
await page.click('#find-dialog button.replace-current');
results.find.replaced = await page.evaluate(() =>
    [...document.querySelectorAll('#content > p')].some(p => p.textContent.includes('established')));
// replace-all inside an annotation span stays annotation-safe
await page.fill('#find-dialog input[name=find]', 'ACME');
await page.fill('#find-dialog input[name=replace]', 'Acme Corp');
await page.click('#find-dialog button.replace-all');
await page.waitForTimeout(150);
results.find.replaceAllStatus = await page.evaluate(() => document.getElementById('find-status').textContent);
results.find.spanIntact = await page.evaluate(() => {
    const span = document.querySelector('#content span[property="https://schema.org/name"]');
    return span?.textContent === 'Acme Corp Corporation' && span.getAttribute('property') === 'https://schema.org/name';
});
// one undo reverts the whole replace-all
await caretInText('#content > p:first-of-type');
await page.keyboard.press(undoKey);
results.find.undoRevertsReplaceAll = await page.evaluate(() =>
    document.querySelector('#content span[property="https://schema.org/name"]')?.textContent === 'ACME Corporation');
// undo tears dialogs down by design (restore-snapshot -> hide-dialogs)
results.find.undoClosedDialog = await page.evaluate(() =>
    getComputedStyle(document.getElementById('find-dialog')).display === 'none');

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
