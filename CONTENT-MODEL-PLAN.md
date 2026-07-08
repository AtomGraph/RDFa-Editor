# Make the editor true to the XHTML content model

> **Status: IMPLEMENTED** (both phases, 2026-07-08). All headless suites (45) and browser suites (10, incl. new `nesting.mjs` + `authoring.mjs`) green. See CLAUDE.md for the updated module contracts.

## Context

The editor's content handling is an ad-hoc flat-block model that neither allows everything the XHTML DTD allows nor forbids everything it forbids:

- **Too restrictive**: paste flattens block content to text inside `li`/`figcaption`/`td`/`th`/`caption` (`src/edit.xsl:874`); nested lists are impossible; `li`/`td`/`th` are `%Flow;` in XHTML (inline AND blocks) but treated as text-only.
- **Non-conformant**: `blockquote` is treated as a text block, but XHTML 1.0 Strict/1.1 defines it as `(%block;)+` — bare inline text directly inside is invalid; canonical's content-blind `div→p` (`src/canonical-xhtml.xsl:84`) can produce invalid `p > block` nesting.
- **No single source of truth**: block/inline knowledge is scattered (fixed-depth XPath in `local:init-block` `src/edit.xsl:251`, `$local:block-names` `:804`, closed host-kind branches in the Enter/Backspace machines); neither lint nor canonical knows the content model.

Goal: every nesting the XHTML DTD allows is authorable and round-trips intact; every nesting it disallows is normalized at boundaries and reported by lint.

## Decisions (user-confirmed)

1. **Scope**: full authoring — nested lists, blocks in list items, blocks in blockquote, blocks in table cells.
2. **Normative schema**: **XHTML 1.0 Strict (Appendix A DTD + Appendix B prohibitions) / XHTML 1.1, extended with HTML5 `figure`/`figcaption`**. Consequences: `p`/`h1–h6` inline-only; `blockquote` block-only (wraps paragraphs); `li`/`dd`/`td`/`th`/`div` flow; `ul|ol → (li)+`; `pre` excludes img/object/big/small/sub/sup; no `a`-in-`a`; `caption`/`dt` inline-only; `figcaption` flow (HTML5).
3. **Invalid input**: **normalize at boundaries + live lint** — wrap stray inline runs in `p` inside block-only containers, hoist/split blocks out of inline-only elements, always RDFa-preserving; new nesting lint checks.
4. **Delivery**: **staged** — Phase 1 foundation (shippable: valid nested XHTML round-trips, invalid input normalized/linted, editor gestures never produce invalid markup), Phase 2 authoring gestures.
5. **Mixed flow content** (`<li>text<ul>…</ul></li>` — valid Strict): preserved byte-identical via an **ephemeral editing-DOM run wrapper** `p.rdfa-editor-run` (class marker per the content-marker contract; unwrapped at canonicalization; promoted to a real `p` by structural gestures like Enter-split/convert; never by plain typing).

## Design core

New **pure-XSLT `src/content-model.xsl`** (namespace `cm:`, no `ixsl:`, include-free — same anti-drift pattern as `lint-rdfa.xsl`): 1:1 transcription of the DTD entities (`%inline;`, `%block;`, `%flow;`, `%pre.content;`, `%a.content;`) as `xs:string*` variables, one master `$cm:model as map(xs:string, map(*))` (per element: allowed child names + `#PCDATA` flag), `$cm:prohibitions` (Appendix B). Functions: `cm:known`, `cm:block`, `cm:inline`, `cm:allows-child(parent, child)`, `cm:allows-text`, `cm:inline-only`, `cm:flow` (text + blocks), `cm:structural` (element-only: ul/ol/dl/table-parts/blockquote), `cm:prohibited-ancestors`, `cm:valid-nesting(element)`. Header cites REC-xhtml1-20020801 + WHATWG HTML §4.4.12–13. The editor contract "region children are blocks" is *not* in this module (it's not the DTD's rule) — it lives in canonical's entry template and load-init.

Derived editability rule: an element is a **text host** (contenteditable) iff `cm:inline-only` it, or `cm:flow` with no block children; a flow element with block children and all `cm:structural` elements are **containers** (not editable, recursed into). `blockquote` is always a container.

## Phase 1 — foundation

### 1. `src/content-model.xsl` (new)
As above. Wire `<xsl:include href="content-model.xsl"/>` into `src/index.xsl` before line 29 (`canonical-xhtml.xsl`). **Do this first and `make sef`** — validates SaxonJS global-var map init early.

