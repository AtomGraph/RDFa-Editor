# LinkedDataHub migration: replacing WYMEditor with the RDFa editor

Goal: swap the jQuery/iframe WYMEditor that edits `ldh:XHTML` blocks (stored as
`rdf:XMLLiteral`) for this repo's XSLT/SaxonJS editor, within LDH's existing form
pipeline. All LDH references are to
`LinkedDataHub/src/main/webapp/static/com/atomgraph/linkeddatahub/xsl/bootstrap/2.3.2/`.

## Prerequisites (this repo)

- **M2 multi-instance refactor** — DONE: editable regions are `.rdfa-editor-content`
  containers (any number per page); undo is region-keyed; drops never cross regions;
  ToC/view-source follow the active region; window state is `rdfaEditor*`-prefixed.
- **M4 vocabulary UX (recommended)** — replace the option-list selects with a typeahead
  fed by LDH's ontology endpoint (below); 100+-option selects don't scale to app
  ontologies.

## The replacement contract, step by step

### 1. Form control rendering — `imports/default.xsl:1236-1258`

Today (`bs2:FormControl` for `*[@rdf:parseType = 'Literal']/xhtml:*`):

```xml
<textarea name="ol" id="{$id}" class="wymeditor">{serialize(xhtml:*)}</textarea>
<input type="hidden" name="lt" value="&rdf;XMLLiteral"/>
```

Replacement: render the XMLLiteral's content as an editable container instead of a
serialized string, keeping the RDF/POST inputs:

```xml
<div class="rdfa-editor-content">
    <xsl:copy-of select="xhtml:*/node()" copy-namespaces="no"/>
</div>
<input type="hidden" name="ol" id="{$id}"/>
<input type="hidden" name="lt" value="&rdf;XMLLiteral"/>
```

### 2. Editor instantiation — `client/form.xsl:144-160`

Today: `ldh:RenderRowForm` on `textarea.wymeditor` calls the jQuery plugin
(`iframeBasePath` config, `getWymeditorByTextarea`, iframe height math).

Replacement: an `ldh:RenderRowForm` template on `div.rdfa-editor-content` running the
editor's per-instance init (per-block-kind `contenteditable`, chrome injection) — the
M2 equivalent of `local:init-editing` scoped to this container. **No JS assets**: the
editor is compiled into the client SEF; only `rdfa-editor.css` is needed.

### 3. Submit sync — `ldh:FormPreSubmit` (form.xsl:178-198)

LDH reads `input/textarea` values at submit with no editor sync hook, and
`ldh:parse-rdf-post` (`client/functions.xsl:221-226`) wraps the `ol` value in
`<div xmlns="http://www.w3.org/1999/xhtml">…</div>` for the XMLLiteral. WYMEditor
kept the textarea in sync continuously; the replacement syncs once, declaratively:

```xml
<xsl:template match="div[contains-token(@class, 'rdfa-editor-content')]" mode="ldh:FormPreSubmit">
    <xsl:variable name="canonical" as="node()*">
        <xsl:apply-templates select="node()" mode="canonical"/>
    </xsl:variable>
    <xsl:for-each select="following-sibling::input[@name = 'ol'][1]">
        <ixsl:set-property name="value" select="serialize($canonical, map{ 'method': 'xml' })" object="."/>
    </xsl:for-each>
</xsl:template>
```

Key points: serialize the container's **children only** (no wrapper element —
parse-rdf-post adds the div); `mode="canonical"` guarantees the stored literal is
sanitized and free of editing ephemera (chrome, contenteditable, classes, on*
handlers, unsafe URLs). SaxonJS 3 applies `ixsl:set-property` immediately
(verified in-browser), so the value is readable by `ldh:parse-rdf-post` within
the same submit event.

### 4. Asset loading — `layout.xsl`

- `layout.xsl:342-344` (skin.css) and `:384-386` (jquery.wymeditor.js) are gated on
  `$load-wymeditor` (`:335` authenticated, `:355` not modal). Replace with a single
  `rdfa-editor.css` link under the same conditions.
- After cutover: `js/wymeditor/**` and the jQuery dependency (if nothing else uses it)
  are removable from the war.

### 5. Multiple blocks per page

Each block edits via its own inline form (`client/block.xsl:314-354`; POST for new
blocks with the `rdf:_N` sequence triple, PATCH for updates; re-render through
`ldh:row-form-response`). The editor must therefore initialize per rendered form
(step 2 fires per block) and keep per-instance undo. Concurrent open editors are
possible — nothing may be keyed on singleton ids.

### 6. Vocabularies

Client-side ontology access uses the `/ns` endpoint
(`constructor.xsl:203-209` pattern):
`ac:build-uri(resolve-uri('ns', ldt:base()), map{ 'query': 'DESCRIBE <uri>', 'accept': 'application/rdf+xml' })`,
fetched via `ixsl:http-request` promise chains, with `ixsl:doc-fetched` guards for
documents already in the pool. The editor's annotation UI should source classes and
properties from the app ontology this way (typeahead, M4) instead of its static
`$vocab-hrefs` files.

