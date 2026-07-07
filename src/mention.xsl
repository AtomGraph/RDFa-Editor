<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
xmlns:local="urn:rdfa-editor:functions"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    @-mention: author a relation triple inline, Notion-style. Typing @ (at a word
    boundary) opens a picker with an explicit predicate (from the loaded vocabularies)
    and an object IRI autocompleted from resources already in the document, vocabulary
    class terms, or free-form entry. The result is a
        <span property="P" resource="O">label</span>
    which the extractor reads as (in-scope-subject, P, O) - a real IRI-object triple,
    no @rel needed. Reuses the annotation write path (local:apply-annotation) and the
    selection wrapper (local:wrap-range) so the emitted RDFa cannot drift from the
    right-click annotation form.
-->

    <xsl:template name="local:init-mention">
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <xsl:call-template name="local:render-mention-dialog"/>
            </xsl:result-document>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:render-mention-dialog">
        <!-- the host preloaded these into the document pool under page-relative URIs -->
        <xsl:variable name="vocab-uris" as="xs:string*"
            select="$vocab-hrefs ! string(resolve-uri(., ixsl:location()))"/>

        <div id="mention-dialog" class="rdfa-editor-ui edit-dialog" role="dialog" aria-modal="true"
                aria-label="Mention a resource" style="display: none;">
            <label>Relationship (property)</label>
            <select name="property">
                <xsl:call-template name="local:vocab-options">
                    <xsl:with-param name="hrefs" select="$vocab-uris"/>
                    <xsl:with-param name="kind" select="'property'"/>
                </xsl:call-template>
            </select>
            <label>Resource (IRI)</label>
            <input type="text" name="resource" list="mention-resources" autocomplete="off"
                placeholder="https://... or type to search"/>
            <datalist id="mention-resources"/>
            <label class="mention-label-field">Link text</label>
            <input type="text" name="label" class="mention-label-field" placeholder="Displayed text"/>
            <div class="action-buttons">
                <button type="button" class="btn-primary mention-save">Insert</button>
                <button type="button" class="btn-secondary mention-cancel">Cancel</button>
            </div>
        </div>
    </xsl:template>

    <!-- object-IRI autocomplete: subjects and IRI objects already in the document,
         plus vocabulary class terms; recomputed on each open so it tracks edits -->
    <xsl:function name="local:mention-candidates" as="xs:string*">
        <xsl:variable name="base" as="xs:string" select="local:document-uri()"/>
        <xsl:variable name="rdf" as="element(rdf:RDF)">
            <xsl:call-template name="extract-rdfa">
                <xsl:with-param name="doc" select="ixsl:page()"/>
                <xsl:with-param name="base" select="$base"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:variable name="doc-resources" as="xs:string*"
            select="($rdf//rdf:Description/@rdf:about, $rdf//@rdf:resource) ! string(.)"/>
        <xsl:variable name="vocab-uris" as="xs:string*"
            select="$vocab-hrefs ! string(resolve-uri(., ixsl:location()))"/>
        <xsl:variable name="vocab-terms" as="xs:string*"
            select="$vocab-uris ! doc(.) ! local:vocab-terms(., 'class') ! ?uri"/>
        <xsl:sequence select="sort(distinct-values(
            ($doc-resources, $vocab-terms)[. ne ''][not(starts-with(., '_:'))]))"/>
    </xsl:function>

    <!-- open the picker at the caret; called by the onbeforeinput dispatcher (edit.xsl) -->
    <xsl:template name="local:open-mention">
        <xsl:param name="event"/>
        <xsl:variable name="range" select="local:caret-range()"/>
        <xsl:if test="exists($range)">
            <ixsl:set-property name="rdfaEditorMentionRange" select="$range" object="ixsl:window()"/>
            <xsl:variable name="collapsed" as="xs:boolean" select="boolean(ixsl:get($range, 'collapsed'))"/>
            <xsl:variable name="dialog" as="element()" select="id('mention-dialog', ixsl:page())"/>

            <!-- refresh the resource autocomplete list -->
            <xsl:for-each select="id('mention-resources', ixsl:page())">
                <xsl:result-document href="?." method="ixsl:replace-content">
                    <xsl:for-each select="local:mention-candidates()">
                        <option value="{.}"/>
                    </xsl:for-each>
                </xsl:result-document>
            </xsl:for-each>

            <xsl:for-each select="($dialog//input[@name = 'resource'])[1]">
                <ixsl:set-property name="value" select="''" object="."/>
            </xsl:for-each>
            <!-- with a selection the selected text is the link text; a collapsed caret
                 needs an explicit label field -->
            <xsl:for-each select="($dialog//input[@name = 'label'])[1]">
                <ixsl:set-property name="value" select="string(ixsl:call($range, 'toString', []))" object="."/>
            </xsl:for-each>
            <xsl:for-each select="$dialog//*[contains-token(@class, 'mention-label-field')]">
                <ixsl:set-style name="display" select="if ($collapsed) then 'block' else 'none'"/>
            </xsl:for-each>

            <xsl:call-template name="local:show-at-caret">
                <xsl:with-param name="element" select="$dialog"/>
            </xsl:call-template>
            <xsl:for-each select="($dialog//input[@name = 'resource'])[1]">
                <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:for-each>
        </xsl:if>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'mention-save')]" mode="ixsl:onclick">
        <xsl:variable name="dialog" as="element()" select="ancestor::div[@id = 'mention-dialog']"/>
        <xsl:variable name="property" as="xs:string"
            select="string(ixsl:get(($dialog//select[@name = 'property'])[1], 'value'))"/>
        <xsl:variable name="resource" as="xs:string"
            select="normalize-space(string(ixsl:get(($dialog//input[@name = 'resource'])[1], 'value')))"/>
        <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'rdfaEditorMentionRange')"/>
        <xsl:if test="$property ne '' and $resource ne '' and exists($range)">
            <xsl:variable name="values" as="map(xs:string, xs:string?)"
                select="map{ 'property': $property, 'object': $resource }"/>
            <xsl:choose>
                <!-- a selection: wrap it, pushing undo only when the wrap succeeded -->
                <xsl:when test="not(boolean(ixsl:get($range, 'collapsed')))">
                    <xsl:variable name="reference-text" as="xs:string" select="string(ixsl:call($range, 'toString', []))"/>
                    <xsl:variable name="snapshot-root" as="element()?" select="local:active-root()"/>
                    <xsl:variable name="snapshot" as="xs:string?" select="$snapshot-root ! string(ixsl:get(., 'innerHTML'))"/>
                    <xsl:variable name="span" as="element()?">
                        <xsl:call-template name="local:wrap-range">
                            <xsl:with-param name="range" select="$range"/>
                            <xsl:with-param name="name" select="'span'"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:for-each select="$span">
                        <xsl:call-template name="local:push-undo">
                            <xsl:with-param name="root" select="$snapshot-root"/>
                            <xsl:with-param name="snapshot" select="$snapshot"/>
                        </xsl:call-template>
                        <xsl:call-template name="local:apply-annotation">
                            <xsl:with-param name="target" select="."/>
                            <xsl:with-param name="values" select="$values"/>
                            <xsl:with-param name="reference-text" select="$reference-text"/>
                        </xsl:call-template>
                        <xsl:call-template name="local:after-mutation"/>
                    </xsl:for-each>
                </xsl:when>
                <!-- collapsed caret: build the labelled span and insert it -->
                <xsl:otherwise>
                    <xsl:variable name="typed" as="xs:string"
                        select="normalize-space(string(ixsl:get(($dialog//input[@name = 'label'])[1], 'value')))"/>
                    <xsl:variable name="label" as="xs:string"
                        select="if ($typed ne '') then $typed else replace($resource, '^.*[#/]', '')"/>
                    <xsl:call-template name="local:push-undo"/>
                    <xsl:variable name="span" as="element()" select="local:element('span')"/>
                    <ixsl:set-property name="textContent" select="$label" object="$span"/>
                    <xsl:call-template name="local:apply-annotation">
                        <xsl:with-param name="target" select="$span"/>
                        <xsl:with-param name="values" select="$values"/>
                        <xsl:with-param name="reference-text" select="$label"/>
                    </xsl:call-template>
                    <xsl:call-template name="local:insert-at-caret">
                        <xsl:with-param name="node" select="$span"/>
                        <xsl:with-param name="range" select="$range"/>
                    </xsl:call-template>
                    <xsl:call-template name="local:after-mutation"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
        <xsl:call-template name="local:hide-dialogs"/>
    </xsl:template>

</xsl:stylesheet>
