import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import { pickTerm } from './typeahead-helper.mjs';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#edit-toolbar', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('toolbar never rendered'));
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 5000 })
    .catch(() => errors.push('chrome never injected'));

// 1. init state
results.init = await page.evaluate(() => {
    const content = document.getElementById('content');
    return {
        blocks: content.children.length,
        chromeCount: content.querySelectorAll(':scope > * > [data-role=chrome]').length,
        pEditable: !!content.querySelector('p[contenteditable=true]'),
        ulNotEditable: !content.querySelector('ul[contenteditable]'),
        liEditable: !!content.querySelector('li[contenteditable=true]'),
        figcaptionEditable: !!content.querySelector('figcaption[contenteditable=true]'),
        imgNotEditable: !content.querySelector('img[contenteditable]'),
        preEditable: !!content.querySelector('pre[contenteditable=true]'),
        toolbarInNav: !!document.querySelector('nav #edit-toolbar'),
        dialogs: !!document.getElementById('link-dialog') && !!document.getElementById('figure-dialog'),
    };
});

const caretIn = async (selector, childIdx, offset) => page.evaluate(([sel, ci, off]) => {
    const host = document.querySelector(sel);
    host.focus();
    const node = ci === null ? host : host.childNodes[ci];
    window.getSelection().collapse(node, off);
}, [selector, childIdx, offset]);

const caretInText = async (selector) => page.evaluate(sel => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, 2);
}, selector);

// 2. typing
await caretIn('#content > p:first-of-type', null, 2);
await page.keyboard.type('XYZ');
results.typing = await page.evaluate(() =>
    document.querySelector('#content > p').textContent.includes('XYZ'));

// 3. Enter split mid-paragraph (childNodes: [chrome, text...]; caret in text node 1, offset 10)
const blocksBefore = await page.evaluate(() => document.getElementById('content').children.length);
await caretIn('#content > p:first-of-type', 1, 10);
await page.keyboard.press('Enter');
results.split = await page.evaluate(bc => {
    const content = document.getElementById('content');
    const ps = content.querySelectorAll(':scope > p');
    const first = ps[0], second = ps[1];
    const sel = window.getSelection();
    return {
        blockAdded: content.children.length === bc + 1,
        secondIsP: second?.tagName === 'P',
        secondEditable: second?.getAttribute('contenteditable') === 'true',
        secondHasChrome: !!second?.querySelector(':scope > [data-role=chrome]'),
        textPartitioned: first.textContent.replace('⠿', '').length > 0 && second.textContent.replace('⠿', '').length > 0,
        caretInSecond: second?.contains(sel.anchorNode),
    };
}, blocksBefore);

// 5. Backspace at start of second p merges back
await page.evaluate(() => {
    const second = document.querySelectorAll('#content > p')[1];
    second.focus();
    window.getSelection().collapse(second.childNodes[1], 0); // after chrome, start of text
});
await page.keyboard.press('Backspace');
results.merge = await page.evaluate(bc => {
    const content = document.getElementById('content');
    return {
        blockCountRestored: content.children.length === bc,
        merged: content.querySelector(':scope > p').textContent.includes('XYZ'),
    };
}, blocksBefore);

// 4. Enter inside an annotated span splits AFTER the span
results.annotationSplit = await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.querySelector('span[property]'));
    const span = p.querySelector('span[property]');
    p.focus();
    window.getSelection().collapse(span.firstChild, 4); // caret inside the annotation
    return { spans: document.querySelectorAll('#content span[property]').length, text: span.textContent };
});
await page.keyboard.press('Enter');
results.annotationSplit = await page.evaluate(prev => {
    const spans = document.querySelectorAll('#content span[property]');
    const span = spans[0];
    return {
        spanCountUnchanged: spans.length === prev.spans,
        spanIntact: span.textContent === prev.text,
        spanInFirstOfPair: span.closest('p').nextElementSibling?.tagName === 'P',
    };
}, results.annotationSplit);
// merge the split back to keep the doc tidy
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.querySelector('span[property]'));
    const next = p.nextElementSibling;
    next.focus();
    window.getSelection().collapse(next, 1);
});
await page.keyboard.press('Backspace');

// 6. Backspace at start of first block is inert
await caretIn('#content > h1', 1, 0);
await page.keyboard.press('Backspace');
results.firstBlockInert = await page.evaluate(bc =>
    document.getElementById('content').children.length === bc, blocksBefore);

// 7. empty-li Enter at list end exits the list
await page.evaluate(() => {
    const ul = document.querySelector('#content > ul');
    const li = document.createElement('li');
    li.setAttribute('contenteditable', 'true');
    ul.appendChild(li);
    li.focus();
    window.getSelection().collapse(li, 0);
});
await page.keyboard.press('Enter');
results.listExit = await page.evaluate(() => {
    const ul = document.querySelector('#content > ul');
    return {
        emptyLiGone: ul.querySelectorAll('li').length === 2,
        pFollows: ul.nextElementSibling?.tagName === 'P',
        caretInNewP: ul.nextElementSibling?.contains(window.getSelection().anchorNode),
    };
});
// remove the new empty p again
await page.evaluate(() => document.querySelector('#content > ul').nextElementSibling.remove());