### 7. i18n

Editor UI strings go into `translations.rdf` (`rdf:nodeID` entries with
`rdfs:label@xml:lang`), retrieved with the standard
`key('resources', 'id', document(resolve-uri('...translations.rdf', lapp:origin())))`
+ `ac:label` pattern (e.g. form.xsl:149).

### 8. Feature flag (decision deferred)

Options, in increasing coupling:
- **`lapp:Application` property** (e.g. `ldh:contentEditor`) — per-app opt-in, queried
  where steps 1/2/4 branch; most LDH-idiomatic.
- **Stylesheet param from a web.xml context-param** — instance-wide switch.
- **Hard cutover** — no flag; delete WYMEditor in the same change.

Whichever is chosen, the branch points are exactly steps 1, 2 and 4 (the textarea
class routing means WYMEditor simply never instantiates when the container renders
instead).

### 9. Build wiring

- LDH compiles `client.xsl` + imports to a single SEF at package time
  (`pom.xml:39, 383-391`: `xslt3-he … -nogo -ns:##html5 -relocate:on`).
- The editor modules (this repo's `src/*.xsl`, minus the demo entry `index.xsl`) are
  copied into the LDH webapp tree at build time (maven-resources / git submodule) and
  `xsl:import`ed from `client.xsl`.
- `rdfa-editor.css` is copied under `static/…/css/`.

### 10. Conflict audit — VERIFIED (compile-proven)

The full integration was proven by compiling LDH's `client.xsl` (from the built
`target/ROOT` tree) with all nine editor modules appended as `xsl:import`s into a
single SEF via `xslt3-he -nogo -ns:##html5 -relocate:on` — no errors, no conflicts.

Audit results:
- Extractor entry is a **named template only** (`extract-rdfa`; the unnamed-mode
  `match="/"` was removed; headless tests invoke with `-it:extract-rdfa`). All other
  editor matching lives in named modes (`rdfa:extract`, `canonical`) or `ixsl:*` event
  modes.
- Event templates: LDH has no `contenteditable` usage and no `body` keydown template
  (only `body` onmousemove in navigation.xsl — different mode). No pattern overlap.
- `drag-handle` class token exists on both sides, but LDH matches `div.drag-handle`
  and the editor `span.drag-handle` — disjoint patterns; both sides' CSS is
  container-scoped (`.row-fluid.block .drag-handle` vs the editor's region scoping).
- No id, window-property, named-template, or mode-name collisions (grep-verified).
  Editor window props are `rdfaEditor*`-prefixed; undo stash ids are
  `rdfa-editor-*`-prefixed; generic UI class selectors (`.btn-*`, `.modal-*`, `.crumb`,
  `.toc-*`, …) are scoped under `.rdfa-editor-ui` so Bootstrap 2.3.2 styling is
  untouched.
- LDH's `base-uri` params are all template-local — no clash with the extractor's
  global `$base-uri`.
- `xsl:output`: resolved by import precedence (client.xsl is the principal module).

Build caveat: `xslt3-he` does not expand DOCTYPE entity declarations when loading
modules — LDH's entity-using stylesheets must be entity-expanded (e.g.
`xmlstarlet c14n`) before the SEF compile, and `xsl:import` hrefs resolve against the
importing file's location (`xml:base` is not honored). The editor modules are
entity-free and import cleanly from any location.

### 11. v6 outlook

LDH v6 makes XHTML+RDFa the canonical document format (no `ldh:XHTML`/XMLLiteral
wrappers): view markup is edited in place and the canonical document is PUT, with RDF
extracted server-side. This form-control integration is the stepping stone: the same
canonicalization/sanitization boundary and the same editing surface carry over; the
XMLLiteral round-trip (steps 1/3) is what falls away.

### 12. Object blocks — the v6 block idiom and the render-hook bridge

