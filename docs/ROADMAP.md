# Roadmap: production-ready XHTML+RDFa editor, embeddable in LinkedDataHub (WYMEditor replacement)

## Context

The prototype (through commit `b8466cf`) is functionally rich: structured-block XHTML editing, strict RDFa 1.1 annotation + extraction, canonical serialization, unified undo/redo, ToC/breadcrumb/lint/find, DnD — all XSLT 3.0 + SaxonJS with 31 headless tests and ~115 Playwright assertions. The user asks: what is missing for (a) production readiness and (b) embedding into LinkedDataHub as the WYMEditor replacement (the jQuery/iframe WYSIWYG editing `ldh:XHTML` blocks stored as `rdf:XMLLiteral`).

## A. Production-readiness gaps (our side)

### A1. Security / sanitization (must-fix)
- `canonical-xhtml.xsl` does NOT strip `on*` event-handler attributes (`onclick`, `onerror`, …) nor `javascript:`/`data:` values in `@href`/`@src` — the canonical transform is the sanitization boundary for stored content; XSS surface once content is multi-user. Add strip rules + lint checks + fixtures.
- Element allowlist question: canonicalization currently passes unknown elements through (shallow-copy) — decide pass-through vs allowlist for embedded content (iframe/object/embed/form should not survive).

### A2. Editing completeness
- **HTML paste** with sanitization: currently plain-text only. We already own the cleanup machinery — parse `clipboardData` `text/html` via `parse-xml`/fragment parsing and run it through `mode="cm:canonical"` + the new sanitization rules; insert clean fragment. (Word/Google-Docs paste is the single biggest prod-usability item.)
- Nested lists (indent/outdent via Tab/Shift+Tab in `li`), `ul`↔`ol` conversion of an existing list.
- h4–h6 in the block-type select (cheap); `code`/`sub`/`sup` inline toggles (cheap — the `format-inline` machinery is generic).
- Image upload (LDH has upload flows) — URL-only first; wire LDH upload later.
- Caret restoration after undo (currently approximate: first host) — snapshot the caret as (block index, text offset) alongside innerHTML.
- Cross-text-node find matches (currently single-text-node only).

### A3. Robustness / quality
- **Multiple editable regions per page**: everything assumes a single `id('content')` (`rdfae:content()`, block-of, undo snapshots, lint, ToC). LDH pages have MANY XHTML blocks. Refactor to instance-scoped editing: editable roots resolved by class/typeof convention or param; undo stack per root (or keyed snapshots); ToC/breadcrumb scoped to the active root.
- Keyboard/a11y: Escape closes dialogs/overlay; focus trap in dialogs; ARIA roles/labels on toolbar, drawer, dialogs, breadcrumb; keyboard block move (Alt+Arrow) as DnD alternative; `prefers-reduced-motion`.
- i18n: UI strings hardcoded English — externalize following LDH's translations.rdf pattern.
- Browser matrix: only Chromium is CI-verified; Firefox + Safari manual/automated passes (Playwright Firefox/WebKit installable).
- IME: composition guard exists for Enter/Backspace; audit beforeinput coalescer under composition.
- Touch: drag handles unusable on touch; fallback (long-press or keyboard move).

### A4. RDFa completeness (extractor)
- `@rel`/`@rev`, `@inlist`, safe CURIEs, `@datetime`/`<time>`, `xml:base` (documented out of scope; @rel/@rev first — real-world pages hit it).
- Vocabulary breadth: schema.org vocab file ships nowhere; 118-option selects won't scale — **typeahead** (LDH has the pattern) over vocab terms replaces the selects; domain/range-aware ranking as follow-up.

### A5. Engineering hygiene
- CI: GitHub Actions running `tests/run-tests.sh` + the Playwright suites (currently scratchpad-only — move smoke scripts into `tests/browser/` in-repo).
- Packaging: CSS lives in the demo `index.html` — extract `rdfa-editor.css`; demo page vs library separation; README/integration docs; versioning.
- Namespace: done — `rdfae:` = `https://w3id.org/atomgraph/rdfa-editor#` (with `content-model#` and `lint#` sub-namespaces); register the `rdfa-editor` redirect at perma-id/w3id.org.

## B. LinkedDataHub embedding contract (WYMEditor replacement) — ships as `docs/ldh/MIGRATION.md` in this repo

Mapped integration surface (all in `LinkedDataHub/src/main/webapp/static/com/atomgraph/linkeddatahub/xsl/bootstrap/2.3.2/`):

