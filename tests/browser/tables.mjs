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

// assertions are recorded and, unlike the printed-only convention, also fail the
// suite via the errors channel so logic regressions surface in CI
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#edit-toolbar', { state: 'attached', timeout: 15000 })
    .catch(() => errors.push('toolbar never rendered'));
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 5000 })
    .catch(() => errors.push('chrome never injected'));

const caretInText = async (selector) => page.evaluate(sel => {
    const host = document.querySelector(sel);
    host.focus();
    const t = [...host.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    window.getSelection().collapse(t, 2);
}, selector);

// focus a cell (by 0-based row/col into the given section) and collapse the caret.
// blur first so focus() always re-fires focusin -> sync-table-toolbar, even when
// the target cell already held focus (a real user's caret move always re-syncs)
const focusCell = async (section, row, col) => {
    await page.evaluate(([sec, r, c]) => {
        document.activeElement?.blur();
        const table = document.querySelector('#content table');
        const rows = table.querySelectorAll(':scope > ' + sec + ' > tr');
        const cell = rows[r].querySelectorAll(':scope > td, :scope > th')[c];
        cell.focus();
        window.getSelection().collapse(cell, 0);
    }, [section, row, col]);
    await page.waitForTimeout(80); // let focusin -> sync-table-toolbar settle
};

const bodyRows = () => page.evaluate(() => document.querySelectorAll('#content table > tbody > tr').length);
const bodyCols = () => page.evaluate(() => document.querySelectorAll('#content table > tbody > tr:first-child > td').length);
const headCols = () => page.evaluate(() => document.querySelectorAll('#content table > thead > tr > th').length);
const opDisabled = op => page.evaluate(o =>
    document.querySelector(`#edit-toolbar button.table-op[data-op="${o}"]`).disabled, op);

// ---- 1. insert a 3x3 table with header row and caption -------------------------
await caretInText('#content > p:first-of-type');
await page.click('#edit-toolbar button.insert-table');
await page.waitForTimeout(150);
await page.fill('#table-dialog input[name=rows]', '3');
await page.fill('#table-dialog input[name=cols]', '3');
await page.fill('#table-dialog input[name=caption]', 'Sales');
await page.click('#table-dialog button.table-save');
await page.waitForTimeout(150);

results.insert = await page.evaluate(() => {
    const t = document.querySelector('#content table');
    return {
        exists: !!t,
        caption: t?.querySelector(':scope > caption')?.textContent === 'Sales',
        headerCells: t?.querySelectorAll(':scope > thead > tr > th').length,
        bodyRows: t?.querySelectorAll(':scope > tbody > tr').length,
        bodyCells: t?.querySelectorAll(':scope > tbody > tr > td').length,
        chromeOnTable: !!t?.querySelector(':scope > [data-role=chrome]'),
        noStrayChrome: !document.querySelector('#content > span[data-role=chrome]'),
        cellsEditable: [...t.querySelectorAll('th, td, caption')].every(c => c.getAttribute('contenteditable') === 'true'),
        tableNotEditable: !t.hasAttribute('contenteditable'),
        rowsNotEditable: ![...t.querySelectorAll('tr, thead, tbody')].some(e => e.hasAttribute('contenteditable')),
    };
});
assert('insert.exists', results.insert.exists);
assert('insert.caption', results.insert.caption);
assert('insert.headerCells', results.insert.headerCells === 3);
assert('insert.bodyRows', results.insert.bodyRows === 3);
assert('insert.bodyCells', results.insert.bodyCells === 9);
assert('insert.chromeOnTable', results.insert.chromeOnTable);
assert('insert.noStrayChrome', results.insert.noStrayChrome);
assert('insert.cellsEditable', results.insert.cellsEditable);
assert('insert.tableNotEditable', results.insert.tableNotEditable);
assert('insert.rowsNotEditable', results.insert.rowsNotEditable);

// ---- 2. typing in a cell -------------------------------------------------------
await focusCell('tbody', 0, 0);
await page.keyboard.type('Data');
assert('typing', await page.evaluate(() =>
    document.querySelector('#content table > tbody > tr:first-child > td:first-child').textContent.includes('Data')));

// ---- 3. Backspace at cell start is inert (never merges the cell away) -----------
await page.evaluate(() => {
    const cell = document.querySelector('#content table > tbody > tr:first-child > td:first-child');
    cell.focus();
    window.getSelection().collapse(cell.firstChild, 0);
});
await page.keyboard.press('Backspace');
assert('backspaceInert', await page.evaluate(() => {
    const t = document.querySelector('#content table');
    return t.querySelectorAll(':scope > tbody > tr').length === 3
        && t.querySelector(':scope > tbody > tr:first-child > td:first-child').textContent.includes('Data');
}));

// ---- 4. Tab walks cells; Tab in the last cell appends a body row ---------------
await page.evaluate(() => {
    // caption Tabs into the first header cell
    const cap = document.querySelector('#content table > caption');
    cap.focus();
    window.getSelection().collapse(cap.firstChild ?? cap, 0);
});
await page.keyboard.press('Tab');
assert('tabFromCaption', await page.evaluate(() => {
    const th = document.querySelector('#content table > thead > tr > th:first-child');
    return th.contains(window.getSelection().anchorNode) || window.getSelection().anchorNode === th;
}));

const rowsBeforeTab = await bodyRows();
await page.evaluate(() => {
    const cells = document.querySelectorAll('#content table > tbody > tr > td');
    const last = cells[cells.length - 1];
    last.focus();
    window.getSelection().collapse(last, 0);
});
await page.keyboard.press('Tab');
await page.waitForTimeout(80);
assert('tabAppendsRow', await bodyRows() === rowsBeforeTab + 1);
assert('tabAppendCaret', await page.evaluate(() => {
    const rows = document.querySelectorAll('#content table > tbody > tr');
    return rows[rows.length - 1].querySelector('td').contains(window.getSelection().anchorNode)
        || rows[rows.length - 1].querySelector('td') === window.getSelection().anchorNode;
}));

// ---- 5. Shift+Tab steps back; a no-op at the first cell -------------------------
await page.evaluate(() => {
    const cells = document.querySelectorAll('#content table > thead > tr > th');
    cells[1].focus();
    window.getSelection().collapse(cells[1], 0);
});
await page.keyboard.press('Shift+Tab');
assert('shiftTab', await page.evaluate(() => {
    const first = document.querySelector('#content table > thead > tr > th:first-child');
    return first.contains(window.getSelection().anchorNode) || window.getSelection().anchorNode === first;
}));

// ---- 6. Enter steps down the column; a last-row Enter appends a row -------------
await focusCell('tbody', 0, 1);
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
assert('enterDownColumn', await page.evaluate(() => {
    const cell = document.querySelector('#content table > tbody > tr:nth-child(2) > td:nth-child(2)');
    return cell.contains(window.getSelection().anchorNode) || window.getSelection().anchorNode === cell;
}));
const rowsBeforeEnter = await bodyRows();
await page.evaluate(() => {
    const rows = document.querySelectorAll('#content table > tbody > tr');
    const cell = rows[rows.length - 1].querySelector('td:nth-child(2)');
    cell.focus();
    window.getSelection().collapse(cell, 0);
});
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
assert('enterAppendsRow', await bodyRows() === rowsBeforeEnter + 1);

// ---- 7. toolbar gating: disabled outside a table, enabled inside ----------------
await caretInText('#content > p:first-of-type');
await page.waitForTimeout(80);
assert('gatingDisabledInP', await opDisabled('row-below'));
await focusCell('tbody', 0, 0);
assert('gatingEnabledInCell', !(await opDisabled('row-below')));

// ---- 8. insert row below / column right -----------------------------------------
let r0 = await bodyRows();
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="row-below"]');
await page.waitForTimeout(80);
assert('rowBelow', await bodyRows() === r0 + 1);

