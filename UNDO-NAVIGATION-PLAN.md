# Round 2: unified undo/redo + Fonto-inspired navigation (ToC, breadcrumb, lint, find & replace)

## Context

The XHTML editor (commit `52234aa`) left structural operations non-undoable (native typing undo only) and has no document navigation. The user asked whether undo is supported and to mine FontoXML's editor UX. Decisions (AskUserQuestion): **unified snapshot undo/redo** replacing native undo, plus all four Fonto-inspired features: **ToC drawer** (Fonto outline view) with **section drag-reorder**, **breadcrumb bar** (element path + RDFa subject at caret), **RDFa validation hints**, **find & replace**. Invariants unchanged: XSLT 3.0 + SaxonJS IXSL, no deprecated APIs, W3C conformance, idiomatic XSLT, chrome/ephemera conventions (`@class` IS stripped by canonicalization; `@title` is NOT — validation markers must use class, never title).

## Module layout

```
src/
├── index.xsl          # MOD: +3 includes; window-prop init (undoStack/redoStack via Array(), lastUndoTime=0,
│                      #      lastUndoHost/breadcrumbLeaf/draggedSectionHeading/findNode=(), findOffset=0);
│                      #      local:init calls local:init-navigate after init-editing
├── annotate.xsl       # MOD: push-undo + after-mutation in spo-action/remove-action
├── edit.xsl           # MOD: keydown dispatcher restructure, push points, toolbar +2 buttons (ToC, Find),
│                      #      local:has-block-data → local:has-transfer-type($event,$type), find-dialog in hide-dialogs
├── undo.xsl           # NEW (ixsl): stacks, push-undo, beforeinput coalescer, apply-undo/redo, after-mutation hook
├── navigate.xsl       # NEW (ixsl): ToC drawer + section drag, breadcrumb, lint surfacing, find & replace
└── lint-rdfa.xsl      # NEW (pure XSLT, entity-free, xmlns:lint="urn:rdfa-editor:lint")
tests/
├── run-tests.sh       # MOD: third loop (lint fixtures)
├── lint-driver.xsl    # NEW: xsl:IMPORT of RDFa2RDFXML-v3.xsl + lint-rdfa.xsl (import precedence resolves the
│                      #      xsl:output conflict); output method=text; named template lint-report
├── fixtures/lint/NN-name.xhtml + expected/lint/NN-name.txt   # 9 fixtures (one issue line each; empty = clean)
index.html             # MOD: demo headings (h2 Company, h2 Publications, h3 Queries), CSS inventory below
```

Rationale: `undo.xsl` is cross-cutting (called from edit/annotate/navigate); lint logic pure + headless-tested like the extractor; new nav buttons injected via `local:render-toolbar` (stylesheet stays self-contained). `$base-uri` stays declared only in the extractor (XTSE0630).

## 1. Unified undo/redo (src/undo.xsl)

- Stacks = JS arrays on window (`ixsl:call(ixsl:window(),'Array',[])`); entries = `innerHTML` strings of `#content` (self-contained: chrome + contenteditable included → restore needs no re-init). Cap 100 (`shift()`).
- **`local:push-undo($host?)`**: snapshot `ixsl:get(local:content(),'innerHTML')`; dedup guard (skip if equal to `at(-1)` — backstop against double pushes); push; cap; clear redo (`set-property length 0`); `lastUndoTime := Date.now` (via `ixsl:call(ixsl:get(ixsl:window(),'Date'),'now',[])`), `lastUndoHost := $host`.
- **`local:apply-undo`**: no-op if empty; push current innerHTML to redoStack; pop; restore via `<xsl:for-each select="local:content()"><ixsl:set-property name="innerHTML" select="$snapshot" object="."/></xsl:for-each>`; teardown: hide overlay+dialogs, clear ALL node-valued window props (activeBlock/editingSpan/draggedBlock/editRange/editingLink/insertAfterBlock/range/breadcrumbLeaf/findNode/lastUndoHost); post-restore sweep (clear drop marks, `dragging` class, `@draggable` — snapshots taken in ondrop may carry them); focus + caret on first host (approximate caret restoration by design — exact would need content-polluting markers); `local:after-mutation`.
- **`local:apply-redo`**: symmetric via shared `local:restore-snapshot`; pushes current state onto undoStack RAW (not via push-undo — must not clear redo).
- **Coalesced typing**: `mode="ixsl:onbeforeinput"` on hosts (guard `local:block-of(.)`): if `inputType` starts with `history` → preventDefault + route to apply-undo/redo (covers menu Edit>Undo); else push when >1000ms since last push OR different host, then after-mutation. beforeinput fires pre-mutation, covering typing, native deletes, cut.
- **`local:after-mutation`** — single post-mutation refresh hook: `local:run-lint`; `local:render-toc` when drawer visible; `local:update-breadcrumb`. Called at the END of every mutating handler + from apply-undo/redo + the coalescer. (push-undo runs PRE-mutation, so refreshes must not ride on it.)

