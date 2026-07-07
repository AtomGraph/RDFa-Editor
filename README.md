# RDFa-Editor

A declarative **XHTML+RDFa authoring tool** running entirely on client-side XSLT 3.0
([SaxonJS 3](https://www.saxonica.com/saxon-js/index.xml) with the `ixsl:` interactive
extensions). No JavaScript application code — the editor UI, the editing behavior, the
RDFa extraction and the document canonicalization are all XSLT.

- **Structured-block editing** of any number of `.rdfa-editor-content` regions (p, h1–h3, lists, blockquote,
  pre, figure): Enter splits, Backspace merges, toolbar for block types / inline
  formatting / links / figures, drag-handle and Alt+Arrow reordering, HTML paste through
  a sanitizing canonicalization pipeline, unified snapshot undo/redo with caret
  restoration.
- **RDFa annotation**: right-click a selection to assert a statement (S/P/O framing,
  vocabulary dropdowns fed by plain ontology RDF/XML files); right-click an annotation
  to edit or remove it.
- **Strictly W3C-conformant RDFa 1.1 extraction** to RDF/XML ("Extract RDF"), a
  **canonical serialization** stripping all editing ephemera ("Source"), and
  **RDFa lint** (unresolvable terms, unsafe markup, step-11 conflicts) surfaced as
  wavy underlines + a breadcrumb badge.
- **Navigation**: ToC drawer (outline with section drag-reorder), breadcrumb bar with
  the RDFa subject in scope at the caret, find & replace.

## Run

```bash
make up                         # build the SEF, then serve on http://localhost:8000
# open http://localhost:8000/index.html — override the port with: make up PORT=9000
```

`make up` runs `make sef` first (compile `src/*.xsl` → `dist/index.xsl.sef.json`, needs
xmlstarlet + npx), then serves the repo with `python3 -m http.server`. Run `make sef`
alone to rebuild the SEF without serving.

## Test

```bash
make test                       # headless XSLT suites: extractor, canonicalization, lint fixtures
make install                    # install Node dependencies (Playwright) for the browser tests
make test-browser               # Playwright suites (rebuilds the SEF, serves the repo itself)
```

## Architecture

See `CLAUDE.md` for the module map and conventions. The load-bearing pieces:
`src/RDFa2RDFXML-v3.xsl` (RDFa 1.1 → RDF/XML, pure XSLT, headless-tested),
`src/canonical-xhtml.xsl` (canonical + sanitized serialization form, pure XSLT),
`src/lint-rdfa.xsl` (pure), and the IXSL modules `edit.xsl` / `annotate.xsl` /
`overlay.xsl` / `navigate.xsl` / `undo.xsl` / `vocab.xsl`. The editor's stylesheet is
self-contained: a host page provides one or more `.rdfa-editor-content` regions, `rdfa-editor.css`, and
preloads the vocabulary documents into the SaxonJS document pool (see `index.html`).

## Embedding in LinkedDataHub

The plan for replacing LinkedDataHub's WYMEditor with this editor lives in
[`ldh/MIGRATION.md`](ldh/MIGRATION.md). The overall roadmap is in
[`ROADMAP.md`](ROADMAP.md).
