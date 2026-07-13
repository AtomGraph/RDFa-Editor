# Embed LDH's RDF-defined blocks as atomic RDFa islands (core + extension)

## Context

LinkedDataHub's content blocks (`ldh:Object`, `ldh:View`, `ldh:ResultSetChart`, queries) are RDF resources rendered client-side by LDH's SaxonJS XSLT (`ldh:RenderRow`-mode templates on `div[@typeof]`, async promise chains → SPARQL → Google Charts). In LDH they form a **flat top-level `rdf:_N` sequence** — a chart inside a list item is impossible. We want them embeddable in RDFa-Editor regions **wherever an XHTML block element can go** (region top level, `li`, `td`, `blockquote`, `dd`), treated as **atomic island blocks**: never editable inside, navigable/selectable/deletable like image islands, hard boundaries for merges and cross-host deletes, byte-identical round-trip.

**Decisions made with the user:**
1. **Storage = self-describing RDFa**: a `div` placeholder using the conformant containment idiom, defining triples inline as RDFa spans; extracting the document yields the full block definition.
2. **Rendering = overridable hook + async fixture demo**: rendering lands in an injected `div[@data-role='rendering']` (extractor skips it, canonicalization drops it — the LDH v6 contract already in place); the default demo renderer does real async hydration from local fixture RDF files via the **SaxonJS 3 promise API** (`ixsl:promise` + `ixsl:http-request` → `ixsl:then` chains, exactly LDH's `ldh:*-thunk` idiom — see LDH block.xsl:582-596). **Never `ixsl:schedule-action`** — legacy, banned in this project.
3. **Insertion = dialog + slash menu**, placed via the existing `local:insert-block-at-caret`.
4. **Packaging = optional extension stylesheet layered via `xsl:import`**: the core gains only a *generic* island mechanism with zero LDH knowledge; all LDH specifics live in an extension module whose contract doubles as the real LDH integration contract (LDH's client.xsl already composes with the editor — docs/ldh/MIGRATION.md §10).

Full design rationale with every anchor verified: `/Users/martynas/.claude/plans/we-need-to-make-flickering-mountain-agent-ac9d0adb33f0ef66a.md`. Key claims independently re-verified: all 11 src modules share `xmlns:local="urn:rdfa-editor:functions"` (so import-precedence override of `local:*` works); `local:init-block`'s text-host branch would make an island div contenteditable (edit.xsl:325-330); `local:merge-host-in` (edit.xsl:88-93) would leapfrog a tail island (islands contain no hosts to trip the composite intersect); `local:clamped-range` (select.xsl:117-135) already escapes `@data-role` — islands mirror it; generate-sef.sh c14n-flattens `src/*.xsl` (maxdepth 1) into `build/` and compiles one entry.

## 1. Storage contract

Placeholder (stored/canonical/clipboard form; real output uses absolute IRIs):

```html
<div property="https://w3id.org/atomgraph/linkeddatahub#content" resource="#chart1"
     typeof="https://w3id.org/atomgraph/linkeddatahub#ResultSetChart">
  <span property="http://spinrdf.org/spin#query" resource="queries/population/#this"></span>
  <span property="https://w3id.org/atomgraph/linkeddatahub#chartType" resource="https://w3id.org/atomgraph/client#BarChart"></span>
  <span property="https://w3id.org/atomgraph/linkeddatahub#categoryVarName" content="country"></span>
  <span property="https://w3id.org/atomgraph/linkeddatahub#seriesVarName" content="population"></span>
</div>
```

Extracts (base B, region `about=""`): `<B> ldh:content <B#chart1> . <B#chart1> a ldh:ResultSetChart; spin:query <resolve(queries/population/#this, B)>; ldh:chartType ac:BarChart; ldh:categoryVarName "country"; ldh:seriesVarName "population"` — verified against the extractor's `@resource` branch (RDFa2RDFXML-v3.xsl:118-127) and typed-resource chaining (:175-182). Canonicalization verified safe: C1 drops the rendering div (canonical-xhtml.xsl:119), C7a/C7b exclude RDFa-bearing divs (:170-183), C6/C8 keep RDFa-bearing empty spans, C2 strips `tabindex`, N1 only touches inline-only names (div is flow), `cm:wrap-inline-runs` passes divs bare. Lint: zero issues (empty-literal has a `not(@resource)` guard, lint-rdfa.xsl:90). Editing DOM adds only ephemera: `tabindex="-1"`, marker class `rdfa-editor-island`, the rendering div, top-level chrome.

Note: `ldh:content` is not (yet) declared in ldh.ttl 1.1.6 — it's the agreed v6 containment convention; only extension markup templates would change if LDH names it differently.

## 2. Core: new module `src/blocks.xsl` (generic, zero LDH knowledge)

ixsl-bearing (like tables.xsl), `xsl:include`d from src/index.xsl. Contents:

- `<xsl:param name="object-block-types" as="xs:string*" select="()"/>` — absolute class IRIs; default empty.
- **The single island predicate** — every island decision routes through it:
  `local:island($e)` = `exists($e[self::div][tokenize(@typeof) = $object-block-types])`.
- **Render hook**: `<xsl:mode name="local:render-island" on-no-match="deep-skip"/>` — context item = the island div. Contract: inject exactly ONE `div[@data-role='rendering']` as last child via `local:replace-rendering`; async renderers inject it **only in the completion callback** (loading state = ephemeral class `rdfa-editor-loading`), so "no rendering div" always means "re-render needed" (undo-restore keys on that); never touch the RDFa spans; never push undo; idempotent. Core ships a neutral synchronous default (`match="*"`, low precedence): a static card showing type + resource.
- `local:replace-rendering($island, $content)` — the ONLY writer of the rendering div: remove existing, create div via `local:element('div')` + `ixsl:set-attribute data-role='rendering'`, innerHTML via `serialize($content, map{'method':'html'})` (never xml — self-closing tags swallow siblings), appendChild.
- **Empty extension hook stubs** (overridden by extensions at higher import precedence): `local:render-extra-dialogs`, `local:render-extra-insert-buttons`, `local:render-extra-slash-items`, `local:run-extra-slash-command($command, $host)`.

CSS (`rdfa-editor.css`): `.rdfa-editor-island` card affordance, `:focus` outline (selected state, mirrors image islands), `.rdfa-editor-loading` dimming. Class markers only (canonicalization-stripped).

## 3. Core: edit.xsl wiring (verified anchors)

- **`local:init-block` (:317-362)** — new FIRST `xsl:when test="local:island($block)"`: remove `contenteditable` (defensive), set `tabindex="-1"`, add class `rdfa-editor-island`, fire `mode="local:render-island"` when `empty($block/*[@data-role='rendering'])`; no recursion, no wrap-stray-runs. The img-tabindex loop (:354-356) gains `[empty(ancestor::*[@data-role])]` (imgs inside rendering never focusable). Chrome injection (:357-361) already runs after the choose — top-level islands get drag handles free; nested islands get none (nested-table doctrine).
- **`local:nav-targets` (:99-103)** — add `or local:island(.)` plus trailing filters `[empty(ancestor::*[@data-role])][empty(ancestor::*[local:island(.)])]`.
- **`local:select-image` (:222-228)** → rename **`local:select-island`** (body unchanged: removeAllRanges + focus); update call sites :236, :255. `local:land-forward/-backward` (:232-270): branch test becomes `$target/self::img or local:island($target)`.
- **Generalize the two img event templates** (:810 onkeydown, :902 onfocusin) to match `*[contains-token(@class, 'rdfa-editor-content')]//*[self::img or local:island(.)]`. Delete victim (:861-862) generalizes to `($target/ancestor-or-self::figure[exists(local:block-of(.))][1], $target)[1]` — an island deletes itself; the existing `local:collapse-container` call (:873-877) handles islands-in-li/td. Ctrl+A stage-2 and arrow nav generalize unchanged.
- **`local:merge-host-in` (:88-93)** — bind `$host := local:last-host-in($element)`, add island to the composite intersect test AND the tail-island guard (islands contain no hosts, so without it the merge leapfrogs a tail island):
  `[empty(ancestor-or-self::*[self::table or self::figure or local:island(.)] intersect $element/descendant-or-self::*)][empty($element/descendant-or-self::*[local:island(.)][. >> $host])]`
- **B3 caret landing (:1203-1216)** — when the removed empty host's `$prev` is an island, `local:select-island($prev)` (the contenteditable descendant lookup is empty). Backspace at start of a non-empty host after an island stays inert (falls through) — same doctrine as tables.
- **Hook call sites**: `local:init-editing` (:280-287) calls `local:render-extra-dialogs`; toolbar Insert group (:461-464) calls `local:render-extra-insert-buttons`.
- **Dialog teardown generalization**: Escape match (:2064-2069) and `local:hide-dialogs` (:2072-2090) keyed on class `edit-dialog` (all four existing dialogs carry it — verified edit.xsl:1977, 2111, tables.xsl:121, navigate.xsl:518) + the slash menu, instead of hardcoded ids. Extension dialogs opt in via the class.
- **No changes needed** (verified): `delete-block` button (island's `local:block-text()` = '' ⇒ deletes without confirm, image-island doctrine); Alt+Arrow, Tab/Enter machines (host-only); block-type select/quote toggle disable via `local:sync-format-toolbar`; paste (canonical strips rendering, re-init re-renders); drag (chrome-gated); breadcrumb already labels `div[<typeof>]` (navigate.xsl:262-264).

## 4. Core: select.xsl, undo.xsl, input.xsl

- **`local:clamped-range` (select.xsl:117-135)**: after the `@data-role` escapes (:128-133), mirror for islands — start container inside an island → `setStartBefore` it; end container → `setEndAfter`. Establishes the invariant "a range boundary never sits inside an island" for the delete machine AND canonical copy (both call it). With that, the delete machine's removals doctrine needs **no island branch** — covered islands are removed whole via the existing rules (:520-527).
- **`local:caret-at-point` (select.xsl:144-176)**: mirror the chrome escape — a point resolving inside an island moves to just after it (sweep anchors never inside islands).
- **Guards**: `$collapse-candidates` (select.xsl:536-539) gains `[not(local:island(.))]`; `local:collapse-container` (edit.xsl:367-388) guard gains `not(local:island($container))` — otherwise a span-only island would be collapsed into a contenteditable text host.
- **Canonical copy**: no change (mode canonical strips rendering/tabindex, keeps the placeholder).
- **`local:restore-snapshot` (undo.xsl:159-221)**: after chrome re-injection (:170-177), re-render only unrendered islands: `for-each $root//*[local:island(.)][empty(*[@data-role='rendering'])]` → apply `local:render-island`. Snapshots carry rendering markup, so restores are byte-deterministic; only mid-flight captures re-fire (guaranteed by the inject-in-callback contract).
- **input.xsl**: `local:render-slash-menu` (:224-240) calls `local:render-extra-slash-items` inside `ul.slash-items`; `local:run-slash-command`'s empty `xsl:otherwise` (:361) calls `local:run-extra-slash-command($command, $host)`. `local:open-slash` unchanged — unknown commands hit the `else true()` availability arm (:268), correct since a div is placeable wherever blocks are.

## 5. Extension: `src/ldh-blocks.xsl` + entry `src/ldh-editor.xsl`

Both at src/ **top level** (generate-sef.sh's `find -maxdepth 1` c14n; sibling hrefs survive the build/ flattening).

**src/ldh-editor.xsl** (demo/dist entry):
```xml
<xsl:import href="index.xsl"/>      <!-- core at lower import precedence -->
<xsl:include href="ldh-blocks.xsl"/> <!-- extension at the entry's precedence -->
```
Legal by import-precedence rules: `$object-block-types` re-declaration (XTSE0630 forbids duplicates only at the SAME precedence), named-template overrides of the hook stubs, same-mode template rules beating the imported catch-all. `main` stays invocable from the imported module; ixsl event templates register across imports (the MIGRATION.md §10 compile-proof covers this shape). `make sef` after step 1 proves it immediately.

**src/ldh-blocks.xsl**:
1. `$object-block-types` = the three absolute IRIs (`…#Object`, `…#View`, `…#ResultSetChart`).
2. **Fixture renderers** — three `mode="local:render-island"` templates matching per typeof + required definition span (mirroring LDH's `ldh:RenderRow` guards). Flow: resolve the query/value IRI against `local:document-uri()` (NOT dist-relative — the span's `@resource` resolves against the page base per RDFa, so `-relocate:on` is moot and no fixture copying is needed); `$query-doc = substring-before($query-uri || '#', '#')`; fetch URLs map the clean IRI to files: `$query-doc || '.rdf'` and `$query-doc || '-results.xml'` (demo-only shim, extensions never in storage); add loading class; then the **SaxonJS 3 promise chain** (LDH's exact idiom, block.xsl:582-596 — NEVER `ixsl:schedule-action`):
   ```xml
   <ixsl:promise select="
       ixsl:http-request(map{ 'method': 'GET', 'href': $query-doc,
                              'headers': map{ 'Accept': 'application/rdf+xml' } }) =>
           ixsl:then(local:block-query-response($island, $query-uri, $results-doc, ?))"
       on-failure="local:block-render-failure($island, ?)"/>
   ```
   `local:block-query-response` (partial application closes over `$island`/`$query-uri`/`$results-doc`; `ixsl:updating="yes"`): check `$response?status = 200` and XML `?media-type`, pull `sp:text` for `$query-uri` from `$response?body` (a `document-node()`), then issue the second promise (`ixsl:http-request` for `$results-doc`) whose callback `local:block-results-response` builds the content — `<pre>` with the query text + an HTML `<table>` of the SRX rows (+ chart caption read from the island's own spans) — hands it to `local:replace-rendering` and clears the loading class. `local:block-render-failure` (`on-failure`, both promises): error card via `local:replace-rendering`, loading class cleared — a failed fetch must never wedge the loading state. Object block: same shape, one fetch of the resource description, rendered as a property/value table. Note: this introduces the repo's **first** `ixsl:promise` — there is no async instruction in src/ today.
3. **Insert dialog** `div#ldh-block-dialog.rdfa-editor-ui.edit-dialog` (class opt-in ⇒ Escape/teardown free): block-type select (Object/View/Result set chart, values = class IRIs), fragment-id input, per-type fieldsets toggled via ixsl:onchange (`ixsl:set-style`): Object → resource URI (`rdf:value`) + optional `ac:mode`; View → query URI (`spin:query`) + optional `ac:mode`; Chart → query URI, chart-type select (ac Table/Bar/Line/Scatter → `ldh:chartType`), category/series var names (`@content` spans). Save (modeled on `table-save`, tables.xsl:159-217): validate → `local:push-undo` → build div+spans via `local:element` + `ixsl:set-attribute` (RDFa must be real attributes; DOM-built, no serialization) → `local:insert-block-at-caret` with `insertHost` → render → `local:select-island` → `local:after-mutation` → `local:hide-dialogs`.
4. **Slash + toolbar contributions**: `local:render-extra-slash-items` emits `<li class="slash-item" data-command="ldh-block">Block…</li>` (generic filter/arrow/Enter machinery applies); `local:run-extra-slash-command` handles `'ldh-block'` (re-arm `insertHost`, show dialog via `local:show-at-element` — mirroring the table branch, input.xsl:340-360); `local:render-extra-insert-buttons` emits a toolbar button mirroring `insert-table` (tables.xsl:137-157).

**LDH integration contract** (document in MIGRATION.md): in real LDH, client.xsl plays the ldh-blocks.xsl role — sets `$object-block-types`, and its `mode="local:render-island"` templates bridge into the existing `ldh:RenderRow` machinery with the rendering div as container. The editor never learns LDH types; LDH never learns editor internals beyond the mode + `local:replace-rendering` + the hook stubs.

## 6. Build + demo

- **generate-sef.sh**: compile line becomes `-xsl:./build/ldh-editor.xsl` (same output `dist/index.xsl.sef.json` — single SEF, zero-setup demo; core-only consumers compile src/index.xsl themselves — one Makefile comment). Vocabs copy unchanged; **no fixture copy** (document-URI resolution).
- **Demo fixtures** (new, served from repo root): `demo/queries/population.rdf` (`sp:Select` description with `sp:text`), `demo/queries/population-results.xml` (SRX rows), `demo/resources/ada.rdf` (Object target).
- **index.html**: add a ResultSetChart block to `#content` (`resource="#population-chart"`, spin:query `resource="queries/population/#this" (on demo/index.html)`); Help-modal sentence.
- **tests/browser/run.mjs**: add `'.xml': 'application/xml'` and `'.rdf': 'application/rdf+xml'` to the mime map; add `'blocks'` to the suite list. (`ixsl:http-request` parses the response body to a `document-node()` based on the media-type, so the fixtures must be served as XML types; python http.server on macOS maps both via Apache mime.types — the `on-failure`/media-type guard shows the error card if a host maps them wrong.)

## 7. Tests

Headless (run against src/ — island storage-form behavior is all core/pure-XSLT):
- `tests/fixtures/14-ldh-block-island.xhtml` + expected RDF (the §1 triples; include a nested island inside an `li`).
- `tests/fixtures/canonical/23-ldh-block-placeholder.xhtml` + expected: island laden with ephemera (tabindex, marker classes, chrome, populated rendering div, run-wrapped sibling) ⇒ clean placeholder, byte-identical spans; plus an attributeless-div control pinning C7a/C7b.
- `tests/fixtures/lint/10-ldh-block-clean.xhtml` + empty expected.

Browser (`tests/browser/blocks.mjs` against tests/fixture-nesting.html, which gains a top-level ResultSetChart island — `resource="../demo/queries/population/#this"`, page-relative — and a nested View island in an li):
1. init/render: uneditable, tabindex, spans un-wrapped, rendering table appears (awaited), chrome top-level only;
2. canonical round-trip via view-source;
3. nav battery: arrows select/leave, Backspace deletes, undo restores + re-render leaves placeholder intact;
4. slash "Block…" → dialog → insert in region and in an empty li;
5. stage-2 Ctrl+A + Delete → reseed; sweep across the island → removed whole, no span residue;
6. Backspace boundary doctrine;
7. canonical copy over an island (clipboard text/html);
8. breadcrumb label + disabled block-type select.
- invariants.mjs: one render-settle wait before baseline capture (rendering populated); battery unchanged.

## 8. Risks / gotchas

- `serialize(…, map{'method':'html'})` on every innerHTML write (self-closing div/span swallows siblings).
- `local:island()` in match patterns reads a global param — legal XSLT 3.0; if the SaxonJS compiler balks, inline `self::div[tokenize(@typeof) = $object-block-types]` (variable refs in pattern predicates are safe). De-risk: `make sef` right after step 1.
- **`ixsl:schedule-action` is banned** (legacy pre-SaxonJS-3) — all async goes through `ixsl:promise`/`ixsl:http-request`/`ixsl:then` with `on-failure`. DOM-mutating promise callbacks must be declared `ixsl:updating="yes"` (LDH precedent, e.g. `ldh:ontology-view-render-thunk`); the failure handler must clear the loading state and render an error card. Verify SaxonJS 3's exact `on-failure` arity against the LDH usage (`ldh:promise-failure#1`) when writing the handlers.
- Async rendering mutates the region outside push-undo ⇒ a visually-idle undo step is possible; harmless (canonical content identical), documented.
- `$object-block-types` re-declaration ONLY at higher import precedence, never in a second core include.
- Always `tokenize(@typeof) = $object-block-types`, never string equality (multi-token typeof).
- Keep core entity-free where headless suites run src/ directly; extension entities are fine (c14n expands for the SEF).

## 9. Implementation order + verification

1. src/blocks.xsl + index.xsl include + CSS → `make sef` (proves pattern legality).
2. edit.xsl wiring (§3) → `make sef`, browser spot-check.
3. select.xsl + undo.xsl + input.xsl (§4).
4. ldh-blocks.xsl + ldh-editor.xsl + generate-sef.sh + demo/ + index.html.
5. Headless fixtures → `make test`.
6. fixture-nesting.html + blocks.mjs + run.mjs + invariants wait → `make test-browser`.
7. Docs: CLAUDE.md module list (blocks.xsl, ldh-blocks.xsl, ldh-editor.xsl entry, build note), README, MIGRATION.md `local:render-island` integration surface.

Final manual check: `make up` → the population chart hydrates async on index.html; view-source shows the clean placeholder; Extract RDF shows the §1 triples; drag/slash-insert/delete/undo/copy-paste behave per §8 of the agent plan.

## Amendments during implementation

1. **`ixsl:schedule-action` is banned** — all async uses the SaxonJS 3 promise API
   (`ixsl:promise` + `ixsl:http-request` `=> ixsl:then`, `on-failure`, callbacks as
   `ixsl:updating="yes"` functions with partial application), exactly LDH's
   `ldh:*-thunk` idiom.
2. **Clean Linked Data URLs throughout** — document URIs end with a trailing slash
   (`demo/queries/population/#this`), representations come from **content
   negotiation** on the clean URI (`Accept: application/rdf+xml` → the description;
   `Accept: application/sparql-results+xml` on a query document → canned results, a
   demo stand-in for live SPARQL execution). File extensions appear nowhere: not in
   storage, not in fetch code, not in fixtures (`demo/queries/population/index.rdf` +
   `results.xml` are server-private file names). `make up` therefore serves via
   `node serve.mjs` (conneg-aware) instead of python http.server; tests/browser/run.mjs
   negotiates the same way.
3. **Core/LDH split with core-only GitHub Pages** — two SEFs: `dist/index.xsl.sef.json`
   (core, from src/index.xsl — what deploy-pages.yml publishes, minus the LDH
   artifacts) and `dist/ldh-editor.xsl.sef.json` (core + extension — used by the new
   `demo/index.html` showcase page and the browser fixtures; local-only, needs
   conneg). index.html carries no LDH markup.
4. **Islands got their own browser fixture** (`tests/fixture-blocks.html` +
   `tests/browser/blocks.mjs`) instead of extending fixture-nesting.html — keeps the 13
   existing suites' block enumeration byte-stable. fixture-nesting.html still loads the
   ldh-editor SEF, proving the extension layers without disturbing core behavior
   (notion.mjs counts its 11th slash item).
5. **Undo/redo chords on a focused island** — the host/body keydown templates don't
   fire with focus on an island (a pre-existing gap for image islands too), so the
   generalized island keydown template intercepts Ctrl/Cmd+Z / Shift+Z / Ctrl+Y itself.
6. **Block markup follows the v6 document format** (the
   [XHTML-RDFa-as-LDH-v6-Document-Format](https://github.com/AtomGraph/LinkedDataHub/wiki/XHTML-RDFa-as-LDH-v6-Document-Format)
   wiki, which supersedes the plan's §1 storage contract): blocks carry
   `@about="#fragment"` + `@typeof` directly — NOT the `property="ldh:content"
   resource=` containment idiom (in v6 `ldh:content` is the document→body XMLLiteral
   property, never a per-block edge; there is no document→block triple and no
   `rdf:_N` — order is document order). Literal definition values are span TEXT
   content (`<span property="ldh:categoryVarName">country</span>`), not `@content` —
   which also matches LDH's renderer selectors verbatim. Island detection was already
   `@typeof`-keyed, so the mechanism was unaffected; the dialog emission, demo pages,
   fixtures and expected files were updated. v6's render mode is `ldh:Block`
   (`ldh:RenderRow` is the v5 name the §12 bridge example targets).