The editor's object blocks (src/blocks.xsl) implement the **v6 document format**
([XHTML+RDFa as LDH v6 Document Format](https://github.com/AtomGraph/LinkedDataHub/wiki/XHTML-RDFa-as-LDH-v6-Document-Format)):
blocks are XHTML elements carrying `@about` (a fragment URI — the block is a document
part) and `@typeof` directly, with definition triples as `span[@property]` children
(objects via `@resource`, literals as span *text content*), arbitrarily nestable per
the content model. There are **no wrappers, no `rdf:_N` sequences, no
document→block containment edges** — the document owns its blocks implicitly through
its content, and `ldh:content` remains the document→body XMLLiteral property, never a
per-block edge. The v5 block model (`ldh:XHTML`, `ldh:Object` indirection, flat
sequences, row scaffolding, per-block CRUD SPARQL) is obsolete by the format itself;
what the editor adds on top is the *editing* semantics (atomic islands) and the
*rendering* seam.

The v5 `ldh:Object` use case — embed an *existing* resource — needs no node at all
in v6: a **reference block** is an empty `div` whose `@about` is the referenced
resource's own absolute URI (`<div about="http://dbpedia.org/resource/Ada_Lovelace"></div>`).
Placement is carried by the XHTML structure, the reference by the name itself; the
RDFa extraction of an empty `div[@about]` is zero triples, so no scaffolding enters
the content graph. The fragment rule disambiguates for free: fragment `@about` =
document part (a defined block or annotated content), absolute non-document `@about`
on an effectively-empty div = dereference and render (`local:reference-block` in
src/blocks.xsl). What the wrapper used to pay for — per-embedding metadata such as
`ac:mode` — has no subject in this idiom; if per-embed rendering modes return, they
need a typed block again.

That stored shape is **the same shape LDH's renderers already match**: e.g. the v5
chart entry (`client/block/chart.xsl:259`) matches
`*[@typeof = ('&ldh;ResultSetChart', …)][descendant::*[@property = '&spin;query'][@resource]]…`
and reads `spin:query`/`ldh:chartType`/`ldh:categoryVarName` off descendant
`@property` elements — and the v6 rendering mode `ldh:Block` is defined exactly as
"match `@typeof`, read properties from `@property` descendants". So the bridge is
thin: client.xsl plays the extension role that src/ldh-blocks.xsl plays in the
standalone demo — it re-declares the island class list and, per type, hands the
island to its block-rendering machinery (`ldh:Block` in v6; the v5 `ldh:RenderRow`
example below works the same way) with the ephemeral rendering div as the container:

```xml
<!-- client.xsl (imports the editor modules, higher import precedence) -->
<xsl:param name="object-block-types" as="xs:string*"
    select="('&ldh;View', '&ldh;ResultSetChart', '&ldh;GraphChart')"/>
<!-- reference blocks (embed-by-URI) need no param entry: local:reference-block
     recognizes them structurally; client.xsl renders them by dereferencing
     @about into its resource-rendering machinery -->


<xsl:template match="div[tokenize(@typeof) = ('&ldh;ResultSetChart', '&ldh;GraphChart')]"
        mode="local:render-island">
    <xsl:variable name="island" as="element()" select="."/>
    <!-- the container ldh:RenderRow renders into: the ephemeral rendering div
         (canonicalization-stripped, extractor-skipped). Seed it with the LDH
         progress-bar markup; the thunk chain replaces it with the chart -->
    <xsl:call-template name="local:replace-rendering">
        <xsl:with-param name="island" select="$island"/>
        <xsl:with-param name="content">
            <div class="progress progress-striped active">
                <div class="bar" style="width: 0%;"></div>
            </div>
        </xsl:with-param>
    </xsl:call-template>
    <xsl:variable name="container" as="element()" select="$island/*[@data-role = 'rendering']"/>
    <xsl:for-each select="$container">
        <!-- RenderRow addresses its container by id (canonicalization-stripped) -->
        <ixsl:set-attribute name="id" select="generate-id($island) || '-rendering'"/>
    </xsl:for-each>
    <xsl:apply-templates select="$island" mode="ldh:RenderRow">
        <!-- the island IS the block: no .row-fluid.block scaffolding, the subject
             is the island's own @about (a fragment URI per the v6 format) -->
        <xsl:with-param name="block" select="$island"/>
        <xsl:with-param name="about"
            select="xs:anyURI(resolve-uri($island/@about, ldh:base-uri(ixsl:page())))"/>
        <xsl:with-param name="container" select="$container"/>
    </xsl:apply-templates>
</xsl:template>
```

The existing async pipelines (`ldh:chart-self-thunk` → `ldh:chart-query-thunk` →
`ldh:chart-results-thunk` → Google Charts `draw()`) run unchanged — they are already
container-plus-context-map based, and literal definition values are span text
content per the v6 format, exactly what their selectors read. One caveat: chart
canvases don't survive an `innerHTML` undo restore; the editor re-fires
`local:render-island` only for islands *without* a rendering div, so a
canvas-bearing bridge should also re-draw from the `LinkedDataHub.contents` cache
when its canvas is dead (LDH already does this on mode switches).

What the seam exposes to client.xsl is exactly what v6's `ldh:Block` mode needs: the
per-type match shapes (`@typeof` + `@property` descendants, already RDFa-driven) and
the thunk pipelines behind them; everything the v6 format removed (`rdf:_N`
ordering/renumbering SPARQL, `ldh:XHTML`/`ldh:Object` wrappers, row scaffolding,
per-block CRUD chrome) is likewise absent from the editor's side of the contract —
ordering is document order, reorder/delete/undo are editor gestures, persistence is
the one document PATCH.
