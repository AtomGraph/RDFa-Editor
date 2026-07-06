# Built-in XHTML editor (structured blocks, always-editable)

## Context

The RDFa annotation editor (branch `xslt3-annotation-editor`, through commit `3f86b11`) can annotate, edit and extract RDFa, but content itself is only browser-default `contenteditable` on hardcoded demo paragraphs. This plan adds a built-in XHTML editor so documents can be *authored*, not just annotated — the next step toward the LDH v6 "XHTML+RDFa as canonical document format" direction (v6 wiki anticipates RDFa-Editor integration). Architecture stays XSLT 3.0 + SaxonJS (IXSL); no deprecated APIs (`document.execCommand` is out — Selection/Range + explicit DOM ops via `ixsl:call`); W3C conformance non-negotiable.

**User decisions (fixed):**
- **Structured blocks**: each block individually `contenteditable`; block structure never browser-editable. Enter splits, Backspace-at-start merges (intercepted via `ixsl:onkeydown`). Toolbar for block-type changes + inline strong/em/a.
- **Full v1 block set**: p, h1–h3, ul/ol/li, blockquote, pre, figure (img + figcaption). Tables deferred.
- **Drag-and-drop reordering**, porting LinkedDataHub's IXSL templates (`LinkedDataHub/.../bootstrap/2.3.2/client/block.xsl:393-519`).
- **Always editable, Notion-style**: no Edit/Read mode; chrome (⠿ drag handle) revealed on hover.

**Reuse findings:** LDH production edits XHTML via WYMEditor/textarea — rejected (separates content from annotations, jQuery/iframe). The v6 mockup (`"LinkedDataHub Design System"/templates/v6-northwind-products.xhtml:789-973`) is the model: `#content` root container, injected chrome with `data-role="chrome"`, handle-gated `draggable`, dragover midpoint before/after, clone-strip-serialize canonicalization. LDH `block.xsl` provides the IXSL DnD idioms to port.

## Key design decisions

- **Extractor generalization**: skip `*[@data-role]` (not just `='rendering'`) in `src/RDFa2RDFXML-v3.xsl` (skip template + `rdfa:literal-value`) — v6 contract: everything with `data-role` is ephemeral; chrome must not leak into literals. Extend fixture 08.
- **Chrome**: `span[@data-role='chrome'][@contenteditable='false']` as **first child** of each block (keeps split ranges clean of chrome), built via DOM calls (`createElement`/`insertBefore` — immediate node refs; avoids same-handler `xsl:result-document` read-after-write risk). Hover reveal is pure CSS (`#content > *:hover > [data-role="chrome"]`, `visibility` + `position:absolute`). Invalid-XHTML span-in-ul is DOM-only ephemera, always stripped before serialization — documented.
- **Toolbar selection preservation**: `ixsl:onmousedown` + `preventDefault` on toolbar buttons; the block-type `select` can't (kills dropdown) → `window.activeBlock` tracked via `ixsl:onfocusin` on editable hosts; `local:current-block()` = selection-first, activeBlock-fallback.
- **Dialogs** (link, figure): small overlays reusing the render-once/populate/show/hide pattern — not `window.prompt`. Range captured to a window property before showing (existing `window.range` precedent). Positioning math extracted from `local:show-overlay` into shared `local:show-at`.
- **Split inside an annotation span**: move the split point to after the outermost RDFa-attributed inline ancestor — never duplicate `@property` across blocks (would change the graph).
- **Merge**: counted `firstChild`-loop child move (the proven `annotate.xsl` idiom), **no `normalize()`** (would invalidate caret math); caret = `selection.collapse($prev, $childCountBeforeMerge)`.
- **Undo**: v1 = none for structural ops; never intercept Ctrl/Cmd+Z, so native per-block typing undo keeps working. Documented limitation (standards path later: `beforeinput`).
- **Editable region**: `id('content')` by convention; event patterns match `@contenteditable`/chrome classes, only init + DnD use `local:content()`.
- **Output modal**: rename `#rdf-modal`/`#rdf-content` → `#output-modal`/`#output-content` + `#output-title` (shared by Extract RDF and View source; 3 refs in annotate.xsl + smoke test).

## Module layout

```
src/
├── index.xsl                # + includes; main calls local:init-editing after init-overlay
├── overlay.xsl              # extract shared local:show-at positioning
├── annotate.xsl             # extract local:unwrap-element + local:wrap-range; modal renames
├── RDFa2RDFXML-v3.xsl       # data-role generalization (2 lines)
├── edit.xsl                 # NEW (ixsl): init/chrome, toolbar, keyboard, paste, DnD, dialogs, view-source
└── canonical-xhtml.xsl      # NEW (pure XSLT, entity-free): mode="canonical" cleanup/strip
tests/
├── run-tests.sh             # second loop over canonical fixtures
├── normalize-xhtml.xsl      # NEW: whitespace-only-text dropper for XHTML comparison (no c14n — pre safety)
├── fixtures/canonical/NN-name.xhtml + expected/canonical/   # 10 fixtures
index.html                   # #content restructure, CSS, modal rename
```