### Keydown dispatcher restructure (edit.xsl), exact guard order
1. `$key`, `$ctrl := ctrlKey or metaKey`; 2. scope guard `exists(local:block-of(.))`; 3. IME `isComposing` → return; 4. undo chord (`$ctrl`, no alt, `lower-case($key)='z'`, no shift) → preventDefault ALWAYS (even on empty stack — native undo stays dead in content) → apply-undo, return; 5. redo chord (ctrl+shift+z, or ctrl+y no shift) → preventDefault → apply-redo, return; 6. other ctrl/meta → return (native); 7. Enter (rangeCount≥1) → handle-enter; 8. Backspace (collapsed) → handle-backspace. Steps 3/6/7/8 byte-compatible with today.
Optional coverage: `match="body" mode="ixsl:onkeydown"` handling only steps 4–5, target-guarded `isSameNode(target, .)` — Ctrl+Z works after clicking the background; include it.

### Push-point inventory (P = push-undo first, A = after-mutation last; NEVER in shared primitives — handlers only)
1 handle-enter (P first, A last) · 2 handle-backspace (P/A inside mutating branches B2/B3/B4 only) · 3 onpaste (P after guards) · 4 convert-block · 5 format-inline (both branches) · 6 insert-block · 7 insert-list · 8 figure-save (after $src guard, A before hide-dialogs) · 9 delete-block (after confirm) · 10 link-save (after $href guard) · 11 link-remove · 12 block ondrop (P after guards AND after clear-drop-marks, before the move) · 13 annotate spo-action (P top, A before hide-overlay both branches) · 14 annotate remove-action · 15 ToC section drop · 16 find replace-current · 17 replace-all (P once before loop) · 18 beforeinput coalescer (conditional). Non-push: focusin/keyup/mouseup, dragstart/over/end, cancels, find-next, view-source, parse-rdf, apply-undo/redo.

## 2. ToC drawer (src/navigate.xsl)

