<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:local="urn:rdfa-editor:functions"
xmlns:rdfa="urn:rdfa:functions"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    Event handling. One interaction model: right-click inside editable content.
    On an existing annotation it opens the editor pre-filled (with a Remove action);
    on a plain selection it validates the range and opens the create form.
    Plain clicks never open the overlay, so the caret stays usable while editing text.
-->

    <xsl:template match="*[@contenteditable = 'true']" mode="ixsl:oncontextmenu">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="target" select="ixsl:get($event, 'target')"/>
        <!-- innermost annotated element strictly inside this editable root -->
        <xsl:variable name="annotation" as="element()?"
            select="($target/ancestor-or-self::*[@property or @typeof or @about or @resource]
                intersect descendant::*)[last()]"/>
        <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>

        <xsl:choose>
            <!-- edit mode -->
            <xsl:when test="exists($annotation)">
                <ixsl:set-property name="editingSpan" select="$annotation" object="ixsl:window()"/>
                <xsl:call-template name="local:populate-form">
                    <xsl:with-param name="span" select="$annotation"/>
                </xsl:call-template>
                <xsl:call-template name="local:update-form-visibility">
                    <xsl:with-param name="pattern" select="local:span-pattern($annotation)"/>
                </xsl:call-template>
                <xsl:call-template name="local:show-overlay">
                    <xsl:with-param name="event" select="$event"/>
                    <xsl:with-param name="selected-text" select="string($annotation)"/>
                    <xsl:with-param name="in-scope-subject"
                        select="$annotation/parent::* ! rdfa:in-scope-subject(., local:document-uri())"/>
                </xsl:call-template>
            </xsl:when>
            <!-- create mode -->
            <xsl:otherwise>
                <xsl:variable name="selection" select="ixsl:call(ixsl:window(), 'getSelection', [])"/>
                <xsl:if test="ixsl:get($selection, 'rangeCount') ge 1 and not(ixsl:get($selection, 'isCollapsed'))">
                    <xsl:variable name="range" select="ixsl:call($selection, 'getRangeAt', [ 0 ])"/>
                    <xsl:choose>
                        <xsl:when test="local:selection-valid($range)">
                            <ixsl:set-property name="range" select="$range" object="ixsl:window()"/>
                            <ixsl:set-property name="editingSpan" select="()" object="ixsl:window()"/>
                            <xsl:call-template name="local:populate-form"/>
                            <xsl:call-template name="local:update-form-visibility">
                                <xsl:with-param name="pattern" select="'property'"/>
                            </xsl:call-template>
                            <xsl:call-template name="local:show-overlay">
                                <xsl:with-param name="event" select="$event"/>
                                <xsl:with-param name="selected-text" select="string(ixsl:call($selection, 'toString', []))"/>
                                <xsl:with-param name="in-scope-subject" select="rdfa:in-scope-subject(., local:document-uri())"/>
                            </xsl:call-template>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:call-template name="local:show-flash">
                                <xsl:with-param name="range" select="$range"/>
                            </xsl:call-template>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:if>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- surroundContents() succeeds when the range starts and ends in the same
         container, or in sibling text nodes; xsl:try in the Annotate handler backstops
         the partial-selection cases this misses -->
    <xsl:function name="local:selection-valid" as="xs:boolean">
        <xsl:param name="range"/>

        <xsl:variable name="start" select="ixsl:get($range, 'startContainer')"/>
        <xsl:variable name="end" select="ixsl:get($range, 'endContainer')"/>
        <xsl:sequence select="ixsl:call($start, 'isSameNode', [ $end ])
            or (ixsl:get($start, 'nodeType') = 3 and ixsl:get($end, 'nodeType') = 3
                and ixsl:call(ixsl:get($start, 'parentNode'), 'isSameNode', [ ixsl:get($end, 'parentNode') ]))"/>
    </xsl:function>

    <!-- the single write path for RDFa attributes, shared by create and edit -->
    <xsl:template name="local:apply-annotation">
        <xsl:param name="target" as="element()"/>
        <xsl:param name="values" as="map(xs:string, xs:string?)"/>

        <xsl:for-each select="$target">
            <xsl:variable name="element" select="."/>
            <xsl:sequence select="('about', 'typeof', 'property', 'resource', 'content')
                ! ixsl:call($element, 'removeAttribute', [ . ])[current-date() lt xs:date('2000-01-01')]"/>

            <xsl:if test="$values?pattern = 'advanced' and exists($values?subject)">
                <ixsl:set-attribute name="about" select="$values?subject"/>
            </xsl:if>
            <xsl:if test="$values?pattern = 'entity' and exists($values?typeof)">
                <ixsl:set-attribute name="typeof" select="$values?typeof"/>
            </xsl:if>
            <xsl:if test="exists($values?property)">
                <ixsl:set-attribute name="property" select="$values?property"/>
            </xsl:if>
            <xsl:if test="$values?pattern = 'advanced' and exists($values?object)">
                <ixsl:set-attribute name="resource" select="$values?object"/>
            </xsl:if>
            <xsl:if test="$values?value-type = 'custom' and exists($values?content)">
                <ixsl:set-attribute name="content" select="$values?content"/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="button[tokenize(@class) = 'spo-action']" mode="ixsl:onclick">
        <xsl:variable name="values" as="map(xs:string, xs:string?)" select="local:form-values(ancestor::form)"/>
        <xsl:variable name="editing" select="ixsl:get(ixsl:window(), 'editingSpan')"/>

        <xsl:choose>
            <xsl:when test="exists($editing)">
                <xsl:call-template name="local:apply-annotation">
                    <xsl:with-param name="target" select="$editing"/>
                    <xsl:with-param name="values" select="$values"/>
                </xsl:call-template>
                <xsl:call-template name="local:hide-overlay"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'range')"/>
                <xsl:variable name="span" as="element()" select="ixsl:call(ixsl:page(), 'createElement', [ 'span' ])"/>
                <xsl:try>
                    <xsl:sequence select="ixsl:call($range, 'surroundContents', [ $span ])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:apply-annotation">
                        <xsl:with-param name="target" select="$span"/>
                        <xsl:with-param name="values" select="$values"/>
                    </xsl:call-template>
                    <xsl:call-template name="local:hide-overlay"/>
                    <xsl:catch errors="*">
                        <xsl:call-template name="local:hide-overlay"/>
                        <xsl:call-template name="local:show-flash">
                            <xsl:with-param name="range" select="$range"/>
                        </xsl:call-template>
                    </xsl:catch>
                </xsl:try>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- unwrap the annotated element: move its children up, drop it, merge text nodes -->
    <xsl:template match="button[tokenize(@class) = 'remove-action']" mode="ixsl:onclick">
        <xsl:for-each select="ixsl:get(ixsl:window(), 'editingSpan')">
            <xsl:variable name="span" select="."/>
            <xsl:variable name="parent" select="ixsl:get($span, 'parentNode')"/>
            <xsl:for-each select="1 to xs:integer(ixsl:get($span, 'childNodes.length'))">
                <xsl:sequence select="ixsl:call($parent, 'insertBefore', [ ixsl:get($span, 'firstChild'), $span ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:for-each>
            <xsl:sequence select="ixsl:call($parent, 'removeChild', [ $span ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call($parent, 'normalize', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:call-template name="local:hide-overlay"/>
    </xsl:template>

    <xsl:template match="button[tokenize(@class) = 'cancel-action']" mode="ixsl:onclick">
        <xsl:call-template name="local:hide-overlay"/>
    </xsl:template>

    <!-- brief red flash over an invalid selection, in page coordinates so it scrolls with the text -->
    <xsl:template name="local:show-flash">
        <xsl:param name="range"/>

        <xsl:variable name="rect" select="ixsl:call($range, 'getBoundingClientRect', [])"/>
        <xsl:variable name="scroll-x" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollX')"/>
        <xsl:variable name="scroll-y" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollY')"/>
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <div id="selection-flash" class="invalid-selection-flash"
                    style="position: absolute; pointer-events: none; z-index: 9999; left: {ixsl:get($rect, 'left') + $scroll-x}px; top: {ixsl:get($rect, 'top') + $scroll-y}px; width: {ixsl:get($rect, 'width')}px; height: {ixsl:get($rect, 'height')}px;"/>
            </xsl:result-document>
        </xsl:for-each>
        <ixsl:schedule-action wait="1200">
            <xsl:call-template name="local:hide-flash"/>
        </ixsl:schedule-action>
    </xsl:template>

    <xsl:template name="local:hide-flash">
        <xsl:for-each select="id('selection-flash', ixsl:page())">
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <!-- extract RDF/XML from the page and display it in the modal -->
    <xsl:template match="button[@id = 'parse-rdf']" mode="ixsl:onclick">
        <xsl:variable name="rdf">
            <xsl:call-template name="extract-rdfa">
                <xsl:with-param name="doc" select="ixsl:page()"/>
                <xsl:with-param name="base" select="local:document-uri()"/>
            </xsl:call-template>
        </xsl:variable>

        <xsl:for-each select="id('rdf-content', ixsl:page())">
            <ixsl:set-property name="textContent" object="."
                select="serialize($rdf, map{ 'method': 'xml', 'indent': true() })"/>
        </xsl:for-each>
        <xsl:for-each select="id('rdf-modal', ixsl:page())">
            <ixsl:set-style name="display" select="'flex'"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="span[tokenize(@class) = 'modal-close']" mode="ixsl:onclick">
        <xsl:for-each select="id('rdf-modal', ixsl:page())">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:for-each>
    </xsl:template>

    <!-- clicking the backdrop (not the content) closes the modal -->
    <xsl:template match="div[@id = 'rdf-modal']" mode="ixsl:onclick">
        <xsl:if test="ixsl:call(ixsl:get(ixsl:event(), 'target'), 'isSameNode', [ . ])">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:if>
    </xsl:template>

</xsl:stylesheet>