`generate-sef.sh` unchanged (flat `src/`, `canonical-xhtml.xsl` entity-free so tests bypass `build/`).

## index.html restructure

Demo content moves into `<div id="content" about="" typeof="…document-hierarchy#Container">` with blocks as direct children (h1[property=dct:title], several p (one pre-annotated), ul, blockquote, pre, figure with Mockup.png). Instructions stay outside. **No hardcoded `contenteditable`** — init sets it. CSS additions: chrome reveal, `.drop-before`/`.drop-after` box-shadows + `.dragging` opacity (v6:438-440), `[contenteditable]:focus` outline, toolbar layout. **Fix**: scope the `[about]`/`[typeof]` dashed-border selectors so `#content` itself doesn't get a frame.

## src/edit.xsl signatures

Helpers: `local:content()`, `local:block-of($node)` (ancestor with `parent::div[@id='content']`), `local:host-of($node)` (`ancestor-or-self::*[@contenteditable='true'][1]`), `local:current-block()`, `local:chrome-count($block)`, `local:place-caret($parent,$index)`, `local:remove-chrome($block)`, `local:at-start($host,$container,$offset)` (probe-range `toString() eq ''`), `local:enclosing-annotation($node,$host)`.

Init: `local:init-editing` (toolbar into nav, dialogs rendered hidden, per-block `local:init-block`) — from `main`'s `ixsl:schedule-action` continuation after `local:init-overlay`. `local:init-block`: contenteditable per kind (p/h*/blockquote/pre → self; ul/ol → each li; figure → figcaption only; img never) + `local:inject-chrome`.

Handlers: `ixsl:onkeydown`/`ixsl:onpaste`/`ixsl:onfocusin` on `*[@contenteditable='true']`; toolbar `ixsl:onmousedown` (preventDefault) + onclick per control (block-type select onchange → `local:convert-block` — createElement, copy RDFa attrs + @lang, counted child move, caret restore via saved (textNode, offset)); `local:toggle-inline($name)` (inside → unwrap, else wrap); insert-block/insert-list/insert-figure/delete-block (confirm when non-empty); `#view-source` → `canonical-xhtml($content := local:content())` → `serialize(…, indent)` → output modal.

Paste: preventDefault; `clipboardData.getData('text/plain')`; newlines → space unless host is `pre`; `range.deleteContents()` + `insertNode(createTextNode(…))` + collapse after.

## Keyboard state machine

Guards in order: `isComposing` → return; key ∉ {Enter, Backspace} → return; Enter+ctrl/meta → return. Non-collapsed Enter → `deleteContents()` first.

**Enter**: E1 shift → insert `<br>`; E2 `pre` → insert `'\n'` text node (trailing-newline quirk documented); E3 `li` non-empty → split to new li; E4 empty last `li` → exit list (new p after list; drop li; drop list if empty); E5 empty non-last li → split; E6 `figcaption` → new p after figure; E7 caret inside annotation → `setStartAfter($annotation)` then split; E8 p/h*/blockquote → `local:split-block`.

`local:split-block`: range caret→end of host, `extractContents()` → fragment; `createElement(name($host))` + append; `$host.after($new)`; top-level: set contenteditable + inject chrome; caret `collapse($new, chrome-count)`.

**Backspace** (collapsed only): B1 not at start → native; B2 p/h*/blockquote at start, prev ∈ {p,h1–h3,blockquote} → merge; B3 prev is composite/none → if host empty remove it + focus prev host, else no-op (never merge across composite boundaries in v1); B4 li at start with prev li → merge lis; B5 first li → no-op; B6 figcaption/pre at start → no-op.

## DnD templates (ported LDH block.xsl:393-519 + v6 midpoint)