- `local:init-navigate`: render `<aside id="toc-drawer" style="display:none"><h2>Contents</h2><div id="toc-list"/></aside>` + breadcrumb footer + find dialog into body (outside #content — no data-role); initial update-breadcrumb + run-lint. Toolbar buttons `#toc-toggle` (☰) and `#find-open` (🔍) added in render-toolbar (existing mousedown-preventDefault template covers them).
- `local:rank($h)` = `xs:integer(substring(local-name($h),2))`. **`local:toc-level($headings, $rank)`** — recursive `xsl:for-each-group group-starting-with="*[local:rank(.) le $rank]"` → nested `ul/li`; item label via `local:block-text()` (chrome-free); `data-index` = position among ALL content headings (`count(... [. << current-group()[1]]) + 1`); handles skipped ranks naturally. Render into `#toc-list` via `xsl:result-document method="ixsl:replace-content"`.
- Toggle opens + regenerates; regeneration also from after-mutation while visible; heading-typing freshness via new onkeyup handler (regen when host is h1–h3 and drawer open).
- Item click: `(local:content()/(h1|h2|h3))[data-index]` → `scrollIntoView(map{'block':'start'})` + focus + place-caret. Navbar overlap solved by CSS `scroll-margin-top` (not JS math).

## 3. ToC section drag-reorder

- **`local:section-of($heading) as element()+`**: `$stop := following h1-h3 with rank le rank($heading); $heading | following-sibling::*[empty($stop) or . << $stop]`.
- ToC li's `draggable="true"` (outside content, no handle gating). dragstart → `draggedSectionHeading := heading-by-index`; dataTransfer type `application/x-rdfa-editor-section` (block vs section types mutually exclusive via generalized **`local:has-transfer-type($event,$type)`**). dragover on toc items → midpoint via existing `local:drop-before` → drop-before/after marks. Drop: no-op guards (`target is source`, target ∈ section-of(source)); push-undo; materialize `$section` refs BEFORE moving; before-drop: sequential `before($anchor := target)`; after-drop: `xsl:iterate` with `$anchor` param starting at `section-of($target)[last()]`, `after`, next anchor = moved node (order-preserving); render-toc + after-mutation. dragend cleanup. Intro blocks before the first heading aren't sections (documented).

## 4. Breadcrumb bar

- `<footer id="breadcrumb"><div id="breadcrumb-path"/><div id="breadcrumb-meta"><span id="breadcrumb-subject"/><span id="lint-badge" style="display:none"/></div></footer>`.
- **`local:update-breadcrumb`**: `$leaf` := element of selection anchorNode (fallback activeBlock); if outside content → clear + subject = document URI. `$ancestors := $leaf/ancestor-or-self::* intersect local:content()/descendant-or-self::*`; store `window.breadcrumbLeaf := $leaf` (single node — same pattern as activeBlock); render `<span class="crumb" data-index="{position()}">` segments (labels via **`local:crumb-label`**: `local-name()` + `[dc:title]`-style compacted `(@property,@typeof)[1]` token via `rdfa:prefixed-name(rdfa:split-uri(...), $rdfa:default-prefixes)`); subject = `rdfa:in-scope-subject($leaf, local:document-uri())`.
- Triggers: existing onfocusin (append call), new host `ixsl:onkeyup` + `ixsl:onmouseup` (no selectionchange — unproven), after-mutation.
- Segment click: re-derive ancestors from stored leaf, `selectAllChildren($ancestors[data-index])`; crumb mousedown preventDefault.

## 5. RDFa validation hints

### Pure module src/lint-rdfa.xsl (headless-tested)
Functions: `lint:in-scope-prefixes($e)` (map:merge over ancestors: defaults ⊕ xmlns ⊕ @prefix, use-last), `lint:in-scope-vocab($e)` (nearest @vocab, ''=reset), `lint:path($e)` (= `rdfa:bnode-label`), `lint:lintable($root)` (descendants minus head/script/style/`*[@data-role]` — extractor parity), **`lint:element-issues($e) as element(lint:issue)*`** (`code` + `path` attrs, message content):
- (a) `term-unresolvable`: any token of @property/@typeof/@datatype where `rdfa:resolve-term-or-curie(...)` is empty (scheme-shaped values pass by design; console xsl:message noise accepted);
- (b) `empty-href`: `a[@href][normalize-space(@href)='']`;
- (c) `content-resource-conflict`: `@property and @content and @resource` (step-11 orphaning);
- (d) `empty-literal`: mirrors the extractor's statement branches exactly — literal-valued @property whose value is '';
- (e) `about-relative`: non-empty @about that isn't ''/#…/_:…/CURIE/absolute-scheme (editor emits absolute IRIs — near-certain typo).

CLI: `tests/lint-driver.xsl` (xsl:import both modules → text output wins by import precedence; named `lint-report`, `$content := /*`); third run-tests.sh loop diffs against `expected/lint/NN.txt`.
Fixtures: 01 valid-clean(empty) · 02 unresolvable-terms(3) · 03 curie-defaults incl. scheme-shaped `unknownpfx:x` passing(empty) · 04 empty-href(2) · 05 content-resource-conflict(1; without @property clean) · 06 empty-literal(1 + counter-cases clean) · 07 relative-about(1; ''/#/_:/absolute clean) · 08 vocab-scope(@vocab resolves bare term; vocab='' reset → 1) · 09 excluded-subtrees(broken RDFa in rendering/script/head → empty).

### Browser surfacing (navigate.xsl)
`local:run-lint` from after-mutation + init: sweep old `rdfa-invalid` classes; add class to flagged elements (class-only — canonicalization-stripped, extractor-invisible; **@title forbidden**); badge count in breadcrumb; badge click recomputes and lists issues via `local:show-output`. Lint classes in snapshots self-heal via the sweep.

## 6. Find & replace (navigate.xsl)

- `#find-dialog` (edit-dialog pattern): find/replace inputs, match-case checkbox (default off = case-insensitive), buttons find-next/replace-current/replace-all/find-close, `#find-status`; mousedown preventDefault (keeps the selection-highlight alive); added to `local:hide-dialogs` (+ clear findNode/findOffset). No Ctrl+F hijack.
- Search space: `local:content()//text()[not(ancestor::*[@data-role])]`, single-text-node matches only (annotation-safe; documented).
- State: `window.findNode` (text node), `window.findOffset` (1-based next-scan start). Helpers: `local:norm($s,$ci)` (lower-case), `local:find-in($hay,$from,$query,$ci) as xs:integer?` (substring-before math; lower-case() length anomalies documented).
- **find-next**: wrap-around scan plan as a sequence of `map{'n':node,'from':int}` (current-from-offset, following, preceding, current-from-1) + `xsl:iterate`/`xsl:break`; on hit: focus host FIRST, then `setBaseAndExtent($n, p-1, $n, p-1+len)` (selection = highlight), `scrollIntoView(map{'block':'center'})` on parentElement, update state + breadcrumb; miss → "No matches".
- **replace-current**: operate on the live selection (guards: not collapsed, in content, normalized text = query) else just find-next; push-undo; deleteContents + insertNode(new text) ; findNode := new node, findOffset := len+1 (no re-match inside replacement); after-mutation; find-next.
- **replace-all**: push-undo once; materialize $texts; per node `local:replace-in-string(...) as map{'value','count'}` (recursive) → one `nodeValue` property write per node (NO structural change — annotation-safe by construction); status "N replaced"; after-mutation. Fallback if nodeValue write fails probe: per-occurrence Range surgery.

## 7. index.html

- Demo content: add `<h2>Company</h2>`, `<h2>Publications</h2>`, `<h3>Queries</h3>` (no RDFa — extractor expectations untouched; smoke positional assumptions updated).
- CSS: body padding-bottom 56px; `#content > * { scroll-margin-top: 76px; }`; toc drawer (fixed left 260px, top 64/bottom 44); toc list/label/hover + scoped drop marks; breadcrumb footer (fixed bottom, flex, z-1000); crumb/crumb-sep/subject styles; `.lint-badge` red pill; `#content .rdfa-invalid { text-decoration: underline wavy #f44336; }`; checkbox-label for the find dialog.

## Phases + gates

0. **Probe** (scratchpad, extend probe/probe.xsl + probe.mjs): beforeinput+inputType; Array()/push/pop/at(-1)/length=0; Date.now; **innerHTML snapshot/restore + delegated keydown still fires in restored subtree**; setBaseAndExtent; scrollIntoView with XDM-map arg; text-node nodeValue write. Fallbacks: beforeinput→keydown coalescing; nodeValue→Range surgery; map-arg→argless scrollIntoView. Gate: green in Chromium.
1. **Lint headless**: lint-rdfa.xsl + driver + 9 fixtures + third loop. Gate: all three loops green (12+10+9).
2. **Undo/redo**: undo.xsl (after-mutation as no-op shell), dispatcher restructure, push points 1–14+18, index.xsl wiring. Gate: SEF builds; existing 16 smoke groups + new groups 17–19 green.
3. **ToC + breadcrumb + lint surfacing**: navigate.xsl, fill after-mutation, triggers, CSS. Gate: smoke 20–22, 24–25; view-source purity (no rdfa-invalid/class in output); extractor unchanged.
4. **Find & replace**. Gate: smoke 26 incl. undo-of-replace-all + annotation integrity.
5. **ToC section drag**. Gate: smoke 23 incl. self-drop no-op, order preservation, undo of section move.
6. **Docs + regression**: CLAUDE.md (modules; replace undo-limitation note with the snapshot contract "every mutating handler pushes first, refreshes after"; new constraint: content markers only via @class/aria-*, @title forbidden), XHTML-EDITOR-PLAN.md Round-2 addendum, SEF rebuild, full smoke + loops, manual Firefox note. Commit.

## Smoke additions (editor-smoke.mjs groups 17–27)

17 undo-typing coalescing (two bursts >1.1s apart undo separately) · 18 undo-structural (split, delete, block DnD w/o stale artifacts, annotation apply/remove) · 19 redo semantics (shift+z & ctrl+y; fresh edit clears redo; empty-stack no-op w/ default prevented) · 20 ToC render (hierarchy, labels chrome-free) · 21 ToC navigation (scroll + caret) · 22 ToC liveness on heading edit/split · 23 section drag (contiguous ordered move incl. h3 sub-blocks; self-drop no-op; undo) · 24 breadcrumb (paths, annotated-span label, subject URI, li path, segment click selects) · 25 lint (clean load → no badge; bad property → squiggle + badge + modal list; fix clears; view-source & Extract RDF unaffected) · 26 find/replace (case-insensitivity, wrap-around, match-case, replace advances, annotation-safe, cross-span "No matches", replace-all count, single undo reverts) · 27 groups 1–16 regression + all test loops.

## SaxonJS risks

beforeinput/innerHTML-restore/nodeValue/map-args gated by Phase 0 with fallbacks; one-template-per-mode-per-element (undo chords INSIDE the existing host keydown dispatcher — a second template would shadow); body fallback target-guarded; all node-valued window props cleared on restore; ondrop pushes after clear-drop-marks; restore sweeps dragging/draggable; xsl:message noise from resolve-term-or-curie during lint accepted (keeps extractor byte-identical); caret restoration after undo approximate (documented).