### 2. `src/canonical-xhtml.xsl` — two-pass pipeline
Pass order matters: nesting analysis must never see chrome (fixture 09 has a chrome span as a direct `ol` child).

- **Pass 1 = existing `mode="canonical"`** with changes:
  - **C7a** (replaces C7): `div[no RDFa][empty(*[cm:block(local-name(.))])]` → `p` (fixture 04 unaffected); **C7b**: attributeless div *with* block children → unwrap to children.
  - **C11** (new, priority 1): `p[contains-token(@class,'rdfa-editor-run')][no RDFa]` → unwrap (RDFa-annotated wrapper stays a real `p`).
  - **C12** (new): `section|article|main|aside|header|footer|nav|hgroup` without RDFa → unwrap; RDFa-bearing pass through (lint flags them).
- **Pass 2 = new `mode="cm-normalize"`** (`on-no-match="shallow-copy"`), applied bottom-up (children processed first, then coerced):
  - **N0** (priority 2): `*[@data-role]` deep pass-through (load-init runs pass 2 alone on host content).
  - **N1**: blocks inside `cm:inline-only` parents — parent has RDFa → keep parent, demote block children to `span` (all attrs kept: triples unchanged); no RDFa → split parent around block groups (shell copies name + `@lang`), drop empty halves.
  - **N2**: `blockquote` — stray text/inline runs wrapped in `p` (via shared `cm:wrap-inline-runs`).
  - **N3/N4/N5**: `ul|ol` non-`li` runs → wrap in `li`; `dl` strays → `dd`; `tr` strays → `td` (sections: → `tr`).
  - **N6**: `table` invalid children hoisted before the table (mirrors browser fostering).
  - **N7**: `big|small|sub|sup` in `pre` unwrap; `img|object` in `pre` → `@alt` text/dropped.
  - **N8**: `a[ancestor::a]` → rename to `span`, all attrs kept.