- handle `ixsl:onmousedown` → `ixsl:set-attribute draggable='true'` on block (handle-gated; permanent draggable breaks selection); `onmouseup` → removeAttribute.
- `ixsl:ondragstart` → `window.draggedBlock := block`; `dataTransfer.effectAllowed='move'` (dotted-path set-property); `setData('application/x-rdfa-editor-block','')`; `setDragImage`; add `.dragging`.
- `ixsl:ondragover` (any node in #content) → gate on draggedBlock + dataTransfer item type; reject self/descendant; eager `preventDefault`; `dropEffect='move'`; clear marks; midpoint (`clientY - rect.top < height/2`) → `.drop-before`/`.drop-after` on target block.
- `ixsl:ondrop` → gate; preventDefault; clear marks; recompute midpoint; `ixsl:call($target, 'before'|'after', [$dragged])`.
- `ixsl:ondragend` → remove `.dragging`/`draggable`, clear marks, `draggedBlock := ()`.
- No dragenter/dragleave (marks recomputed each dragover). Helper `local:clear-drop-marks`.

## canonical-xhtml.xsl (mode="canonical", on-no-match="shallow-copy")

Entry: named `canonical-xhtml($content as element() := /*)`; CLI `-it:canonical-xhtml -s:fixture` (fallback `-im:canonical` if `-it`+`-s` context misbehaves). Rules: C1 drop `*[@data-role]` subtrees; C2 strip `@contenteditable|@draggable|@class|@id|@style|@aria-*|@data-*`; C3 `b`→`strong`; C4 `i`→`em`; C5 unwrap `font|u`; C6 unwrap `span` with no RDFa/lang attrs; C7 attributeless `div`→`p` (RDFa-bearing divs pass); C8 drop empty non-RDFa inlines (keep `<span property resource/>` hidden definitions); C9 drop trailing block `<br>`; C10 `br` in `pre` → `'\n'`; C11 text copied verbatim (never reflow — `pre` exactness).

Fixtures (`tests/fixtures/canonical/`): 01 chrome-strip, 02 rendering-strip (v6 figure pattern), 03 inline-mess, 04 div-normalization, 05 empty-inline-pruning (RDFa spans kept), 06 br-policy, 07 attr-strip (RDFa/href/src/alt/lang preserved), 08 editor-emission-roundtrip (mirror of extractor fixture 11 — the contract), 09 block-set-passthrough, 10 pre-whitespace-lang.

## Phases + gates

0. **SaxonJS probe + extractor change**: scratchpad probe SEF proving `ixsl:onkeydown`/`onpaste`/`onfocusin` fire and text nodes round-trip through `ixsl:call`; then the 2-line `data-role` generalization + fixture 08 extension. Gate: probe green in Chromium+Firefox, `run-tests.sh` green.
1. **canonical-xhtml.xsl headless**: module + normalize-xhtml.xsl + 10 fixtures + second test loop. Gate: both loops green.
2. **index.html restructure + init/chrome/toolbar shell** (+ modal rename, annotate.xsl refs). Gate: SEF builds, page loads clean, editability per kind correct, chrome hover-reveals, updated smoke green (annotation intact), Extract RDF has no chrome literals.
3. **Keyboard + paste** (state machine, split/merge, caret helpers, focusin). Gate: smoke assertions 2–7, 12.
4. **Toolbar actions + dialogs** (+ annotate.xsl `local:unwrap-element`/`local:wrap-range` extraction). Gate: assertions 8–11, 13.
5. **DnD** (seven templates + CSS marks). Gate: assertion 14.
6. **View-source + docs** (CLAUDE.md: new modules, block model, undo limitation, `#content` convention; REFACTORING-PLAN.md addendum) + SEF rebuild + full pass. Gate: everything green, canonical source of live page has zero ephemera.

## Verification

- `bash tests/run-tests.sh` — extractor (12) + canonical (10) fixtures.
- Playwright smoke (scratchpad, port 8080), assertions: (1) init state per kind + chrome count; (2) typing; (3) Enter split partitions text, chrome+editable on new block, caret placed; (4) split near annotation keeps span whole; (5) merge concatenates preserving spans, caret at junction; (6) no merge across composite/first block; (7) empty-li exit; (8) block-type change preserves text+RDFa attrs; (9) bold toggle wrap/unwrap + flash on invalid; (10) link dialog create/edit/remove; (11) figure insert; (12) paste plain-text only; (13) delete block; (14) DnD reorder + cleanup; (15) canonical source free of `data-role`/`contenteditable`/`draggable`/`class`/`id`/`aria-`/⠿; (16) annotation + extraction regression.
- Manual Firefox pass.

## SaxonJS risks (mitigations baked in)

Delegated document-level listeners cover injected chrome (keydown/paste/focusin unproven → Phase 0 probe; `focus` doesn't bubble — use `focusin`); eager `preventDefault` discard-predicate idiom first in intercepting branches (critical for dragover); no same-handler result-document read-after-write (DOM calls only); counted child-move loops (never lazy live-list iteration); explicit `selection.collapse` after every structural move (text-node refs survive reparenting); numeric casts on JS properties; no new global params in included modules (XTSE0630); `xsl:mode` declared once.