// li split + merge (E3/B4)
await page.evaluate(() => {
    const li = document.querySelector('#content li');
    li.focus();
    window.getSelection().collapse(li.firstChild, 5);
});
await page.keyboard.press('Enter');
results.liSplit = await page.evaluate(() =>
    document.querySelector('#content > ul').querySelectorAll('li').length === 3);
await page.keyboard.press('Backspace'); // caret sits at start of the new li
results.liMerge = await page.evaluate(() =>
    document.querySelector('#content > ul').querySelectorAll('li').length === 2);

// 8. block-type change preserves text and RDFa attributes
await caretIn('#content > h1', 1, 3);
await page.selectOption('#edit-toolbar select[name=block-type]', 'h2');
results.convert = await page.evaluate(() => {
    const h2 = document.querySelector('#content > h2');
    return {
        converted: !!h2,
        property: h2?.getAttribute('property'),
        text: h2?.textContent.includes('Demo document'),
        editable: h2?.getAttribute('contenteditable') === 'true',
    };
});
await caretIn('#content > h2', 1, 3);
await page.selectOption('#edit-toolbar select[name=block-type]', 'h1'); // convert back

// 9. bold toggle
await page.evaluate(() => {
    const p = document.querySelector('#content > p');
    const text = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(text, 1); range.setEnd(text, 6);
    const sel = window.getSelection();
    sel.removeAllRanges(); sel.addRange(range);
});
await page.click('#edit-toolbar button[data-element=strong]');
results.bold = await page.evaluate(() => {
    const strong = [...document.querySelectorAll('#content > p:first-of-type strong')];
    return { wrapped: strong.some(s => s.textContent.length === 5) };
});
await page.click('#edit-toolbar button[data-element=strong]'); // caret still inside -> unwrap
results.bold.unwrapped = await page.evaluate(w =>
    ![...document.querySelectorAll('#content > p:first-of-type strong')].some(s => s.textContent.length === 5), results.bold);

// 10. link dialog create / edit / remove
await page.evaluate(() => {
    const p = document.querySelector('#content > p');
    const text = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(text, 1); range.setEnd(text, 6);
    const sel = window.getSelection();
    sel.removeAllRanges(); sel.addRange(range);
});
await page.click('#edit-toolbar button.format-link');
await page.fill('#link-dialog input[name=href]', 'https://linked.example/');
await page.click('#link-dialog button.link-save');
results.link = await page.evaluate(() => ({
    created: !!document.querySelector('#content > p a[href="https://linked.example/"]'),
}));
await page.evaluate(() => {
    const a = document.querySelector('#content > p a[href="https://linked.example/"]');
    a.closest('[contenteditable=true]').focus();
    window.getSelection().collapse(a.firstChild, 2);
});
await page.click('#edit-toolbar button.format-link');
results.link.prefilled = await page.evaluate(() =>
    document.querySelector('#link-dialog input[name=href]').value === 'https://linked.example/');
await page.click('#link-dialog button.link-remove');
results.link.removed = await page.evaluate(() =>
    !document.querySelector('#content a[href="https://linked.example/"]'));

// 11. figure insert
await caretInText('#content > p:first-of-type');
await page.click('#edit-toolbar button.insert-figure');
const FIG_SRC = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
await page.fill('#figure-dialog input[name=src]', FIG_SRC);
await page.fill('#figure-dialog input[name=alt]', 'Inserted');
await page.fill('#figure-dialog input[name=caption]', 'New figure');
await page.click('#figure-dialog button.figure-save');
results.figure = await page.evaluate(src => {
    const fig = document.querySelector('#content > p + figure');
    return {
        inserted: !!fig,
        img: fig?.querySelector(`img[src="${src}"][alt="Inserted"]`) != null,
        caption: fig?.querySelector('figcaption[contenteditable=true]')?.textContent === 'New figure',
        chrome: !!fig?.querySelector('[data-role=chrome]'),
    };
}, FIG_SRC);