let c0 = await bodyCols(), h0 = await headCols();
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="col-right"]');
await page.waitForTimeout(80);
assert('colRightBody', await bodyCols() === c0 + 1);
assert('colRightHeader', await headCols() === h0 + 1); // columns span header rows too

// ---- 9. delete row / column, then D2 last-line no-ops ---------------------------
let r1 = await bodyRows();
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="del-row"]');
await page.waitForTimeout(80);
assert('delRow', await bodyRows() === r1 - 1);

let c1 = await bodyCols();
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="del-col"]');
await page.waitForTimeout(80);
assert('delCol', await bodyCols() === c1 - 1);

// shrink to a single body row, then confirm one more delete is a no-op (D2)
for (let guard = 0; guard < 10 && (await bodyRows()) > 1; guard++) {
    await focusCell('tbody', 0, 0);
    await page.click('#edit-toolbar button.table-op[data-op="del-row"]');
    await page.waitForTimeout(60);
}
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="del-row"]');
await page.waitForTimeout(80);
assert('delRowLastIsNoop', await bodyRows() === 1);

// shrink to a single column, then confirm one more delete is a no-op (D2)
for (let guard = 0; guard < 10 && (await bodyCols()) > 1; guard++) {
    await focusCell('tbody', 0, 0);
    await page.click('#edit-toolbar button.table-op[data-op="del-col"]');
    await page.waitForTimeout(60);
}
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="del-col"]');
await page.waitForTimeout(80);
assert('delColLastIsNoop', await bodyCols() === 1);

