<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:local="urn:rdfa-editor:functions"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    Object blocks: RDF-defined blocks (LinkedDataHub queries, charts, views, ...)
    embedded in content as self-describing RDFa placeholders - a div whose @typeof
    matches $object-block-types, carrying its defining triples as property spans.
    The editor treats such a div as an atomic island: never a text host, focusable
    like a block image, a hard boundary for merges and cross-host deletes. The
    visual rendering is injected into an ephemeral div[@data-role='rendering']
    child (canonicalization-stripped, extractor-skipped), so the placeholder
    round-trips byte-identically wherever the content model admits a div.

    The core knows no block vocabulary: $object-block-types is empty and the
    local:render-island mode ships a neutral placeholder card. An extension
    stylesheet (src/ldh-blocks.xsl here; LinkedDataHub's client.xsl in
    production) imports the editor, re-declares the param and overrides the mode
    per @typeof with real (async) renderers - see the render-hook contract below.
-->

    <!-- island classes: absolute class IRIs matched against tokenize(@typeof).
         Empty in core - re-declared at higher import precedence by an extension
         entry (a same-precedence duplicate would be static error XTSE0630) -->
    <xsl:param name="object-block-types" as="xs:string*" select="()"/>

    <!-- THE island predicate: every island decision (init, navigation, merge
         boundaries, the delete machine, undo re-render) routes through here -->
    <xsl:function name="local:island" as="xs:boolean">
        <xsl:param name="element" as="element()?"/>
        <xsl:sequence select="exists($element[self::div][tokenize(@typeof) = $object-block-types])"/>
    </xsl:function>

    <!-- the render hook. Context item = the island div. Contract: inject exactly
         one div[@data-role='rendering'] as the island's last child via
         local:replace-rendering - async renderers only in the completion callback
         (loading state = the ephemeral rdfa-editor-loading class), so an island
         without a rendering div always reads as "render needed" (the undo-restore
         re-render pass keys on that); never touch the RDFa spans; never push undo
         (rendering is ephemeral by construction); idempotent (replace, not append) -->
    <xsl:mode name="local:render-island" on-no-match="deep-skip"/>

    <!-- neutral default: a static card naming the block's type and resource.
         Extension templates matching per @typeof win on import precedence -->
    <xsl:template match="*" mode="local:render-island">
        <xsl:variable name="type" as="xs:string?"
            select="(tokenize(@typeof)[. = $object-block-types], tokenize(@typeof))[1]"/>
        <xsl:call-template name="local:replace-rendering">
            <xsl:with-param name="island" select="."/>
            <xsl:with-param name="content">
                <div class="rdfa-editor-island-card">
                    <strong><xsl:value-of select="replace($type, '^.*[#/]', '')"/></strong>
                    <xsl:for-each select="(@resource, @about)[1]">
                        <xsl:text> </xsl:text>
                        <code><xsl:value-of select="."/></code>
                    </xsl:for-each>
                </div>
            </xsl:with-param>
        </xsl:call-template>
    </xsl:template>

    <!-- idempotent rendering-container swap: the only writer of the rendering div -->
    <xsl:template name="local:replace-rendering">
        <xsl:param name="island" as="element()"/>
        <xsl:param name="content" as="node()*"/>
        <xsl:for-each select="$island/*[@data-role = 'rendering']">
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:variable name="rendering" as="element()" select="local:element('div')"/>
        <xsl:for-each select="$rendering">
            <ixsl:set-attribute name="data-role" select="'rendering'"/>
        </xsl:for-each>
        <!-- html method: XML's self-closing tags read as OPEN tags to the HTML
             fragment parser and swallow following siblings -->
        <ixsl:set-property name="innerHTML"
            select="serialize($content, map{ 'method': 'html' })" object="$rendering"/>
        <xsl:sequence select="ixsl:call($island, 'appendChild', [ $rendering ])[current-date() lt xs:date('2000-01-01')]"/>
    </xsl:template>

    <!-- ............................ extension hooks ............................ -->

    <!-- no-op extension points, overridden at higher import precedence: dialogs
         appended to body at init, toolbar Insert-group buttons, slash-menu items,
         and slash-command dispatch for those items -->
    <xsl:template name="local:render-extra-dialogs"/>

    <xsl:template name="local:render-extra-insert-buttons"/>

    <xsl:template name="local:render-extra-slash-items"/>

    <xsl:template name="local:run-extra-slash-command">
        <xsl:param name="command" as="xs:string"/>
        <xsl:param name="host" as="element()?"/>
    </xsl:template>

</xsl:stylesheet>