1. **Form control swap** — `imports/default.xsl:1236-1258` renders `<textarea name="ol" class="wymeditor">` with `serialize()`d XMLLiteral children + hidden `lt`=rdf:XMLLiteral input. Replacement: render an editable container holding the `xhtml:div` content (our structured-block root) + a hidden `ol` input + the same `lt` input.
2. **Instantiation** — `client/form.xsl:144-160` (`ldh:RenderRowForm` on `textarea.wymeditor`, jQuery plugin + iframe). Replacement: a RenderRowForm template on our container class running per-instance init (editability + chrome). **No JS assets at all** (SEF-compiled) — only `rdfa-editor.css`.
3. **Submit sync** — LDH reads `textarea.value` at submit with no update() hook; `client/functions.xsl:221-226` wraps the `ol` value in `<div xmlns=…>` for the XMLLiteral. Replacement hook: **`ldh:FormPreSubmit`** (form.xsl:178-198) template serializing the container's canonicalized CHILDREN (no wrapper div) into the hidden `ol` input.
4. **Assets gate** — `layout.xsl:335/342-344/355/384-386` (`$load-wymeditor`): swap for a CSS-only include; jQuery+WYMEditor JS/skins removable after cutover.
5. **Multiple blocks** — one inline edit form per block (`client/block.xsl:314-354`), re-rendered after save; requires the **multi-instance refactor** (no `id('content')` singletons; per-instance undo).
6. **Vocabularies** — `/ns?uri=<vocab>&accept=application/rdf+xml` endpoint (constructor.xsl:203-209 pattern) via `ixsl:promise`; typeahead control (LDH typeahead.xsl precedent) replaces the selects.
7. **i18n** — strings into `translations.rdf` (`key('resources', id, document(...))` + `ac:label`).
8. **Feature flag** — decision DEFERRED (user); document options: `lapp:Application` property / XSL param via web.xml / hard cutover.
9. **Build** — modules pulled into the LDH webapp tree at build time and `xsl:import`ed from `client.xsl`; existing pom `xslt3-he … -relocate:on` step compiles everything (pom.xml:39, 383-391). Conflict audit checklist: the extractor entry (named-only `rdfax:extract-rdfa` since the unnamed-mode `match="/"` was dropped) vs LDH root templates, `body` keydown fallback, host-level event templates, `xsl:output`, `id('content')` assumptions.
10. **v6 note** — view mode renders XMLLiteral via identity transform (`imports/default.xsl:1489-1503`); the eventual v6 in-place model (edit the view markup, PUT canonical doc) is the successor to this form-control integration.

## C. Milestones

- **M1 — Hardening (THIS ROUND, implemented)**: sanitization + HTML paste + a11y/keys + undo caret restoration + in-repo tests/CI + CSS extraction + README; migration plan document in `ldh/`.
- **M2 — Multi-instance component** (DONE): `.rdfa-editor-content` regions, region-keyed undo, scoped ToC/source, `rdfaEditor*` state prefix, `.rdfa-editor-ui` CSS scoping; LDH integration compile-proven (docs/ldh/MIGRATION.md §10).
- **Tables** (DONE): composite table blocks — rows×cols insert dialog (optional header row + caption), positional row/column operations gated on `rdfae:has-spans`, Tab/Shift+Tab + Enter cell traversal that grows the grid at its bottom edge (`src/tables.xsl`).
- **M3 — LDH swap**: the contract above (LDH-side patches + build wiring + e2e in an LDH dev instance).
- **M4 — Vocabulary UX**: typeahead over ontology terms from `/ns`, schema.org vocab, domain/range-aware ranking.
- **M5 — Editing completeness**: nested lists, h4–h6, code/sub/sup, image upload via LDH, cross-node find, i18n strings, Firefox/Safari passes, touch fallback.
- **Beyond**: `@rel`/`@rev` extraction, v6 in-place document editing (PUT canonical XHTML), review/comments.

**User decisions:** LDH materials in a separate folder of this repo (`docs/ldh/`); feature flag deferred (documented); this round = migration plan doc + M1 implementation.

## D. M1 implementation detail

### D1. Sanitization (`src/canonical-xhtml.xsl`)
- Drop subtrees (documented blocklist, priority above shallow-copy): `script | style | iframe | object | embed | applet | form | input | button | select | textarea | link | meta | base`.
- Strip attributes: `@*[matches(local-name(), '^on', 'i')]` (empty template).
- Neutralize URL schemes: drop `@href`/`@src` whose `lower-case(normalize-space(.))` starts with `javascript:`/`vbscript:`/`data:` — except `data:image/` allowed in `@src`.
- Lint additions (shared semantics): `unsafe-attribute` (on\*), `unsafe-url` checks in `src/lint-rdfa.xsl`.
- Fixtures: `canonical/11-sanitization` (script/iframe dropped; onclick stripped; `javascript:` href attr dropped, element kept; `data:image` src kept), `lint/10-unsafe`.