// 12. paste is plain-text only
await caretInText('#content > p:first-of-type');
await page.evaluate(() => {
    const dt = new DataTransfer();
    dt.setData('text/html', '<b>EVIL</b><script>x()</script>');
    dt.setData('text/plain', 'PASTED TEXT');
    document.querySelector('#content > p').dispatchEvent(
        new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
});
results.paste = await page.evaluate(() => {
    // HTML paste path: sanitized + canonicalized markup is inserted (b -> strong, script dropped)
    const p = document.querySelector('#content > p');
    return {
        htmlInserted: [...p.querySelectorAll('strong')].some(s => s.textContent === 'EVIL'),
        noElements: !p.querySelector('b, script'),
    };
});

// 13. delete block (the figure we just inserted; non-empty -> confirm auto-accepted)
await page.evaluate(() => {
    const cap = document.querySelector('#content > p + figure figcaption');
    cap.focus();
    window.getSelection().collapse(cap, 0);
});
await page.click('#edit-toolbar button.delete-block');
results.deleteBlock = await page.evaluate(() => !document.querySelector('#content > p + figure'));

// 14. drag-and-drop reorder: drag first p below the blockquote
results.dnd = await page.evaluate(async () => {
    const content = document.getElementById('content');
    const dragged = content.querySelector(':scope > p');
    const target = content.querySelector(':scope > blockquote');
    const handle = dragged.querySelector('.drag-handle');
    const firstTag = i => content.children[i].tagName;
    handle.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    const draggableSet = dragged.getAttribute('draggable') === 'true';
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-block', '');
    dragged.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt,
        clientY: rect.bottom - 2 })); // lower half -> after
    const marked = target.classList.contains('drop-after');
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt,
        clientY: rect.bottom - 2 }));
    dragged.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
    return {
        draggableSet,
        marked,
        moved: target.nextElementSibling === dragged,
        cleaned: !dragged.hasAttribute('draggable') && !dragged.classList.contains('dragging')
            && !content.querySelector('.drop-before, .drop-after'),
    };
});

// 15. canonical source
await page.click('#view-source');
const source = await page.evaluate(() => document.getElementById('output-content').textContent);
results.canonicalSource = {
    hasRdfa: source.includes('about=""') && source.includes('property='),
    clean: !/data-role|contenteditable|draggable|class=|aria-|⠿/.test(source.replace(/id="/g, '')),
    noId: !source.includes('id="'),
};
// the Download button saves the shown text as content.xhtml (client-side Blob)
const [xhtmlDl] = await Promise.all([page.waitForEvent('download'), page.click('#output-download')]);
results.canonicalSource.download = xhtmlDl.suggestedFilename() === 'content.xhtml'
    && readFileSync(await xhtmlDl.path(), 'utf8') === source;
await page.click('#output-modal .modal-close');

// 16. annotation + extraction regression
await page.evaluate(() => {
    const p = [...document.querySelectorAll('#content > p')].find(x => x.textContent.includes('official website'));
    const text = [...p.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 5);
    const range = document.createRange();
    range.setStart(text, 1); range.setEnd(text, 6);
    const sel = window.getSelection();
    sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content > p', { hasText: 'official website' }).click({ button: 'right', position: { x: 25, y: 8 } });
await page.waitForTimeout(300);
await pickTerm(page, 'property', 'http://purl.org/dc/terms/description', 'description');
await page.click('#overlay button.spo-action');
await page.click('#parse-rdf');
await page.waitForTimeout(300);
const rdf = await page.evaluate(() => document.getElementById('output-content').textContent);
results.annotation = {
    annotated: await page.evaluate(() => !!document.querySelector('#content span[property="http://purl.org/dc/terms/description"]')),
    extracted: rdf.includes('description'),
    noChromeLiterals: !rdf.includes('⠿'),
    titleTriple: rdf.includes('Demo document'),
};
const [rdfDl] = await Promise.all([page.waitForEvent('download'), page.click('#output-download')]);
results.annotation.download = rdfDl.suggestedFilename() === 'content.rdf'
    && readFileSync(await rdfDl.path(), 'utf8') === rdf;

// 17. block-level annotation: right-click an h1 that carries its own @property
await page.click('#output-modal .modal-close').catch(() => {});
await page.waitForTimeout(100);
await page.evaluate(() => window.getSelection().removeAllRanges());
await page.locator('#content > h1').click({ button: 'right', position: { x: 60, y: 10 } });
await page.waitForTimeout(300);
results.blockAnnotation = {
    editorOpened: await page.evaluate(() =>
        getComputedStyle(document.getElementById('overlay')).display !== 'none'),
    // edit pre-fill renders the committed typeahead button carrying the IRI
    propertyPrefilled: await page.evaluate(() =>
        document.querySelector('#overlay .typeahead-field[data-field=property] input[type=hidden]')?.value
            === 'http://purl.org/dc/terms/title'),
    // the value field must not leak the block's chrome (⠿) glyph
    valueClean: await page.evaluate(() =>
        document.querySelector('#overlay input[name=value]').value === 'Demo document'),
    removeShown: await page.evaluate(() =>
        getComputedStyle(document.querySelector('#overlay button.remove-action')).display !== 'none'),
};
// Remove strips the RDFa attributes but keeps the heading (does not unwrap it)
await page.click('#overlay button.remove-action');
await page.waitForTimeout(200);
results.blockAnnotation.headingKept = await page.evaluate(() =>
    !!document.querySelector('#content > h1') &&
    document.querySelector('#content > h1').textContent.includes('Demo document'));
results.blockAnnotation.propertyStripped = await page.evaluate(() =>
    !document.querySelector('#content > h1')?.hasAttribute('property'));
for (const [k, v] of Object.entries(results.blockAnnotation))
    if (!v) errors.push('ASSERT FAILED: blockAnnotation.' + k);

console.log(JSON.stringify({ results, errors }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
