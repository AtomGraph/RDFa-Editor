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
    Unified snapshot undo/redo: one whole-document history over #content innerHTML.
    Every mutating handler pushes a snapshot first (see the push-point inventory in
    UNDO-NAVIGATION-PLAN.md) and calls local:after-mutation last; plain typing is
    coalesced into ~1s bursts via ixsl:onbeforeinput. Ctrl/Cmd+Z and Shift+Z / Ctrl+Y
    are intercepted in the keydown dispatcher (edit.xsl) - native undo is replaced.

    Storage: hidden DOM stash divs (one child div per snapshot, textContent = the
    innerHTML string). JS arrays are unusable across the IXSL boundary (they marshal
    to XDM sequences; an empty array becomes an empty sequence) and sequence-valued
    window properties store only their first item - the DOM stash uses only proven
    primitives and gives O(1) push/pop. It carries data-role="storage", so the
    extractor skips it; it lives outside #content, so canonicalization never sees it.

    Caret restoration after undo/redo is approximate (first editable host): exact
    restoration would require serializing Range endpoints into content-polluting
    markers, which the canonicalization contract forbids.
-->

    <xsl:variable name="local:max-undo" as="xs:integer" select="100"/>

    <xsl:template name="local:init-undo">
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <div id="undo-storage" data-role="storage" style="display: none;">
                    <div id="undo-stack"/>
                    <div id="redo-stack"/>
                </div>
            </xsl:result-document>
        </xsl:for-each>
    </xsl:template>

    <!-- append a snapshot entry, enforcing the depth cap -->
    <xsl:template name="local:stash-push">
        <xsl:param name="stack" as="element()"/>
        <xsl:param name="snapshot" as="xs:string"/>

        <xsl:variable name="entry" as="element()" select="ixsl:call(ixsl:page(), 'createElement', [ 'div' ])"/>
        <ixsl:set-property name="textContent" select="$snapshot" object="$entry"/>
        <xsl:sequence select="ixsl:call($stack, 'appendChild', [ $entry ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:for-each select="($stack/div)[position() le count($stack/div) - $local:max-undo]">
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <!-- record the pre-mutation state; call FIRST in every mutating handler.
         $snapshot allows capturing before an operation that may fail (wrap-range)
         and pushing only on success -->
    <xsl:template name="local:push-undo">
        <xsl:param name="host" as="element()?" select="()"/>
        <xsl:param name="snapshot" as="xs:string" select="string(ixsl:get(local:content(), 'innerHTML'))"/>

        <xsl:variable name="stack" as="element()" select="id('undo-stack', ixsl:page())"/>
        <!-- dedup guard: a snapshot equal to the top is a no-op (backstop against double pushes) -->
        <xsl:if test="not(string(($stack/div)[last()]) eq $snapshot)">
            <xsl:call-template name="local:stash-push">
                <xsl:with-param name="stack" select="$stack"/>
                <xsl:with-param name="snapshot" select="$snapshot"/>
            </xsl:call-template>
            <ixsl:set-property name="textContent" select="''" object="id('redo-stack', ixsl:page())"/>
        </xsl:if>
        <ixsl:set-property name="lastUndoTime"
            select="ixsl:call(ixsl:get(ixsl:window(), 'Date'), 'now', [])" object="ixsl:window()"/>
        <ixsl:set-property name="lastUndoHost" select="$host" object="ixsl:window()"/>
    </xsl:template>

    <xsl:template name="local:apply-undo">
        <xsl:variable name="top" as="element()?" select="(id('undo-stack', ixsl:page())/div)[last()]"/>
        <xsl:for-each select="$top">
            <xsl:call-template name="local:stash-push">
                <xsl:with-param name="stack" select="id('redo-stack', ixsl:page())"/>
                <xsl:with-param name="snapshot" select="string(ixsl:get(local:content(), 'innerHTML'))"/>
            </xsl:call-template>
            <xsl:variable name="snapshot" as="xs:string" select="string(.)"/>
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:restore-snapshot">
                <xsl:with-param name="snapshot" select="$snapshot"/>
            </xsl:call-template>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:apply-redo">
        <xsl:variable name="top" as="element()?" select="(id('redo-stack', ixsl:page())/div)[last()]"/>
        <xsl:for-each select="$top">
            <!-- raw push onto the undo stack: must NOT clear the redo stack -->
            <xsl:call-template name="local:stash-push">
                <xsl:with-param name="stack" select="id('undo-stack', ixsl:page())"/>
                <xsl:with-param name="snapshot" select="string(ixsl:get(local:content(), 'innerHTML'))"/>
            </xsl:call-template>
            <xsl:variable name="snapshot" as="xs:string" select="string(.)"/>
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:restore-snapshot">
                <xsl:with-param name="snapshot" select="$snapshot"/>
            </xsl:call-template>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:restore-snapshot">
        <xsl:param name="snapshot" as="xs:string"/>

        <xsl:for-each select="local:content()">
            <ixsl:set-property name="innerHTML" select="$snapshot" object="."/>
        </xsl:for-each>
        <!-- every stored node reference is stale now -->
        <xsl:call-template name="local:hide-overlay"/>
        <xsl:call-template name="local:hide-dialogs"/>
        <xsl:for-each select="('activeBlock', 'editingSpan', 'draggedBlock', 'editRange', 'editingLink',
                'insertAfterBlock', 'range', 'breadcrumbLeaf', 'findNode', 'lastUndoHost',
                'draggedSectionHeading')">
            <ixsl:set-property name="{.}" select="()" object="ixsl:window()"/>
        </xsl:for-each>
        <ixsl:set-property name="lastUndoTime" select="0" object="ixsl:window()"/>
        <!-- snapshots taken mid-drag may carry transient drag state -->
        <xsl:call-template name="local:clear-drop-marks"/>
        <xsl:for-each select="local:content()/*[@draggable]">
            <xsl:sequence select="ixsl:call(., 'removeAttribute', [ 'draggable' ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'remove', [ 'dragging' ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:for-each select="(local:content()/descendant-or-self::*[@contenteditable = 'true'])[1]">
            <xsl:call-template name="local:focus">
                <xsl:with-param name="element" select="."/>
            </xsl:call-template>
            <xsl:call-template name="local:place-caret">
                <xsl:with-param name="node" select="."/>
                <xsl:with-param name="offset" select="local:chrome-count(.)"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:call-template name="local:after-mutation"/>
    </xsl:template>

    <!-- coalesced typing history: beforeinput fires pre-mutation for typing, native
         deletes and cut, so a burst boundary snapshot captures the state before it -->
    <xsl:template match="*[@contenteditable = 'true']" mode="ixsl:onbeforeinput">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:if test="exists(local:block-of(.))">
            <xsl:variable name="type" as="xs:string" select="string(ixsl:get($event, 'inputType'))"/>
            <xsl:choose>
                <!-- menu-driven Edit > Undo/Redo bypasses keydown -->
                <xsl:when test="starts-with($type, 'history')">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:choose>
                        <xsl:when test="$type = 'historyUndo'">
                            <xsl:call-template name="local:apply-undo"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:call-template name="local:apply-redo"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:variable name="now" as="xs:double" select="ixsl:call(ixsl:get(ixsl:window(), 'Date'), 'now', [])"/>
                    <xsl:if test="$now - xs:double((ixsl:get(ixsl:window(), 'lastUndoTime'), 0)[1]) gt 1000
                            or not(ixsl:get(ixsl:window(), 'lastUndoHost') ! (. is current()))">
                        <xsl:call-template name="local:push-undo">
                            <xsl:with-param name="host" select="."/>
                        </xsl:call-template>
                        <xsl:call-template name="local:after-mutation"/>
                    </xsl:if>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </xsl:template>

    <!-- the single post-mutation refresh hook: lint markers, live ToC, breadcrumb -->
    <xsl:template name="local:after-mutation">
        <xsl:call-template name="local:run-lint"/>
        <xsl:if test="id('toc-drawer', ixsl:page()) ! (ixsl:get(., 'style.display') ne 'none')">
            <xsl:call-template name="local:render-toc"/>
        </xsl:if>
        <xsl:call-template name="local:update-breadcrumb"/>
    </xsl:template>

</xsl:stylesheet>