### D2. HTML paste (`src/edit.xsl` onpaste)
- `text/html` non-empty → HTML path; else existing plain-text path.
- Parse: detached `$carrier := createElement('div')` + `innerHTML :=` clipboard HTML (scripts inert when detached; XPath over detached nodes already proven).
- Sanitize: `$clean :=` apply-templates `$carrier/node()` in `mode="cm:canonical"` (now incl. D1 rules).
- Wrap stray top-level inline runs: `for-each-group group-adjacent="boolean(self::p|self::h1|…block…)"` → non-block groups wrapped in `<p>`.
- Re-materialize XDM → live DOM: `serialize()` the fragment → `$stage := createElement('div')` + `innerHTML` (safe post-sanitization).
- Insert:
  - **Inline-only** fragment: `range.deleteContents()`; move `$stage` childNodes into a `createDocumentFragment` (counted `firstChild` loop, order preserved); capture `$last` ref before the move; `range.insertNode($frag)`; caret after `$last` via `rdfae:place-caret(parent, count(preceding-sibling)+1)`.
  - **Blocks into p/h/blockquote host**: push-undo; `rdfae:split-block` at caret; insert pasted blocks after the first half (`xsl:iterate` anchor pattern from section drop); `rdfae:init-block` each (editable + chrome); `rdfae:ensure-placeholder` on halves; caret at end of last inserted block.
  - **Into li/figcaption**: flatten to `string($stage)` through the plain-text path (documented).
- Single push-undo before, after-mutation after; one Ctrl+Z reverts the paste.

### D3. A11y + keyboard
- **Escape** closes: keydown templates on `#overlay` and the three dialogs (input events bubble to the containers) → preventDefault + `rdfae:hide-overlay`/`rdfae:hide-dialogs`.
- **Alt+ArrowUp/Down moves the current block** (keyboard DnD alternative): new dispatcher branch BEFORE the plain-arrow branch (plain arrows must also gain a `not(altKey)` guard); `before(prev)`/`after(next)` sibling move; push-undo + after-mutation; caret survives (node refs move with the block); no sibling → no-op.
- **ARIA** in render templates: `role="dialog" aria-modal="true" aria-label` on overlay + dialogs; `aria-label` mirroring `@title` on toolbar buttons + `role="toolbar"` on `#edit-toolbar`; `role="navigation" aria-label` on `#toc-drawer` and `#breadcrumb`; lint badge becomes a real `<button class="lint-badge">`.
- **Focus return**: hide-overlay/hide-dialogs focus the `activeBlock` host when present. Full focus trap out of scope (documented).

### D4. Undo caret restoration (`src/undo.xsl`)
- `rdfae:push-undo` (and both apply-undo/redo current-state pushes) capture the caret when the selection anchor is a TEXT node inside content, as data attrs on the stash entry (stash lives outside #content): `data-block` (index among content children), `data-node` (index among the block's chrome-free descendant text nodes), `data-offset`.
- `rdfae:restore-snapshot` resolves `content/*[$bi]` → chrome-free `text()[$ni]` → `collapse(min(offset, length))`; bare-`[$index]` predicates; fallback = current first-host behavior. Caret stored with a snapshot = caret when that state existed → symmetric for undo and redo.

### D5. Tests in-repo, CI, packaging
- `tests/browser/{editor,features,fixes}.mjs` (ported suites; `PORT`/`BASE_URL` env); `package.json` (private; devDep `playwright`; scripts `test` → run-tests.sh, `test:browser`).
- `.github/workflows/ci.yml`: setup-node, `npm ci`, `npx playwright install chromium --with-deps`, `python3 -m http.server` background, run both.
- **`rdfa-editor.css`**: all editor-contract styles move out of index.html (overlay/statement/dialogs/buttons, chrome + gutter, DnD marks, ToC drawer, breadcrumb/crumbs, lint badge + `.rdfa-invalid`, toolbar, `#content *[property]`-family RDFa highlighting, scroll-margin, focus outline, modal); demo-only styles stay (body/nav/test-section/demo content box).
- `README.md`: overview, quickstart, test commands, architecture pointer, `docs/ldh/MIGRATION.md` pointer.

### D6. `docs/ldh/MIGRATION.md`
The section-B contract expanded into a step-by-step LDH patch plan: default.xsl form-control swap; form.xsl RenderRowForm init + FormPreSubmit serialization templates; functions.xsl `ol`+`lt` expectations (children only, no wrapper div); layout.xsl asset gate (CSS-only, WYMEditor/jQuery removable at cutover); translations.rdf strings; deferred feature-flag options; build wiring (modules copied into the LDH webapp tree, `xsl:import`ed from client.xsl, compiled by the existing pom `xslt3-he` step); conflict-audit checklist (unnamed-mode `match="/"`, body keydown, host event templates, `xsl:output`, `id('content')` singletons); prerequisites (M2 multi-instance, M4 typeahead).

## Phases + gates

1. **P1 Sanitization**: D1 + fixtures. Gate: all headless loops green (12+11+10 after additions).
2. **P2 HTML paste**: D2. Gate: new Playwright paste assertions (inline junk canonicalized; multi-block Word-ish paste; onclick/javascript: stripped; li flatten; single-undo revert).
3. **P3 A11y/keys**: D3. Gate: Escape/Alt-move/ARIA assertions.
4. **P4 Caret restoration**: D4. Gate: undo returns caret to pre-mutation block/offset (typing + structural cases).
5. **P5 Packaging**: D5 + D6 + README + full regression (all suites, all loops) + commits.

## Verification
`bash tests/run-tests.sh` (3 loops, grown fixture set); `npm run test:browser` (ported suites + new M1 assertions); manual Firefox pass note. Canonical-source purity re-asserted after sanitization changes (no on*/javascript:/script in output).