// ---- 10. spanned tables disable the structural ops ------------------------------
// blur first so the subsequent focus fires focusin -> sync-table-toolbar (in real
// use the caret always moves into the table, which re-syncs the toolbar)
await page.evaluate(() => {
    document.activeElement?.blur();
    document.querySelector('#content table > tbody > tr:first-child > td').setAttribute('colspan', '2');
});
await focusCell('tbody', 0, 0);
assert('spanGating', (await opDisabled('row-below')) && (await opDisabled('col-right')) && (await opDisabled('del-row')));
await page.evaluate(() => document.querySelector('#content table > tbody > tr:first-child > td').removeAttribute('colspan'));

// ---- 11. undo of a table op (foster-parenting regression) -----------------------
// grow so the op has room, then undo and check chrome integrity
await focusCell('tbody', 0, 0);
await page.click('#edit-toolbar button.table-op[data-op="row-below"]');
await page.waitForTimeout(80);
const grown = await bodyRows();
await page.keyboard.press('Control+z');
await page.waitForTimeout(120);
results.undo = await page.evaluate(() => ({
    rows: document.querySelectorAll('#content table > tbody > tr').length,
    chromeOnTable: !!document.querySelector('#content table > [data-role=chrome]'),
    noStrayChrome: !document.querySelector('#content > span[data-role=chrome]'),
    oneChrome: document.querySelectorAll('#content table > [data-role=chrome]').length === 1,
}));
assert('undoRowCount', results.undo.rows === grown - 1);
assert('undoChromeOnTable', results.undo.chromeOnTable);
assert('undoNoStrayChrome', results.undo.noStrayChrome);
assert('undoOneChrome', results.undo.oneChrome);
await page.keyboard.press('Control+y');
await page.waitForTimeout(120);
assert('redoRowCount', await bodyRows() === grown);

// ---- 12. Enter in the caption starts a paragraph after the table ----------------
await page.evaluate(() => {
    const cap = document.querySelector('#content table > caption');
    cap.focus();
    window.getSelection().collapse(cap.firstChild ?? cap, 0);
});
await page.keyboard.press('Enter');
await page.waitForTimeout(80);
assert('captionEnter', await page.evaluate(() => {
    const t = document.querySelector('#content table');
    return t.nextElementSibling?.tagName === 'P' && t.nextElementSibling.contains(window.getSelection().anchorNode);
}));
// tidy: remove the paragraph we just created
await page.evaluate(() => {
    const p = document.querySelector('#content table').nextElementSibling;
    if (p && p.tagName === 'P') p.remove();
});

// ---- 13. RDFa annotation on a cell text selection -------------------------------
await page.evaluate(() => {
    const cell = document.querySelector('#content table > tbody > tr:first-child > td');
    cell.focus();
    // ensure the cell holds selectable text
    if (!cell.textContent.trim()) cell.textContent = 'Region';
    const t = [...cell.childNodes].find(n => n.nodeType === 3 && n.textContent.trim().length > 2);
    const range = document.createRange();
    range.setStart(t, 0); range.setEnd(t, Math.min(6, t.textContent.length));
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
});
await page.locator('#content table > tbody > tr:first-child > td').first()
    .click({ button: 'right', position: { x: 8, y: 8 } });
await page.waitForTimeout(300);
await pickTerm(page, 'property', 'http://purl.org/dc/terms/description', 'description');
await page.click('#rdfa-editor-overlay button.spo-action');
await page.waitForTimeout(120);
assert('cellAnnotation', await page.evaluate(() =>
    !!document.querySelector('#content table td span[property="http://purl.org/dc/terms/description"]')));

// ---- 14. the table is a draggable block -----------------------------------------
results.drag = await page.evaluate(() => {
    const content = document.getElementById('content');
    const dragged = content.querySelector(':scope > table');
    const target = content.querySelector(':scope > blockquote');
    if (!dragged || !target) return { skipped: true };
    dragged.querySelector('.drag-handle').dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    const draggableSet = dragged.getAttribute('draggable') === 'true';
    const dt = new DataTransfer();
    dt.setData('application/x-rdfa-editor-block', '');
    dragged.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: dt }));
    const rect = target.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 2 }));
    target.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt, clientY: rect.bottom - 2 }));
    dragged.dispatchEvent(new DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
    return {
        draggableSet,
        moved: target.nextElementSibling === dragged,
        cleaned: !dragged.hasAttribute('draggable') && !dragged.classList.contains('dragging'),
    };
});
assert('dragDraggable', results.drag.draggableSet === true);
assert('dragMoved', results.drag.moved === true);
assert('dragCleaned', results.drag.cleaned === true);

// ---- 15. canonical source view is clean -----------------------------------------
await page.click('#view-source');
await page.waitForTimeout(120);
const src = await page.evaluate(() => document.getElementById('output-content').textContent);
assert('sourceHasTable', /<table\b/.test(src) && /<tbody\b/.test(src));
assert('sourceClean', !/data-role|contenteditable|draggable|⠿/.test(src));
await page.click('#output-modal .modal-close');

console.log(JSON.stringify({ results, errors: errors.slice(0, 8) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
