import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
const assert = (name, cond) => { results[name] = cond; if (!cond) errors.push('ASSERT FAILED: ' + name); };

await page.goto(BASE + '/tests/fixture.html');
await page.waitForSelector('#content > * > [data-role=chrome]', { state: 'attached', timeout: 15000 });

// 1. gutter hover: hovering to the LEFT of a block (over the handle position) keeps it revealed
results.gutter = await page.evaluate(() => {
    const p = document.querySelector('#content > p');
    const rect = p.getBoundingClientRect();
    // a point 20px left of the block box - inside the ::before gutter strip
    const el = document.elementFromPoint(rect.left - 20, rect.top + 8);
    return { gutterHitsBlock: el === p || p.contains(el) };
});
// visibility via real hover over the handle coordinates
const pBox = await page.locator('#content > p').first().boundingBox();
await page.mouse.move(pBox.x - 18, pBox.y + 8);
await page.waitForTimeout(100);
results.gutter.handleVisibleFromGutter = await page.evaluate(() => {
    const handle = document.querySelector('#content > p [data-role=chrome]');
    return getComputedStyle(handle).visibility === 'visible';
});

// 2. arrow navigation across blocks
await page.evaluate(() => {
    const h1 = document.querySelector('#content > h1');
    h1.focus();
    const t = [...h1.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, t.textContent.length); // end of h1
});
await page.keyboard.press('ArrowDown');
results.arrows = {
    downIntoNext: await page.evaluate(() =>
        document.querySelector('#content > h2').contains(window.getSelection().anchorNode)
        || window.getSelection().anchorNode === document.querySelector('#content > h2')),
};
await page.keyboard.press('ArrowUp'); // at start of h2 -> back into h1
results.arrows.upIntoPrevious = await page.evaluate(() => {
    const h1 = document.querySelector('#content > h1');
    const a = window.getSelection().anchorNode;
    return h1 === a || h1.contains(a);
});
// ArrowRight at end crosses too
await page.evaluate(() => {
    const h1 = document.querySelector('#content > h1');
    h1.focus();
    const t = [...h1.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, t.textContent.length);
});
await page.keyboard.press('ArrowRight');
results.arrows.rightCrosses = await page.evaluate(() => {
    const h2 = document.querySelector('#content > h2');
    const a = window.getSelection().anchorNode;
    return h2 === a || h2.contains(a);
});
// shift+Arrow stays native (selection extends within host) - test mid-text
await page.evaluate(() => {
    const h1 = document.querySelector('#content > h1');
    h1.focus();
    const t = [...h1.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, 4);
});
await page.keyboard.press('Shift+ArrowLeft');
results.arrows.shiftStaysNative = await page.evaluate(() =>
    !window.getSelection().isCollapsed);

// 2b. block images are navigation stops (not skipped): arrow keys select the
// non-editable image by focusing it, then step past it into the caption
assert('imageNav.focusable', await page.evaluate(() =>
    document.querySelector('#content figure img')?.getAttribute('tabindex') === '-1'));
// caret at the end of the <pre> that precedes the figure, then ArrowDown selects the image
await page.evaluate(() => {
    const pre = document.querySelector('#content > pre');
    pre.focus();
    const t = [...pre.childNodes].reverse().find(n => n.nodeType === 3);
    window.getSelection().collapse(t, t.textContent.length);
});
await page.keyboard.press('ArrowDown');
assert('imageNav.downSelectsImage', await page.evaluate(() =>
    document.activeElement === document.querySelector('#content figure img')));
// ArrowDown again steps past the image into the caption
await page.keyboard.press('ArrowDown');
assert('imageNav.downLeavesToCaption', await page.evaluate(() =>
    document.querySelector('#content figcaption').contains(window.getSelection().anchorNode)
    || window.getSelection().anchorNode === document.querySelector('#content figcaption')));
// ArrowUp from the caption start re-selects the image
await page.evaluate(() => {
    const cap = document.querySelector('#content figcaption');
    cap.focus();
    const t = [...cap.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, 0);
});
await page.keyboard.press('ArrowUp');
assert('imageNav.upSelectsImage', await page.evaluate(() =>
    document.activeElement === document.querySelector('#content figure img')));
// ArrowUp from the image lands the caret back in the previous block
await page.keyboard.press('ArrowUp');
assert('imageNav.upLeavesToPrev', await page.evaluate(() =>
    document.querySelector('#content > pre').contains(window.getSelection().anchorNode)
    || document.activeElement === document.querySelector('#content > pre')));

// 2c. Backspace on a selected image deletes its figure; undo restores it (with tabindex)
await page.evaluate(() => {
    const pre = document.querySelector('#content > pre');
    pre.focus();
    const t = [...pre.childNodes].reverse().find(n => n.nodeType === 3);
    window.getSelection().collapse(t, t.textContent.length);
});
await page.keyboard.press('ArrowDown'); // select the image
await page.keyboard.press('Backspace'); // delete the whole figure
assert('imageNav.backspaceDeletesFigure', await page.evaluate(() =>
    !document.querySelector('#content figure')));
assert('imageNav.deleteLandsCaret', await page.evaluate(() =>
    document.querySelector('#content > pre').contains(window.getSelection().anchorNode)
    || document.activeElement === document.querySelector('#content > pre')));
await page.keyboard.press('Control+z'); // undo restores the figure and its focusable image
assert('imageNav.undoRestoresFigure', await page.evaluate(() =>
    !!document.querySelector('#content figure img[tabindex="-1"]')));

// 3. Enter at end -> empty block accepts mouse click + typing
await page.evaluate(() => {
    const p = document.querySelector('#content > p');
    p.focus();
    window.getSelection().collapse(p, p.childNodes.length); // very end
});
await page.keyboard.press('Enter');
results.emptyBlock = await page.evaluate(() => {
    const p2 = document.querySelector('#content > p + p');
    return {
        created: !!p2,
        hasPlaceholder: !!p2?.querySelector(':scope > br'),
        hasHeight: p2?.getBoundingClientRect().height > 5,
    };
});
// click INTO the empty block with the mouse, then type
const emptyBox = await page.locator('#content > p + p').first().boundingBox();
await page.mouse.click(emptyBox.x + emptyBox.width / 2, emptyBox.y + emptyBox.height / 2);
await page.keyboard.type('typed after click');
results.emptyBlock.typingAppears = await page.evaluate(() =>
    document.querySelector('#content > p + p').textContent.includes('typed after click'));
// split at START leaves the (now empty) first half usable too
await page.evaluate(() => {
    const p = document.querySelector('#content > p + p');
    p.focus();
    const t = [...p.childNodes].find(n => n.nodeType === 3);
    window.getSelection().collapse(t, 0);
});
await page.keyboard.press('Enter');
results.emptyBlock.emptyFirstHalfHasPlaceholder = await page.evaluate(() => {
    const ps = [...document.querySelectorAll('#content > p')];
    const emptyOne = ps.find(p => p.textContent.replace('⠿', '').trim() === '');
    return !!emptyOne?.querySelector(':scope > br');
});
// cleanup via undo (3 ops)
await page.keyboard.press('Control+z');
await page.keyboard.press('Control+z');
await page.keyboard.press('Control+z');
results.cleanup = await page.evaluate(() =>
    !document.querySelector('#content > p + p') ||
    ![...document.querySelectorAll('#content > p')].some(p => p.textContent.includes('typed after click')));

console.log(JSON.stringify({ results, errors: errors.slice(0, 4) }, null, 2));
await browser.close();
process.exit(errors.length ? 1 : 0);
