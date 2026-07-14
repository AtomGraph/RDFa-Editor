// Nested drag-and-drop: every %block carries its own handle wherever the content
// model places blocks, and drops resolve to the innermost legal level - lifting a
// nested block (incl. an RDFa object div) out of a list item, dropping a top-level
// block into a container, clamping over illegal spots, staying region-scoped.
// Real mouse gestures throughout (Playwright synthesizes HTML5 drag events from
// mouse.down + moves). Runs against fixture-dragnest.html.
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';

const errors = [];
const results = {};
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', err => errors.push(String(err)));
page.on('dialog', d => d.accept());

const undoKey = 'Control+z';
const load = async () => {
    await page.goto(BASE + '/tests/fixture-dragnest.html');
    // nested chrome proves the recursive init reached the quote inside the li
    await page.waitForSelector('#content li > blockquote > [data-role=chrome]',
        { state: 'attached', timeout: 15000 })
        .catch(() => errors.push('nested chrome never injected'));
};
const baselineOf = () => page.evaluate(() => document.getElementById('content').innerHTML);

// viewport center of a block's drag handle (hover the block first so the
// handle's visibility and geometry are settled)
const handleAt = async selector => {
    const block = await page.evaluate(sel => {
        const r = document.querySelector(sel).getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, selector);
    await page.mouse.move(block.x, block.y);
    return page.evaluate(sel => {
        const r = document.querySelector(sel + ' > [data-role=chrome]').getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, selector);
};

// viewport point within a block: fraction of its height picks before (< .5)
// or after (> .5) per the midpoint rule
const pointIn = (selector, fraction) => page.evaluate(([sel, f]) => {
    const r = document.querySelector(sel).getBoundingClientRect();
    return { x: r.x + Math.min(r.width / 2, 200), y: r.y + r.height * f };
}, [selector, fraction]);

const dragReal = async (from, to) => {
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    for (let i = 1; i <= 8; i++)
        await page.mouse.move(from.x + (to.x - from.x) * i / 8, from.y + (to.y - from.y) * i / 8);
    await page.mouse.up();
};

// the invariants net, with the nested-chrome contract: chrome only as a child
// of a draggable block (a real %block in a region / flow container / blockquote)
const invariants = () => page.evaluate(() => {
    const v = [];
    const region = document.getElementById('content');
    const BLOCK = new Set(['P', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'DIV', 'UL', 'OL', 'DL',
        'PRE', 'BLOCKQUOTE', 'ADDRESS', 'FIELDSET', 'TABLE', 'FIGURE']);
    const FLOW = new Set(['LI', 'DD', 'TD', 'TH', 'DIV', 'FIGURE', 'FIGCAPTION']);
    const walker = document.createTreeWalker(region, NodeFilter.SHOW_TEXT);
    for (let n; (n = walker.nextNode());) {
        if (!n.textContent.trim()) continue;
        if (n.parentElement.closest('[data-role]')) continue;
        if (!n.parentElement.closest('[contenteditable=true]'))
            v.push('orphan text: "' + n.textContent.trim().slice(0, 30) + '"');
    }
    for (const h of region.querySelectorAll('[contenteditable=true] [contenteditable=true]'))
        v.push('nested host: ' + h.tagName.toLowerCase());
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

// act, check invariants, undo once, compare against the pre-gesture baseline
const settle = async baseline => {
    const v = await invariants();
    await page.evaluate(() => document.querySelector('#content [contenteditable=true]')?.focus());
    await page.keyboard.press(undoKey);
    const restored = await baselineOf() === baseline;
    return { invariantsOk: v.length === 0, ...(v.length ? { violations: v } : {}), undoRestores: restored };
};

// ==== init: handles on nested blocks, none on non-blocks =========================
await load();
results.init = await page.evaluate(() => {
    const li = [...document.querySelectorAll('#content > ul > li')];
    const objectDiv = document.querySelector('#content li > div[about="#note"]');
    return {
        nestedPChrome: !!document.querySelector('#content li > p > [data-role=chrome]'),
        nestedQuoteChrome: !!document.querySelector('#content li > blockquote > [data-role=chrome]'),
        quoteInnerPChrome: !!document.querySelector('#content li > blockquote > p > [data-role=chrome]'),
        objectDivChrome: !!objectDiv?.querySelector(':scope > [data-role=chrome]'),
        objectDivEditable: objectDiv?.getAttribute('contenteditable') === 'true',
        noChromeOnLi: li.every(l => ![...l.children].some(c => c.getAttribute('data-role') === 'chrome')),
        noChromeOnRun: !document.querySelector('#content p.rdfa-editor-run > [data-role=chrome]'),
    };
});
{
    const v = await invariants();
    results.initInvariantsOk = v.length === 0;
    if (v.length) results.initViolations = v;
}

// ==== S1: lift the nested blockquote out of its list item ========================
await load();
{
    const baseline = await baselineOf();
    await dragReal(await handleAt('#content li > blockquote'), await pointIn('#content > p + ul + p', 0.8));
    results.liftOut = await page.evaluate(() => {
        const bq = [...document.querySelectorAll('#content > blockquote')]
            .find(b => b.textContent.includes('Quote in item'));
        const li = [...document.querySelectorAll('#content > ul > li')]
            .find(l => l.textContent.includes('Block item'));
        return {
            atTopLevel: !!bq && !!bq.previousElementSibling
                && bq.previousElementSibling.textContent.includes('Tail paragraph'),
            chromeKept: !!bq?.querySelector(':scope > [data-role=chrome]'),
            liKeepsBlock: !!li?.querySelector(':scope > p') && !li.querySelector(':scope > blockquote'),
        };
    });
    Object.assign(results.liftOut, await settle(baseline));
}

// ==== S2: the motivating case - the RDFa object div leaves its list item =========
await load();
{
    const baseline = await baselineOf();
    await dragReal(await handleAt('#content li > div[about="#note"]'), await pointIn('#content > p + ul + p', 0.8));
    results.objectOut = await page.evaluate(() => {
        const div = document.querySelector('#content > div[about="#note"]');
        const li = [...document.querySelectorAll('#content > ul > li')]
            .find(l => l.textContent.includes('Object holder'));
        return {
            atTopLevel: !!div,
            rdfaIntact: div?.querySelector(':scope > span[property]')?.textContent === 'Note body',
            liCollapsed: li?.getAttribute('contenteditable') === 'true'
                && !li.querySelector('.rdfa-editor-run'),
        };
    });
    Object.assign(results.objectOut, await settle(baseline));
}

// ==== S3: a top-level paragraph drops INTO the list item =========================
await load();
{
    const baseline = await baselineOf();
    await dragReal(await handleAt('#content > h1 + p'), await pointIn('#content li > p:not(.rdfa-editor-run)', 0.8));
    results.dropInto = await page.evaluate(() => {
        const li = [...document.querySelectorAll('#content > ul > li')]
            .find(l => l.textContent.includes('Block item'));
        const kids = li ? [...li.children].filter(c => !c.hasAttribute('data-role')) : [];
        return {
            nested: kids.length === 3 && kids[1].tagName === 'P'
                && kids[1].textContent.includes('Intro paragraph'),
            leftTopLevel: ![...document.querySelectorAll('#content > p')]
                .some(p => p.textContent.includes('Intro paragraph')),
        };
    });
    Object.assign(results.dropInto, await settle(baseline));
}

// ==== S4: over a plain item the legal level is the whole list ====================
// (li is not a drop target; the deepest draggable block there is the ul itself,
// so the paragraph lands before/after the list - never as an invalid ul child)
await load();
{
    const baseline = await baselineOf();
    await dragReal(await handleAt('#content > h1 + p'), await pointIn('#content > ul > li', 0.4));
    results.legalClamp = await page.evaluate(() => ({
        noPInUl: !document.querySelector('#content ul > p'),
        beforeList: !!document.querySelector('#content > p + ul')
            && document.querySelector('#content > ul').previousElementSibling
                .textContent.includes('Intro paragraph'),
    }));
    Object.assign(results.legalClamp, await settle(baseline));
}

// ==== S5: a drag never crosses regions ===========================================
await load();
{
    const baseline = await baselineOf();
    const embeddedBefore = await page.evaluate(() => document.getElementById('embedded').innerHTML);
    await dragReal(await handleAt('#content li > blockquote'), await pointIn('#embedded > p', 0.5));
    results.crossRegion = {
        contentIntact: await baselineOf() === baseline,
        embeddedIntact: await page.evaluate(() => document.getElementById('embedded').innerHTML) === embeddedBefore,
    };
}

// ==== S6: a nested handle press never arms a selection sweep =====================
await load();
{
    const from = await handleAt('#content li > blockquote > p');
    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    const to = await pointIn('#content > p + ul + p', 0.5);
    for (let i = 1; i <= 4; i++)
        await page.mouse.move(from.x + (to.x - from.x) * i / 4, from.y + (to.y - from.y) * i / 4);
    results.nestedHandleNotHijacked = {
        neverArmed: await page.evaluate(() => window.rdfaEditor.sweepAnchorNode == null),
    };
    await page.mouse.up();
}

// ==== S7: gesture-built nested blocks converge on a handle =======================
// (Enter splits the paragraph inside the quote; the new sibling paragraph gets
// its chrome from the after-mutation sweep, not from the split site)
await load();
{
    const baseline = await baselineOf();
    await page.evaluate(() => {
        const p = document.querySelector('#content li > blockquote > p');
        p.focus();
        const t = [...p.childNodes].find(n => n.nodeType === 3);
        window.getSelection().collapse(t, 5);
    });
    await page.keyboard.press('Enter');
    results.splitConverges = await page.evaluate(() => {
        const ps = document.querySelectorAll('#content li > blockquote > p');
        return {
            split: ps.length === 2,
            bothHaveChrome: [...ps].every(p => !!p.querySelector(':scope > [data-role=chrome]')),
        };
    });
    Object.assign(results.splitConverges, await settle(baseline));
}

// ==== S8: canonical serialization stays clean of nested chrome ===================
await load();
{
    await page.click('#view-source');
    results.canonicalClean = await page.evaluate(() => {
        const src = document.getElementById('output-content').textContent;
        return {
            noChrome: !src.includes('data-role') && !src.includes('⠿'),
            objectDivKept: src.includes('about="#note"'),
        };
    });
}

console.log(JSON.stringify({ results, errors: errors.slice(0, 5) }, null, 2));
await browser.close();
const flat = JSON.stringify(results);
process.exit(errors.length || flat.includes('false') ? 1 : 0);
