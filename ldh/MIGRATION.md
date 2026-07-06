# LinkedDataHub migration: replacing WYMEditor with the RDFa editor

Goal: swap the jQuery/iframe WYMEditor that edits `ldh:XHTML` blocks (stored as
`rdf:XMLLiteral`) for this repo's XSLT/SaxonJS editor, within LDH's existing form
pipeline. All LDH references are to
`LinkedDataHub/src/main/webapp/static/com/atomgraph/linkeddatahub/xsl/bootstrap/2.3.2/`.

## Prerequisites (this repo)

- **M2 multi-instance refactor** — LDH pages edit many XHTML blocks; the editor
  currently assumes a single `id('content')` root (`local:content()`, undo snapshots,
  lint/ToC scoping). Editable roots must be resolved per instance (container class
  convention), with per-instance undo stacks.
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
handlers, unsafe URLs).

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

### 10. Conflict audit checklist (before the first compile)

- The extractor's unnamed-mode `match="/"` (`extract-rdfa`) vs LDH's root templates —
  move the editor's entry behind a named/mode-scoped entry only.
- `xsl:output` declarations (LDH's principal output wins with `xsl:import` —
  verify; the extractor's `indent="yes"` must not leak).
- Event-template overlap: one template per mode per element — audit LDH's existing
  `ixsl:onkeydown`/`onclick`/`onmousedown`/drag handlers against the editor's host-level
  (`*[@contenteditable='true']`) and `body` templates.
- `id('content')` and other singleton assumptions (removed by M2).
- Window-property names (`activeBlock`, `undoStack` stash ids, …) — prefix them
  (`rdfaEditor*`) to avoid collisions.
- `$base-uri` and other global params — declared once across the merged tree.

### 11. v6 outlook

LDH v6 makes XHTML+RDFa the canonical document format (no `ldh:XHTML`/XMLLiteral
wrappers): view markup is edited in place and the canonical document is PUT, with RDF
extracted server-side. This form-control integration is the stepping stone: the same
canonicalization/sanitization boundary and the same editing surface carry over; the
XMLLiteral round-trip (steps 1/3) is what falls away.