- **Entry coercion** (editor contract): region children processed then `cm:wrap-inline-runs(…, 'p')` — stray top-level inline runs become paragraphs.
- Shared helpers in this module: `cm:normalize($nodes)`, `cm:wrap-inline-runs($kids, $wrapper)` (`for-each-group group-adjacent="boolean(self::*[cm:block(local-name(.)) or @data-role])"` — the generalization of paste's grouping at `edit.xsl:883–897`).
- Header note: "not standalone-compilable — include alongside content-model.xsl".

### 3. Test wiring
- New `tests/canonical-driver.xsl` (mirrors `lint-driver.xsl`): imports `../src/content-model.xsl` + `../src/canonical-xhtml.xsl`. Switch `tests/run-tests.sh:51` to `-xsl:tests/canonical-driver.xsl`.
- `tests/normalize-xhtml.xsl:19–21`: add `blockquote`, `dl`, `colgroup` to the element-only whitespace-drop parent list (NOT `li`/`td` — mixed content significant there).

### 4. `src/lint-xhtml.xsl` (new, pure)
Sibling of `lint-rdfa.xsl` (depends on `content-model.xsl` only — verdicts can't drift from normalization). `lint:nesting-issues($element)`: **invalid-nesting** (child not allowed under known parent; skip region root), **stray-text** (non-ws text in `cm:structural` container), **prohibited-nesting** (Appendix B ancestor), **unknown-element**. Paths via existing `lint:path`. Wire: `navigate.xsl:444/:447/:464` and `tests/lint-driver.xsl:20` change `lint:element-issues(.)` → `(lint:element-issues(.), lint:nesting-issues(.))`; add imports/includes (`index.xsl` + driver).

### 5. `src/edit.xsl` — recursive init + load normalization
- Rewrite `local:init-block` (`:251–268`): text host → set contenteditable; container → if `cm:flow`, wrap stray runs (`local:wrap-stray-runs`, new: live-DOM run wrapping with counted `appendChild` moves, marker class `rdfa-editor-run`); empty `blockquote` gets an editable `p`+`br`; recurse into non-inline known children (skip `@data-role`); `img` tabindex as today; **chrome only when `parent::*[contains-token(@class,'rdfa-editor-content')]`**.
- Load-init in `local:init-editing` (`:243–247`): per region, cheap probe (`exists($region//*[not(cm:valid-nesting(.))])` or stray-text/region-stray-inline) → only then rebuild children via `cm:normalize` + `cm:wrap-inline-runs` and write back with `serialize(…, map{'method':'html'})`. No undo push (precedes user actions).
- `local:ensure-placeholder` (`:116`): add `and cm:allows-child(local-name($host), 'br')` guard (blockquote containers must never get a bare `br`).
- CSS: `rdfa-editor.css` add `.rdfa-editor-content p.rdfa-editor-run { margin: 0; }`.
- **`serialize`→`innerHTML` hazard**: change `:912`/`:945` to `map{'method':'html'}` (XML self-closing `<p/>` breaks the HTML fragment parser).

### 6. Phase 1 validity stopgap (editor gestures must not produce invalid markup)
- `local:split-block` (`:701`): chrome condition `not($host/self::li)` → parent-is-region.
- `local:insert-empty-paragraph` (`:669`): same guard around `inject-chrome`.
- Backspace B2 (`:748`): drop `self::blockquote` from direct-merge list; `$prev[self::blockquote]` → merge into `($prev/descendant::*[@contenteditable='true'])[last()]`.
- Block-type convert (`:977–1029`): to-`blockquote` = **wrap** current text block (blockquote gains chrome, block loses it, no contenteditable on wrapper); from-`blockquote` with single text-block child = unwrap+rename; multi-child → `local:show-flash` no-op. Guard for-each against containers.

### 7. Paste rewrite (`:858–961`)
- `$clean` := pass 1 + pass 2. Delete `$local:block-names` (`:804`); `$has-blocks := exists($clean/*[cm:block(local-name(.))])`.
- Replace the `:874` flatten branch with a cm-driven cascade: (a) **flow host** (li/td/th/dd/figcaption) + blocks → insert *inside* the host: new child sequence = wrapped pre-caret run, pasted blocks, wrapped tail run; write back (`method:'html'`), drop host contenteditable, re-run `local:init-block($host)`; caret to last pasted block's last host. (b) **inline-only host** (p/h1–h3) → existing split-and-thread `:907–926` (valid at any depth now); belt-and-braces `cm:allows-child` check on the parent, else (c). (c) **neither placeable** (`caption`/`dt`) → flatten to text (derived, not hard-coded).
- Delegate `:883–897` grouping to `cm:wrap-inline-runs`.

### 8. Phase 1 tests
- Canonical fixtures (`tests/fixtures/canonical/` + expected): `13-blockquote-block-only` (runs wrapped, RDFa preserved, valid untouched), `14-nested-lists-roundtrip` (**byte-identical round-trip of mixed li — the acceptance test**), `15-cell-flow-roundtrip` (td > p+ul+blockquote, nested table), `16-inline-only-hoist` (p>ul split; RDFa-p demotes child to span), `17-list-dl-child-normalization`, `18-run-wrapper-unwrap`, `19-region-stray-inline` (+ C12), `20-prohibitions` (a-in-a, pre exclusions, table hoist). Update `expected/canonical/09`: `<blockquote>Quote.</blockquote>` → `<blockquote><p>Quote.</p></blockquote>`.
- Lint fixtures: `11-invalid-nesting` (one issue per check), `12-valid-nesting-clean` (deep valid nesting → empty output).
- Browser `tests/browser/nesting.mjs` (+ register in `run.mjs`): recursive init shape, run-wrapper + view-source round-trip, typing/Enter/Backspace in `blockquote > p`, paste blocks into `li` nests, load normalization + lint badge, undo across nested edit. Migrate the four suites targeting `#content > blockquote` as text host (`features.mjs:74`, `hardening.mjs:139–157`, `editor.mjs:262`, `tables.mjs:297`).

**Order**: content-model + sef → canonical two-pass + driver + fixtures (headless-green) → lint-xhtml → edit.xsl init/stopgap → paste → browser tests → CLAUDE.md.

## Phase 2 — authoring gestures

### 1. Shared primitives
`local:first-host-in`/`local:last-host-in` (name the existing inline pattern at `:764`/`:929`/`:1117`); `local:collapse-container` (single remaining `p.rdfa-editor-run` → unwrap, restore contenteditable — inverse of wrap-stray-runs); split-block promotion rule (host is run wrapper → strip marker; both halves real `p`s).

### 2. Blockquote surface
Remove `blockquote` from the block-type select (`:295–302`); select reports/converts the **host** (`local:host-of`, not `block-of`) — caret in quote-paragraph shows "Paragraph", converts inner block only; disabled on non-convertible hosts. New **quote toggle button** (`format-quote`, aria-pressed, synced in `local:sync-format-toolbar` `:364–371`): ON = wrap target block where `cm:allows-child(parent, 'blockquote')` (region, td, container li), chrome swap if top-level; OFF = unwrap children out (counted `before` moves), refuse + flash if the blockquote carries RDFa (would drop triples); re-init released children. Replaces the Phase 1 select stopgap.

### 3. Nested lists — Tab/Shift+Tab
Keydown dispatcher before the `:421` Tab branch: `li` context wins over `td` (innermost); `local:item-of($node)` := `ancestor-or-self::li[1]`.
- **Indent**: no previous li → flash no-op. Else: reuse `$prev/*[last()][self::ul or self::ol]` or create list of parent's kind appended to `$prev` (converting `$prev` leaf→container via wrap-stray-runs); `appendChild($target, $li)`; caret capture/restore; undo push first, after-mutation last.
- **Outdent**: top-level list → flash no-op. Else: following siblings become a nested list inside `$li` (standard semantics); `$container/after($li)`; remove empty list; `local:collapse-container($container)`.

### 4. Enter/Backspace (keep lettered-case docs)
- **E4a**: empty last li in a *nested* list → outdent one level (progressive); **E4b**: top-level → existing exit. **E3′**: split of a run wrapper strips the marker.
- **B4**: li merge target → `local:last-host-in(prev li)` (deepest visually-preceding line). **B4b** (new): first li of a nested list → outdent (mirror Shift+Tab); top-level first li stays inert. **B7** (new): first host of a blockquote → move it before the quote (exit upward); remove emptied quote. Generalize B2 into "previous sibling is a container (non-composite) → merge into its last host".

### 5. Tables with flow cells
`local:table-tab`/`local:table-enter`/row-column-op caret landings wrap targets in `first-host-in`/`last-host-in` (`tables.xsl:397–411, :430–435, :453–457, :467–472, :277–282, :314–318, :345–350, :372–377`). Tab in plain cell still traverses; `li`-in-`td` indents. E2b stays keyed on `$host/self::td|th` (Enter in p-inside-cell = paragraph split — document).

### 6. Toolbar state
Quote toggle pressed/disabled logic; block-type select disable outside convertible hosts; list/insert/delete buttons unchanged (delete-block = whole top-level block, status quo).

### 7. Phase 2 tests
`tests/browser/authoring.mjs`: quote wrap/unwrap/RDFa-refusal/inner-convert; Tab indent → `li > ul > li` with run wrapper + conventional canonical form; first-li flash; Shift+Tab with followers demoted; container collapse; progressive Enter outdent then exit; Backspace outdent + quote exit; li-in-td Tab; cell landings; undo/redo per gesture.

**Order**: primitives → Enter/Backspace → indent/outdent → quote toggle + select rework → table landings → toolbar sync → tests → CLAUDE.md.

## CLAUDE.md updates (both phases)
New content-model.xsl bullet (schema transcription, `cm:*` single source of truth, include-free); canonical two-pass + N-rules + editor-contract coercion + canonical-driver note; edit.xsl recursive editability + `rdfa-editor-run` marker contract + cm-driven paste; lint-xhtml checks; overview: blockquote is a container (`blockquote > p+`), nested lists/cell-flow supported; key constraint: `serialize` with `method:'html'` for all `innerHTML` writes. Note the storage-contract change: stored bare-text blockquotes are rewritten to `blockquote > p` once (LDH content audit advised).

## Risks
- Run-wrapper lifecycle is the novel mechanism (find&replace safe — nodeValue rewrite; annotations survive unwrap; undo rides innerHTML). Breadcrumb shows `p` for a wrapper — cosmetic.
- SaxonJS global-var map init unproven in this repo — compile content-model.xsl first.
- Load-init rewrite goes through innerHTML on invalid input — host-page node refs go stale (same as undo restore).

## Verification
- `make sef` after each XSLT step; `make test` (extractor 26 + lint + canonical suites) headless-green before browser work.
- `make test-browser` (existing 4 suites migrated + new `nesting.mjs`, Phase 2 `authoring.mjs`).
- Manual: `make up`, load a fixture page with `<li>text<ul>` mixed items, nested blockquote content, blocks in cells → verify editability shape, view-source round-trip byte-identical, lint badge on injected-invalid markup; author each Phase 2 gesture and undo it.
