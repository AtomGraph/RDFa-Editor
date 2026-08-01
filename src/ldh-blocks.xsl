<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xsl:stylesheet [
    <!ENTITY ldh    "https://w3id.org/atomgraph/linkeddatahub#">
    <!ENTITY ac     "https://w3id.org/atomgraph/client#">
    <!ENTITY rdf    "http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <!ENTITY spin   "http://spinrdf.org/spin#">
]>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:rdfae="https://w3id.org/atomgraph/rdfa-editor#"
xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
xmlns:sp="http://spinrdf.org/sp#"
xmlns:srx="http://www.w3.org/2005/sparql-results#"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    LinkedDataHub blocks extension: makes ldh:View / ldh:ResultSetChart
    placeholders and reference blocks (an empty div naming an external
    resource by its absolute @about URI - the v6 replacement for the obsolete
    ldh:Object + rdf:value indirection) first-class island blocks. Included by
    the ldh-editor.xsl entry at HIGHER import precedence than the core (which
    it xsl:imports), so the declarations here override the core's:

    - $object-block-types is re-declared with the LDH class IRIs;
    - per-type mode="rdfae:render-island" templates (plus one matching
      rdfae:reference-block) replace the neutral card with real async
      hydration via the SaxonJS 3 promise API (ixsl:promise +
      ixsl:http-request => ixsl:then, LDH's ldh:*-thunk idiom). Document URIs
      follow the Linked Data convention: trailing slash, no file extensions,
      representations chosen by CONTENT NEGOTIATION on the clean URI -
      Accept: application/rdf+xml for the description, and (demo stand-in for
      live SPARQL execution) Accept: application/sparql-results+xml for canned
      results of a query document (serve.mjs / tests/browser/run.mjs negotiate;
      a reference block dereferences ANY absolute URI the same way - e.g. a
      DBpedia resource, whose server 303-redirects to the RDF/XML data and
      allows CORS). In production, LinkedDataHub's client.xsl plays this
      module's role, bridging into its block rendering - v6 mode ldh:Block,
      v5 ldh:RenderRow (docs/ldh/MIGRATION.md par. 12);
    - the "Block..." insert dialog plugs into the core's extension hooks
      (rdfae:render-extra-dialogs / -insert-buttons / -slash-items /
      rdfae:run-extra-slash-command).

    Relative @resource IRIs resolve against the page base (rdfae:document-uri),
    matching the RDFa extractor's resolution - never against the SEF location.
    Reference blocks carry ABSOLUTE @about URIs by construction (the editor
    emits absolute IRIs; a relative @about is the about-relative lint case).
-->

    <xsl:param name="object-block-types" as="xs:string*" select="(
        '&ldh;View',
        '&ldh;ResultSetChart')"/>

    <!-- ................................ renderers ................................ -->

    <!-- ldh:View / ldh:ResultSetChart: fetch the spin:query resource, then the
         canned results; a chart also captions itself from its own definition
         spans. Placeholders missing the spin:query span fall through to the
         core's neutral card (deep-skip backstop) -->
    <xsl:template match="div[tokenize(@typeof) = ('&ldh;View', '&ldh;ResultSetChart')]
            [descendant::*[@property = '&spin;query'][@resource]]" mode="rdfae:render-island">
        <xsl:variable name="chart-type" as="xs:string?"
            select="(descendant::*[@property = '&ldh;chartType']/@resource)[1] ! string(.)"/>
        <xsl:variable name="category" as="xs:string?"
            select="(descendant::*[@property = '&ldh;categoryVarName']/(@content, text())[1])[1] ! string(.)"/>
        <xsl:variable name="series" as="xs:string*"
            select="descendant::*[@property = '&ldh;seriesVarName']/(@content, text())[1] ! string(.)"/>
        <xsl:variable name="heading" as="xs:string" select="string-join((
            $chart-type ! replace(., '^.*[#/]', ''),
            string-join(($category[. ne ''], string-join($series[. ne ''], ', ')[. ne '']), ' &#xD7; ')[. ne '']
            ), ' &#xB7; ')"/>
        <xsl:call-template name="rdfae:load-query-block">
            <xsl:with-param name="island" select="."/>
            <xsl:with-param name="heading" select="$heading"/>
        </xsl:call-template>
    </xsl:template>

    <!-- reference block: dereference the @about URI (conneg on the clean URI;
         absolute by the rdfae:reference-block predicate) and render the
         resource's description as a property table -->
    <xsl:template match="div[rdfae:reference-block(.)]" mode="rdfae:render-island">
        <xsl:variable name="island" as="element()" select="."/>
        <xsl:variable name="value-uri" as="xs:string" select="normalize-space(@about)"/>
        <xsl:variable name="value-doc" as="xs:string" select="substring-before($value-uri || '#', '#')"/>
        <xsl:sequence select="ixsl:call(ixsl:get($island, 'classList'), 'add', [ 'rdfa-editor-loading' ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:promise select="
            ixsl:http-request(map{ 'method': 'GET', 'href': $value-doc,
                'headers': map{ 'Accept': 'application/rdf+xml' } }) =>
                ixsl:then(rdfae:block-reference-response($island, $value-uri, $value-doc, ?))"
            on-failure="rdfae:block-render-failure($island, ?)"/>
    </xsl:template>

    <!-- shared query-block flow: promise chain fetching the query document,
         then (in its callback) the results document. The rendering div is
         injected only in the final callback, per the render-hook contract -->
    <xsl:template name="rdfae:load-query-block">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="heading" as="xs:string?"/>
        <xsl:variable name="query-uri" as="xs:string" select="string(resolve-uri(
            string(($island/descendant::*[@property = '&spin;query']/@resource)[1]), rdfae:document-uri()))"/>
        <xsl:variable name="query-doc" as="xs:string" select="substring-before($query-uri || '#', '#')"/>
        <xsl:sequence select="ixsl:call(ixsl:get($island, 'classList'), 'add', [ 'rdfa-editor-loading' ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:promise select="
            ixsl:http-request(map{ 'method': 'GET', 'href': $query-doc,
                'headers': map{ 'Accept': 'application/rdf+xml' } }) =>
                ixsl:then(rdfae:block-query-response($island, $query-uri, $heading, ?))"
            on-failure="rdfae:block-render-failure($island, ?)"/>
    </xsl:template>

    <!-- first hop: the query document (Accept: application/rdf+xml). Pulls
         sp:text (and rdfs:label as the fallback heading), then fires the
         results fetch - the SAME clean URI, negotiated for SPARQL results -->
    <xsl:function name="rdfae:block-query-response" as="item()*" ixsl:updating="yes">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="query-uri" as="xs:string"/>
        <xsl:param name="heading" as="xs:string?"/>
        <xsl:param name="response" as="map(*)"/>
        <xsl:variable name="body" as="document-node()?" select="$response?body[. instance of document-node()]"/>
        <xsl:variable name="query-doc" as="xs:string" select="substring-before($query-uri || '#', '#')"/>
        <xsl:choose>
            <xsl:when test="$response?status = 200 and exists($body)">
                <!-- relative rdf:about values resolve against the document URI
                     (the request URI), per RDF/XML base semantics -->
                <xsl:variable name="query" as="element()?"
                    select="($body//*[@rdf:about][string(resolve-uri(@rdf:about, $query-doc)) = $query-uri],
                        $body//*[sp:text])[1]"/>
                <xsl:variable name="query-text" as="xs:string?" select="($query/sp:text)[1] ! string(.)"/>
                <xsl:variable name="final-heading" as="xs:string?"
                    select="($heading[. ne ''], ($query/rdfs:label)[1] ! string(.))[1]"/>
                <ixsl:promise select="
                    ixsl:http-request(map{ 'method': 'GET', 'href': $query-doc,
                        'headers': map{ 'Accept': 'application/sparql-results+xml' } }) =>
                        ixsl:then(rdfae:block-results-response($island, $final-heading, $query-text, ?))"
                    on-failure="rdfae:block-render-failure($island, ?)"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="rdfae:block-render-error">
                    <xsl:with-param name="island" select="$island"/>
                    <xsl:with-param name="message" select="'Failed to load the query (' || $query-uri || ')'
                        || rdfae:conneg-hint($response)"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!-- a 200 with the wrong representation means the server ignored the Accept
         header: the demo needs the content-negotiating dev server (make up) -->
    <xsl:function name="rdfae:conneg-hint" as="xs:string">
        <xsl:param name="response" as="map(*)"/>
        <xsl:sequence select="(' - the server did not content-negotiate the representation; serve with ''make up'' (serve.mjs)'[$response?status = 200], '')[1]"/>
    </xsl:function>

    <!-- second hop: the SPARQL Results XML document, rendered as a real table -->
    <xsl:function name="rdfae:block-results-response" as="item()*" ixsl:updating="yes">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="heading" as="xs:string?"/>
        <xsl:param name="query-text" as="xs:string?"/>
        <xsl:param name="response" as="map(*)"/>
        <xsl:variable name="results" as="document-node()?" select="$response?body[. instance of document-node()]"/>
        <xsl:choose>
            <xsl:when test="$response?status = 200 and exists($results/srx:sparql)">
                <xsl:variable name="vars" as="xs:string*" select="$results/srx:sparql/srx:head/srx:variable/@name ! string(.)"/>
                <xsl:sequence select="ixsl:call(ixsl:get($island, 'classList'), 'remove', [ 'rdfa-editor-loading' ])[current-date() lt xs:date('2000-01-01')]"/>
                <xsl:call-template name="rdfae:replace-rendering">
                    <xsl:with-param name="island" select="$island"/>
                    <xsl:with-param name="content">
                        <div class="rdfa-editor-island-card">
                            <xsl:for-each select="$heading[. ne '']">
                                <strong><xsl:value-of select="."/></strong>
                            </xsl:for-each>
                            <xsl:for-each select="$query-text[. ne '']">
                                <pre class="rdfa-editor-island-query"><xsl:value-of select="."/></pre>
                            </xsl:for-each>
                            <table>
                                <thead>
                                    <tr>
                                        <xsl:for-each select="$vars">
                                            <th><xsl:value-of select="."/></th>
                                        </xsl:for-each>
                                    </tr>
                                </thead>
                                <tbody>
                                    <xsl:for-each select="$results/srx:sparql/srx:results/srx:result">
                                        <xsl:variable name="result" as="element()" select="."/>
                                        <tr>
                                            <xsl:for-each select="$vars">
                                                <xsl:variable name="var" as="xs:string" select="."/>
                                                <td><xsl:value-of select="$result/srx:binding[@name = $var]/(srx:uri, srx:literal, srx:bnode)[1]"/></td>
                                            </xsl:for-each>
                                        </tr>
                                    </xsl:for-each>
                                </tbody>
                            </table>
                        </div>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="rdfae:block-render-error">
                    <xsl:with-param name="island" select="$island"/>
                    <xsl:with-param name="message" select="'Failed to load results (' || string($response?status) || ')'
                        || rdfae:conneg-hint($response)"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!-- reference hop: the dereferenced resource's description as a property
         table, capped - a public resource (DBpedia) can carry hundreds of
         properties, the card is a preview, not a browser -->
    <xsl:function name="rdfae:block-reference-response" as="item()*" ixsl:updating="yes">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="value-uri" as="xs:string"/>
        <xsl:param name="value-doc" as="xs:string"/>
        <xsl:param name="response" as="map(*)"/>
        <xsl:variable name="body" as="document-node()?" select="$response?body[. instance of document-node()]"/>
        <xsl:variable name="description" as="element()?"
            select="($body//*[@rdf:about][string(resolve-uri(@rdf:about, $value-doc)) = $value-uri],
                $body/rdf:RDF/*)[1]"/>
        <xsl:choose>
            <xsl:when test="$response?status = 200 and exists($description)">
                <xsl:sequence select="ixsl:call(ixsl:get($island, 'classList'), 'remove', [ 'rdfa-editor-loading' ])[current-date() lt xs:date('2000-01-01')]"/>
                <xsl:variable name="label" as="xs:string?"
                    select="(($description/rdfs:label[not(@xml:lang)], $description/rdfs:label[@xml:lang = 'en'], $description/rdfs:label)[1]) ! string(.)"/>
                <xsl:call-template name="rdfae:replace-rendering">
                    <xsl:with-param name="island" select="$island"/>
                    <xsl:with-param name="content">
                        <div class="rdfa-editor-island-card">
                            <strong><xsl:value-of select="($label, $value-uri)[1]"/></strong>
                            <table>
                                <tbody>
                                    <xsl:for-each select="$description/*[position() le 10]">
                                        <tr>
                                            <th><xsl:value-of select="local-name()"/></th>
                                            <td><xsl:value-of select="(string(@rdf:resource)[. ne ''], string(.))[1]"/></td>
                                        </tr>
                                    </xsl:for-each>
                                </tbody>
                            </table>
                            <xsl:for-each select="$description/*[11]">
                                <code><xsl:value-of select="$value-uri"/></code>
                            </xsl:for-each>
                        </div>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="rdfae:block-render-error">
                    <xsl:with-param name="island" select="$island"/>
                    <xsl:with-param name="message" select="'Failed to load the resource (' || $value-uri || ')'
                        || rdfae:conneg-hint($response)"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!-- a failed fetch must never wedge the loading state -->
    <xsl:template name="rdfae:block-render-error">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="message" as="xs:string"/>
        <xsl:sequence select="ixsl:call(ixsl:get($island, 'classList'), 'remove', [ 'rdfa-editor-loading' ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:call-template name="rdfae:replace-rendering">
            <xsl:with-param name="island" select="$island"/>
            <xsl:with-param name="content">
                <div class="rdfa-editor-island-error"><xsl:value-of select="$message"/></div>
            </xsl:with-param>
        </xsl:call-template>
    </xsl:template>

    <xsl:function name="rdfae:block-render-failure" as="item()*" ixsl:updating="yes">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="error" as="item()?"/>
        <xsl:call-template name="rdfae:block-render-error">
            <xsl:with-param name="island" select="$island"/>
            <xsl:with-param name="message" select="'Failed to load block data'"/>
        </xsl:call-template>
    </xsl:function>

    <!-- ................................ insert dialog ................................ -->

    <xsl:template name="rdfae:render-extra-dialogs">
        <div id="ldh-block-dialog" class="rdfa-editor-ui edit-dialog" role="dialog" aria-modal="true"
                aria-label="Insert block" style="display: none;">
            <label>Block type</label>
            <select name="block-type-iri">
                <option value="https://w3id.org/atomgraph/rdfa-editor#reference">Resource</option>
                <option value="&ldh;View">View</option>
                <option value="&ldh;ResultSetChart">Result set chart</option>
            </select>
            <!-- a reference block IS the referenced resource: its absolute URI
                 goes straight into @about, no fragment id and no wrapper node -->
            <div class="ldh-fields ldh-fields-reference">
                <label>Resource URI</label>
                <input type="text" name="reference-uri" placeholder="http://dbpedia.org/resource/Ada_Lovelace"/>
            </div>
            <!-- defined blocks are document parts: fragment @about + @typeof -->
            <div class="ldh-fields ldh-fields-frag" style="display: none;">
                <label>Fragment id</label>
                <input type="text" name="about" placeholder="#chart-1"/>
            </div>
            <div class="ldh-fields ldh-fields-view" style="display: none;">
                <label>Query URI</label>
                <input type="text" name="view-query"/>
                <label>Mode URI (optional)</label>
                <input type="text" name="view-mode"/>
            </div>
            <div class="ldh-fields ldh-fields-chart" style="display: none;">
                <label>Query URI</label>
                <input type="text" name="chart-query"/>
                <label>Chart type</label>
                <select name="chart-type">
                    <option value="&ac;Table">Table</option>
                    <option value="&ac;BarChart">Bar chart</option>
                    <option value="&ac;LineChart">Line chart</option>
                    <option value="&ac;ScatterChart">Scatter chart</option>
                </select>
                <label>Category variable</label>
                <input type="text" name="chart-category"/>
                <label>Series variable</label>
                <input type="text" name="chart-series"/>
            </div>
            <div class="action-buttons">
                <button type="button" class="btn-primary ldh-block-save">Insert</button>
                <button type="button" class="btn-secondary ldh-block-cancel">Cancel</button>
            </div>
        </div>
    </xsl:template>

    <xsl:template name="rdfae:render-extra-insert-buttons">
        <button type="button" class="insert-ldh-block" title="Insert block" aria-label="Insert LinkedDataHub block">&#x25A6;</button>
    </xsl:template>

    <xsl:template name="rdfae:render-extra-slash-items">
        <li class="slash-item" data-command="ldh-block" role="option">Block&#x2026;</li>
    </xsl:template>

    <!-- reset to the reference defaults (mirrors the figure/table openers) -->
    <xsl:template name="rdfae:reset-ldh-block-dialog">
        <xsl:variable name="dialog" as="element()" select="id('ldh-block-dialog', ixsl:page())"/>
        <xsl:for-each select="$dialog//input">
            <ixsl:set-property name="value" select="''" object="."/>
        </xsl:for-each>
        <xsl:for-each select="($dialog//select[@name = 'block-type-iri'])[1]">
            <ixsl:set-property name="value" select="'https://w3id.org/atomgraph/rdfa-editor#reference'" object="."/>
        </xsl:for-each>
        <xsl:call-template name="rdfae:toggle-ldh-block-fields">
            <xsl:with-param name="dialog" select="$dialog"/>
            <xsl:with-param name="type" select="'https://w3id.org/atomgraph/rdfa-editor#reference'"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="rdfae:toggle-ldh-block-fields">
        <xsl:param name="dialog" as="element()"/>
        <xsl:param name="type" as="xs:string"/>
        <xsl:for-each select="$dialog//div[contains-token(@class, 'ldh-fields-reference')]">
            <ixsl:set-style name="display" select="if ($type = 'https://w3id.org/atomgraph/rdfa-editor#reference') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="$dialog//div[contains-token(@class, 'ldh-fields-frag')]">
            <ixsl:set-style name="display" select="if ($type = 'https://w3id.org/atomgraph/rdfa-editor#reference') then 'none' else 'block'"/>
        </xsl:for-each>
        <xsl:for-each select="$dialog//div[contains-token(@class, 'ldh-fields-view')]">
            <ixsl:set-style name="display" select="if ($type = '&ldh;View') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="$dialog//div[contains-token(@class, 'ldh-fields-chart')]">
            <ixsl:set-style name="display" select="if ($type = '&ldh;ResultSetChart') then 'block' else 'none'"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="div[@id = 'ldh-block-dialog']//select[@name = 'block-type-iri']" mode="ixsl:onchange">
        <xsl:call-template name="rdfae:toggle-ldh-block-fields">
            <xsl:with-param name="dialog" select="ancestor::div[@id = 'ldh-block-dialog']"/>
            <xsl:with-param name="type" select="string(ixsl:get(., 'value'))"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'insert-ldh-block')]" mode="ixsl:onclick">
        <ixsl:set-property name="insertHost"
            select="rdfae:current-host()[exists(rdfae:block-of(.))]" object="rdfae:editor-state()"/>
        <xsl:call-template name="rdfae:reset-ldh-block-dialog"/>
        <xsl:call-template name="rdfae:show-at">
            <xsl:with-param name="element" select="id('ldh-block-dialog', ixsl:page())"/>
            <xsl:with-param name="event" select="ixsl:event()"/>
        </xsl:call-template>
        <xsl:for-each select="(id('ldh-block-dialog', ixsl:page())//input[@name = 'reference-uri'])[1]">
            <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="rdfae:run-extra-slash-command">
        <xsl:param name="command" as="xs:string"/>
        <xsl:param name="host" as="element()?"/>
        <xsl:if test="$command = 'ldh-block'">
            <ixsl:set-property name="insertHost" select="$host" object="rdfae:editor-state()"/>
            <xsl:variable name="dialog" as="element()" select="id('ldh-block-dialog', ixsl:page())"/>
            <xsl:call-template name="rdfae:reset-ldh-block-dialog"/>
            <xsl:call-template name="rdfae:show-at-element">
                <xsl:with-param name="element" select="$dialog"/>
                <xsl:with-param name="anchor" select="$host"/>
            </xsl:call-template>
            <xsl:for-each select="($dialog//input[@name = 'reference-uri'])[1]">
                <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:for-each>
        </xsl:if>
    </xsl:template>

    <!-- a definition span: RDFa as real DOM attributes (they must serialize);
         literal values go in TEXT CONTENT per the v6 document format (the spans
         render display:none via rdfa-editor.css) -->
    <xsl:template name="rdfae:make-definition-span">
        <xsl:param name="property" as="xs:string"/>
        <xsl:param name="resource" as="xs:string?" select="()"/>
        <xsl:param name="text" as="xs:string?" select="()"/>
        <xsl:variable name="span" as="element()" select="rdfae:element('span')"/>
        <ixsl:set-attribute name="property" select="$property" object="$span"/>
        <xsl:for-each select="$resource[. ne '']">
            <ixsl:set-attribute name="resource" select="." object="$span"/>
        </xsl:for-each>
        <xsl:for-each select="$text[. ne '']">
            <ixsl:set-property name="textContent" select="." object="$span"/>
        </xsl:for-each>
        <xsl:sequence select="$span"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'ldh-block-save')]" mode="ixsl:onclick">
        <xsl:variable name="dialog" as="element()" select="ancestor::div[@id = 'ldh-block-dialog']"/>
        <xsl:variable name="type" as="xs:string" select="string(ixsl:get(($dialog//select[@name = 'block-type-iri'])[1], 'value'))"/>
        <xsl:variable name="about" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'about'))"/>
        <xsl:variable name="reference-uri" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'reference-uri'))"/>
        <xsl:variable name="view-query" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'view-query'))"/>
        <xsl:variable name="view-mode" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'view-mode'))"/>
        <xsl:variable name="chart-query" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'chart-query'))"/>
        <xsl:variable name="chart-type" as="xs:string" select="string(ixsl:get(($dialog//select[@name = 'chart-type'])[1], 'value'))"/>
        <xsl:variable name="chart-category" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'chart-category'))"/>
        <xsl:variable name="chart-series" as="xs:string" select="normalize-space(rdfae:input-value($dialog, 'chart-series'))"/>
        <xsl:variable name="reference" as="xs:boolean" select="$type = 'https://w3id.org/atomgraph/rdfa-editor#reference'"/>
        <xsl:variable name="valid" as="xs:boolean" select="
            if ($reference) then rdfae:is-absolute-iri($reference-uri)
            else $about ne '' and (
                if ($type = '&ldh;View') then $view-query ne ''
                else $chart-query ne '')"/>
        <xsl:if test="$valid">
            <xsl:call-template name="rdfae:push-undo"/>
            <!-- the v6 block idiom: @about + @typeof directly on the element,
                 definition triples as property spans, fragment @about (the block
                 is a document part); NO containment edge - the document owns its
                 blocks implicitly through its content
                 (XHTML-RDFa-as-LDH-v6-Document-Format). A REFERENCE block inverts
                 the fragment rule: its @about is the referenced resource's own
                 absolute URI and it stays empty - naming the resource IS the
                 reference, no ldh:Object wrapper, no rdf:value span -->
            <xsl:variable name="island" as="element()" select="rdfae:element('div')"/>
            <ixsl:set-attribute name="about" select="if ($reference) then $reference-uri else $about" object="$island"/>
            <xsl:if test="not($reference)">
                <ixsl:set-attribute name="typeof" select="$type" object="$island"/>
            </xsl:if>
            <xsl:variable name="spans" as="element()*">
                <xsl:choose>
                    <xsl:when test="$reference"/>
                    <xsl:when test="$type = '&ldh;View'">
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&spin;query'"/>
                            <xsl:with-param name="resource" select="$view-query"/>
                        </xsl:call-template>
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&ac;mode'"/>
                            <xsl:with-param name="resource" select="$view-mode[. ne '']"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&spin;query'"/>
                            <xsl:with-param name="resource" select="$chart-query"/>
                        </xsl:call-template>
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&ldh;chartType'"/>
                            <xsl:with-param name="resource" select="$chart-type"/>
                        </xsl:call-template>
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&ldh;categoryVarName'"/>
                            <xsl:with-param name="text" select="$chart-category[. ne '']"/>
                        </xsl:call-template>
                        <xsl:call-template name="rdfae:make-definition-span">
                            <xsl:with-param name="property" select="'&ldh;seriesVarName'"/>
                            <xsl:with-param name="text" select="$chart-series[. ne '']"/>
                        </xsl:call-template>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            <!-- spans with neither a resource nor a literal text value are dropped -->
            <xsl:for-each select="$spans[@resource or normalize-space()]">
                <xsl:sequence select="ixsl:call($island, 'appendChild', [ . ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:for-each>
            <!-- placed per the content model relative to the host the dialog was
                 opened from (same path as figures/tables); init locks it, sets
                 tabindex and fires the renderer -->
            <xsl:call-template name="rdfae:insert-block-at-caret">
                <xsl:with-param name="node" select="$island"/>
                <xsl:with-param name="host" select="ixsl:get(rdfae:editor-state(), 'insertHost')[exists(rdfae:block-of(.))]"/>
            </xsl:call-template>
            <xsl:call-template name="rdfae:init-block">
                <xsl:with-param name="block" select="$island"/>
            </xsl:call-template>
            <xsl:call-template name="rdfae:select-island">
                <xsl:with-param name="element" select="$island"/>
            </xsl:call-template>
            <xsl:call-template name="rdfae:after-mutation"/>
        </xsl:if>
        <xsl:call-template name="rdfae:hide-dialogs"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'ldh-block-cancel')]" mode="ixsl:onclick">
        <xsl:call-template name="rdfae:hide-dialogs"/>
    </xsl:template>

</xsl:stylesheet>
