// Shared drivers for the property/type typeahead fields in the annotation overlay.
// A field is #rdfa-editor-overlay .typeahead-field[data-field=property|typeof]; it is either in
// the typing state (input.typeahead-input + ul.typeahead-menu) or committed
// (button.typeahead-value). These helpers normalise to the typing state first.

export async function openTypeahead(page, field) {
    const wrap = `#rdfa-editor-overlay .typeahead-field[data-field=${field}]`;
    if (await page.locator(`${wrap} .typeahead-value`).count())
        await page.click(`${wrap} .typeahead-value`);          // committed -> re-open for editing
    return wrap;
}

// type a query, then select the suggested option carrying the exact IRI. Selection
// fires on mousedown (before the input's focusout), and the option is removed on
// commit, so dispatch mousedown directly rather than click (whose mouseup would find
// the element detached).
export async function pickTerm(page, field, iri, query) {
    const wrap = await openTypeahead(page, field);
    await page.fill(`${wrap} input.typeahead-input`, query);
    await page.waitForTimeout(120);
    await page.locator(`${wrap} .typeahead-option[data-uri="${iri}"]`).dispatchEvent('mousedown');
    await page.waitForTimeout(50);
}

// type a full IRI and commit it as a free entry (no matching vocabulary term needed)
export async function typeIri(page, field, iri) {
    const wrap = await openTypeahead(page, field);
    await page.fill(`${wrap} input.typeahead-input`, iri);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(50);
}

// the committed IRI a field currently holds (hidden input inside the button), or ''
export async function committedIri(page, field) {
    return page.evaluate(f => document.querySelector(
        `#rdfa-editor-overlay .typeahead-field[data-field=${f}] input[type=hidden]`)?.value ?? '', field);
}
