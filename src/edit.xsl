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
    Built-in XHTML editor: structured blocks under the #content container, each
    individually contenteditable - block structure is never browser-editable.
    Enter splits, Backspace at block start merges, the toolbar changes block types
    and wraps inline strong/em/a (reusing the annotation machinery), blocks reorder
    via the drag handle. Injected chrome carries data-role="chrome" and is stripped
    by canonical-xhtml.xsl and skipped by the RDFa extractor.

    Undo: native per-block typing undo works (Ctrl/Cmd+Z is never intercepted);
    structural operations (split/merge/convert/move/delete) are not undoable in v1.
-->

    <!-- ................................ helpers ................................ -->

    <!-- the page URI without its fragment: the base for RDFa resolution in the browser -->
    <xsl:function name="local:document-uri" as="xs:string">
        <xsl:sequence select="substring-before(ixsl:get(ixsl:window(), 'location.href') || '#', '#')"/>
    </xsl:function>

    <!-- editable regions are marked by convention with the rdfa-editor-content class
         (host-page chrome: never serialized - the canonical form strips @class) -->
    <xsl:function name="local:roots" as="element()*">
        <xsl:sequence select="ixsl:page()//*[contains-token(@class, 'rdfa-editor-content')]"/>
    </xsl:function>

    <xsl:function name="local:root-of" as="element()?">
        <xsl:param name="node"/>
        <xsl:sequence select="$node/ancestor-or-self::*[contains-token(@class, 'rdfa-editor-content')][1]"/>
    </xsl:function>

    <!-- the region the user is working in: selection first, then the last focused host -->
    <xsl:function name="local:active-root" as="element()?">
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:variable name="anchor" select="if (ixsl:get($selection, 'rangeCount') ge 1)
            then ixsl:get($selection, 'anchorNode') else ()"/>
        <xsl:sequence select="($anchor ! local:root-of(.),
            ixsl:get(ixsl:window(), 'rdfaEditorActiveBlock') ! local:root-of(.), local:roots()[1])[1]"/>
    </xsl:function>

    <!-- the top-level block containing a node -->
    <xsl:function name="local:block-of" as="element()?">
        <xsl:param name="node"/>
        <xsl:sequence select="$node/ancestor-or-self::*[parent::*[contains-token(@class, 'rdfa-editor-content')]][1]"/>
    </xsl:function>

    <!-- the editable host containing a node (block, li or figcaption) -->
    <xsl:function name="local:host-of" as="element()?">
        <xsl:param name="node"/>
        <xsl:sequence select="$node/ancestor-or-self::*[@contenteditable = 'true'][1]"/>
    </xsl:function>

    <!-- toolbar actions resolve the block from the selection, falling back to the
         last focused host (the block-type select steals focus - see ixsl:onfocusin) -->
    <xsl:function name="local:current-block" as="element()?">
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:variable name="anchor" select="if (ixsl:get($selection, 'rangeCount') ge 1)
            then ixsl:get($selection, 'anchorNode') else ()"/>
        <xsl:sequence select="($anchor ! local:block-of(.), ixsl:get(ixsl:window(), 'rdfaEditorActiveBlock') ! local:block-of(.))[1]"/>
    </xsl:function>

    <xsl:function name="local:chrome-count" as="xs:integer">
        <xsl:param name="block" as="element()"/>
        <xsl:sequence select="count($block/*[@data-role = 'chrome'])"/>
    </xsl:function>

    <!-- block text excluding chrome, for emptiness checks -->
    <xsl:function name="local:block-text" as="xs:string">
        <xsl:param name="block" as="element()"/>
        <xsl:sequence select="normalize-space(string-join($block//text()[not(ancestor::*[@data-role])]))"/>
    </xsl:function>

    <!-- true when nothing but chrome precedes the caret inside the host -->
    <xsl:function name="local:at-start" as="xs:boolean">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="range"/>
        <xsl:variable name="probe" select="ixsl:call(ixsl:page(), 'createRange', [])"/>
        <xsl:sequence select="ixsl:call($probe, 'setStart', [ $host, local:chrome-count($host) ])[current-date() lt xs:date('2000-01-01')],
            ixsl:call($probe, 'setEnd', [ ixsl:get($range, 'startContainer'), xs:integer(ixsl:get($range, 'startOffset')) ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:sequence select="string(ixsl:call($probe, 'toString', [])) = ''"/>
    </xsl:function>

    <!-- true when nothing but a trailing placeholder follows the caret inside the host -->
    <xsl:function name="local:at-end" as="xs:boolean">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="range"/>
        <xsl:variable name="probe" select="ixsl:call(ixsl:page(), 'createRange', [])"/>
        <xsl:sequence select="ixsl:call($probe, 'setEnd', [ $host, xs:integer(ixsl:get($host, 'childNodes.length')) ])[current-date() lt xs:date('2000-01-01')],
            ixsl:call($probe, 'setStart', [ ixsl:get($range, 'endContainer'), xs:integer(ixsl:get($range, 'endOffset')) ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:sequence select="string(ixsl:call($probe, 'toString', [])) = ''"/>
    </xsl:function>

    <!-- an empty editable host needs a <br> placeholder: without one it has no height
         and no valid caret position (its only child may be non-editable chrome), so
         clicks and typing go nowhere. Dropped again by canonical-xhtml.xsl -->
    <xsl:template name="local:ensure-placeholder">
        <xsl:param name="host" as="element()"/>
        <xsl:if test="local:block-text($host) = '' and empty($host/br)">
            <xsl:sequence select="ixsl:call($host, 'appendChild',
                [ local:element('br') ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>
    </xsl:template>

    <!-- outermost RDFa-attributed inline ancestor of a node, strictly below the host -->
    <xsl:function name="local:enclosing-annotation" as="element()?">
        <xsl:param name="node"/>
        <xsl:param name="host" as="element()"/>
        <xsl:sequence select="($node/ancestor-or-self::*[@property or @about or @typeof or @resource]
            intersect $host/descendant::*)[1]"/>
    </xsl:function>

    <xsl:function name="local:selection" as="item()">
        <xsl:sequence select="ixsl:call(ixsl:window(), 'getSelection', [])"/>
    </xsl:function>

    <xsl:function name="local:caret-range" as="item()?">
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:sequence select="if (ixsl:get($selection, 'rangeCount') ge 1)
            then ixsl:call($selection, 'getRangeAt', [ 0 ]) else ()"/>
    </xsl:function>

    <xsl:function name="local:element" as="element()">
        <xsl:param name="name" as="xs:string"/>
        <xsl:sequence select="ixsl:call(ixsl:page(), 'createElement', [ $name ])"/>
    </xsl:function>

    <!-- focus the host of $node, then collapse the caret there -->
    <xsl:template name="local:focus-caret">
        <xsl:param name="node"/>
        <xsl:param name="offset" as="xs:integer"/>
        <xsl:for-each select="local:host-of($node)">
            <xsl:call-template name="local:focus">
                <xsl:with-param name="element" select="."/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:call-template name="local:place-caret">
            <xsl:with-param name="node" select="$node"/>
            <xsl:with-param name="offset" select="$offset"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="local:place-caret">
        <xsl:param name="node"/>
        <xsl:param name="offset" as="xs:integer"/>
        <xsl:sequence select="ixsl:call(local:selection(), 'collapse',
            [ $node, $offset ])[current-date() lt xs:date('2000-01-01')]"/>
    </xsl:template>

    <xsl:template name="local:focus">
        <xsl:param name="element" as="element()"/>
        <xsl:sequence select="ixsl:call($element, 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
    </xsl:template>

    <!-- ................................ init ................................ -->

    <xsl:template name="local:init-editing">
        <xsl:for-each select="ixsl:page()//nav">
            <xsl:result-document href="?." method="ixsl:append-content">
                <xsl:call-template name="local:render-toolbar"/>
            </xsl:result-document>
        </xsl:for-each>
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <xsl:call-template name="local:render-link-dialog"/>
                <xsl:call-template name="local:render-figure-dialog"/>
            </xsl:result-document>
        </xsl:for-each>
        <xsl:for-each select="local:roots()/*">
            <xsl:call-template name="local:init-block">
                <xsl:with-param name="block" select="."/>
            </xsl:call-template>
        </xsl:for-each>
    </xsl:template>

    <!-- editability per block kind: composite blocks lock their structure -->
    <xsl:template name="local:init-block">
        <xsl:param name="block" as="element()"/>

        <xsl:for-each select="$block[self::p or self::h1 or self::h2 or self::h3
                or self::blockquote or self::pre],
                $block[self::ul or self::ol]/li, $block[self::figure]/figcaption">
            <ixsl:set-attribute name="contenteditable" select="'true'"/>
        </xsl:for-each>
        <xsl:call-template name="local:inject-chrome">
            <xsl:with-param name="block" select="$block"/>
        </xsl:call-template>
    </xsl:template>

    <!-- first-child chrome keeps split ranges (caret to end of block) clean of it -->
    <xsl:template name="local:inject-chrome">
        <xsl:param name="block" as="element()"/>

        <xsl:if test="empty($block/*[@data-role = 'chrome'])">
            <xsl:variable name="chrome" as="element()" select="local:element('span')"/>
            <ixsl:set-attribute name="data-role" select="'chrome'" object="$chrome"/>
            <ixsl:set-attribute name="class" select="'drag-handle'" object="$chrome"/>
            <ixsl:set-attribute name="contenteditable" select="'false'" object="$chrome"/>
            <ixsl:set-attribute name="title" select="'Drag to reorder'" object="$chrome"/>
            <ixsl:set-property name="textContent" select="'&#x283F;'" object="$chrome"/>
            <xsl:sequence select="ixsl:call($block, 'prepend', [ $chrome ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>
    </xsl:template>

    <xsl:template name="local:remove-chrome">
        <xsl:param name="block" as="element()"/>
        <xsl:for-each select="$block/*[@data-role = 'chrome']">
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:render-toolbar">
        <div id="edit-toolbar" class="rdfa-editor-ui" role="toolbar" aria-label="Editing toolbar">
            <select name="block-type" title="Block type" aria-label="Block type">
                <option value="p">Paragraph</option>
                <option value="h1">Heading 1</option>
                <option value="h2">Heading 2</option>
                <option value="h3">Heading 3</option>
                <option value="blockquote">Quote</option>
                <option value="pre">Preformatted</option>
            </select>
            <button type="button" class="format-inline" data-element="strong" title="Bold" aria-label="Bold"><strong>B</strong></button>
            <button type="button" class="format-inline" data-element="em" title="Italic" aria-label="Italic"><em>I</em></button>
            <button type="button" class="format-link" title="Link" aria-label="Link">&#x1F517;</button>
            <button type="button" class="insert-block" title="Add paragraph" aria-label="Add paragraph">+ &#xB6;</button>
            <button type="button" class="insert-list" data-list="ul" title="Bulleted list" aria-label="Bulleted list">&#x2022; List</button>
            <button type="button" class="insert-list" data-list="ol" title="Numbered list" aria-label="Numbered list">1. List</button>
            <button type="button" class="insert-figure" title="Insert figure" aria-label="Insert figure">&#x1F5BC;</button>
            <button type="button" class="delete-block" title="Delete block" aria-label="Delete block">&#x2715;</button>
            <button type="button" id="toc-toggle" title="Table of contents" aria-label="Table of contents">&#x2630;</button>
            <button type="button" id="find-open" title="Find and replace" aria-label="Find and replace">&#x1F50D;</button>
            <button type="button" id="view-source" title="Canonical XHTML+RDFa" aria-label="View canonical source">Source</button>
        </div>
    </xsl:template>

    <!-- ................................ keyboard ................................ -->

    <xsl:template match="*[@contenteditable = 'true']" mode="ixsl:onkeydown">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="key" as="xs:string" select="string(ixsl:get($event, 'key'))"/>
        <xsl:variable name="chord" as="xs:boolean"
            select="(ixsl:get($event, 'ctrlKey') or ixsl:get($event, 'metaKey')) and not(ixsl:get($event, 'altKey'))"/>
        <xsl:if test="exists(local:block-of(.)) and not(ixsl:get($event, 'isComposing'))">
            <xsl:choose>
                <!-- native undo is replaced by the snapshot history: intercept even on an empty stack -->
                <xsl:when test="$chord and lower-case($key) = 'z' and not(ixsl:get($event, 'shiftKey'))">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:apply-undo"/>
                </xsl:when>
                <xsl:when test="$chord and ((lower-case($key) = 'z' and ixsl:get($event, 'shiftKey'))
                        or (lower-case($key) = 'y' and not(ixsl:get($event, 'shiftKey'))))">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:apply-redo"/>
                </xsl:when>
                <!-- other ctrl/meta chords stay native (copy, paste, browser find) -->
                <xsl:when test="ixsl:get($event, 'ctrlKey') or ixsl:get($event, 'metaKey')"/>
                <!-- Escape closes the annotation overlay / dialogs even while focus
                     remains in the content (their own keydown templates only fire
                     when focus is inside them) -->
                <xsl:when test="$key = 'Escape'">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:hide-overlay"/>
                    <xsl:call-template name="local:hide-dialogs"/>
                </xsl:when>
                <!-- Alt+Arrow moves the current block (keyboard alternative to drag-and-drop) -->
                <xsl:when test="ixsl:get($event, 'altKey') and $key = ('ArrowUp', 'ArrowDown')">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:variable name="host" as="element()" select="."/>
                    <xsl:variable name="block" as="element()?" select="local:block-of(.)"/>
                    <xsl:for-each select="if ($key = 'ArrowUp')
                            then $block/preceding-sibling::*[1] else $block/following-sibling::*[1]">
                        <xsl:call-template name="local:push-undo"/>
                        <xsl:sequence select="ixsl:call(., if ($key = 'ArrowUp') then 'before' else 'after',
                            [ $block ])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>
                    <!-- moving the focused block blurs it -->
                    <xsl:call-template name="local:focus">
                        <xsl:with-param name="element" select="$host"/>
                    </xsl:call-template>
                    <xsl:call-template name="local:after-mutation"/>
                </xsl:when>
                <!-- arrow keys cross block boundaries: each block is its own
                     contenteditable island, so the browser stops at its edges -->
                <xsl:when test="$key = ('ArrowDown', 'ArrowRight', 'ArrowUp', 'ArrowLeft')
                        and not(ixsl:get($event, 'shiftKey')) and not(ixsl:get($event, 'altKey'))">
                    <xsl:variable name="selection" select="local:selection()"/>
                    <xsl:if test="ixsl:get($selection, 'rangeCount') ge 1 and ixsl:get($selection, 'isCollapsed')">
                        <xsl:variable name="range" select="local:caret-range()"/>
                        <xsl:variable name="host" as="element()" select="."/>
                        <xsl:variable name="hosts" as="element()*"
                            select="local:root-of(.)//*[@contenteditable = 'true']"/>
                        <xsl:choose>
                            <xsl:when test="$key = ('ArrowDown', 'ArrowRight') and local:at-end($host, $range)">
                                <xsl:for-each select="($hosts[. &gt;&gt; $host])[1]">
                                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                                    <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="."/>
    <xsl:with-param name="offset" select="local:chrome-count(.)"/>
</xsl:call-template>
                                </xsl:for-each>
                            </xsl:when>
                            <xsl:when test="$key = ('ArrowUp', 'ArrowLeft') and local:at-start($host, $range)">
                                <xsl:for-each select="($hosts[. &lt;&lt; $host])[last()]">
                                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                                    <xsl:call-template name="local:focus">
                                        <xsl:with-param name="element" select="."/>
                                    </xsl:call-template>
                                    <!-- caret at the end, but before a trailing placeholder <br> -->
                                    <xsl:call-template name="local:place-caret">
                                        <xsl:with-param name="node" select="."/>
                                        <xsl:with-param name="offset"
                                            select="count(node()) - count(node()[last()][self::br])"/>
                                    </xsl:call-template>
                                </xsl:for-each>
                            </xsl:when>
                            <xsl:otherwise/>
                        </xsl:choose>
                    </xsl:if>
                </xsl:when>
                <xsl:when test="$key = ('Enter', 'Backspace')">
                    <xsl:variable name="selection" select="local:selection()"/>
                    <xsl:if test="ixsl:get($selection, 'rangeCount') ge 1">
                        <xsl:variable name="range" select="local:caret-range()"/>
                        <xsl:choose>
                            <xsl:when test="$key = 'Enter'">
                                <xsl:call-template name="local:handle-enter">
                                    <xsl:with-param name="host" select="."/>
                                    <xsl:with-param name="event" select="$event"/>
                                    <xsl:with-param name="range" select="$range"/>
                                </xsl:call-template>
                            </xsl:when>
                            <!-- Backspace intercepts only collapsed carets; everything else stays native (B1) -->
                            <xsl:when test="ixsl:get($selection, 'isCollapsed')">
                                <xsl:call-template name="local:handle-backspace">
                                    <xsl:with-param name="host" select="."/>
                                    <xsl:with-param name="event" select="$event"/>
                                    <xsl:with-param name="range" select="$range"/>
                                </xsl:call-template>
                            </xsl:when>
                        </xsl:choose>
                    </xsl:if>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:if>
    </xsl:template>

    <!-- undo chords also work with focus on the page background -->
    <xsl:template match="body" mode="ixsl:onkeydown">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="key" as="xs:string" select="string(ixsl:get($event, 'key'))"/>
        <xsl:variable name="chord" as="xs:boolean"
            select="(ixsl:get($event, 'ctrlKey') or ixsl:get($event, 'metaKey')) and not(ixsl:get($event, 'altKey'))"/>
        <xsl:if test="ixsl:call(ixsl:get($event, 'target'), 'isSameNode', [ . ]) and $chord">
            <xsl:choose>
                <xsl:when test="lower-case($key) = 'z' and not(ixsl:get($event, 'shiftKey'))">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:apply-undo"/>
                </xsl:when>
                <xsl:when test="(lower-case($key) = 'z' and ixsl:get($event, 'shiftKey'))
                        or (lower-case($key) = 'y' and not(ixsl:get($event, 'shiftKey')))">
                    <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:call-template name="local:apply-redo"/>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:if>
    </xsl:template>

    <xsl:template name="local:handle-enter">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="event"/>
        <xsl:param name="range"/>

        <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:call-template name="local:push-undo">
            <xsl:with-param name="host" select="$host"/>
        </xsl:call-template>
        <xsl:if test="not(ixsl:get($range, 'collapsed'))">
            <xsl:sequence select="ixsl:call($range, 'deleteContents', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>

        <xsl:choose>
            <!-- E1: Shift+Enter = line break -->
            <xsl:when test="ixsl:get($event, 'shiftKey')">
                <xsl:call-template name="local:insert-at-caret">
                    <xsl:with-param name="node" select="local:element('br')"/>
                    <xsl:with-param name="range" select="$range"/>
                </xsl:call-template>
            </xsl:when>
            <!-- E2: line structure inside pre is text -->
            <xsl:when test="$host/self::pre">
                <xsl:call-template name="local:insert-at-caret">
                    <xsl:with-param name="node" select="ixsl:call(ixsl:page(), 'createTextNode', [ '&#10;' ])"/>
                    <xsl:with-param name="range" select="$range"/>
                </xsl:call-template>
            </xsl:when>
            <!-- E4: Enter on the empty last item exits the list -->
            <xsl:when test="$host/self::li and local:block-text($host) = '' and empty($host/following-sibling::li)">
                <xsl:variable name="list" as="element()" select="$host/parent::*"/>
                <xsl:sequence select="ixsl:call($host, 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
                <xsl:if test="empty($list/li)">
                    <xsl:sequence select="ixsl:call($list, 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:if>
                <xsl:call-template name="local:insert-empty-paragraph">
                    <xsl:with-param name="after" select="$list[exists(parent::*)]"/>
                </xsl:call-template>
            </xsl:when>
            <!-- E6: Enter in the caption starts a paragraph after the figure -->
            <xsl:when test="$host/self::figcaption">
                <xsl:call-template name="local:insert-empty-paragraph">
                    <xsl:with-param name="after" select="local:block-of($host)"/>
                </xsl:call-template>
            </xsl:when>
            <!-- E3/E5/E7/E8: split, never through an annotation (the split point moves
                 behind the outermost RDFa-attributed ancestor so the graph is unchanged) -->
            <xsl:otherwise>
                <xsl:for-each select="local:enclosing-annotation(ixsl:get($range, 'startContainer'), $host)">
                    <xsl:sequence select="ixsl:call($range, 'setStartAfter', [ . ])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:sequence select="ixsl:call($range, 'collapse', [ true() ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>
                <xsl:call-template name="local:split-block">
                    <xsl:with-param name="host" select="$host"/>
                    <xsl:with-param name="range" select="$range"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
        <xsl:call-template name="local:after-mutation"/>
    </xsl:template>

    <!-- a fresh empty paragraph after a block: the <br> is the browser-standard caret
         placeholder for empty editable elements (dropped again by canonical-xhtml.xsl) -->
    <xsl:template name="local:insert-empty-paragraph">
        <xsl:param name="after" as="element()?"/>

        <xsl:variable name="p" as="element()" select="local:element('p')"/>
        <xsl:sequence select="ixsl:call($p, 'appendChild', [ local:element('br') ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:choose>
            <xsl:when test="exists($after)">
                <xsl:sequence select="ixsl:call($after, 'after', [ $p ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:for-each select="local:active-root()">
                    <xsl:sequence select="ixsl:call(., 'appendChild', [ $p ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>
            </xsl:otherwise>
        </xsl:choose>
        <ixsl:set-attribute name="contenteditable" select="'true'" object="$p"/>
        <xsl:call-template name="local:inject-chrome">
            <xsl:with-param name="block" select="$p"/>
        </xsl:call-template>
        <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="$p"/>
    <xsl:with-param name="offset" select="local:chrome-count($p)"/>
</xsl:call-template>
    </xsl:template>

    <xsl:template name="local:insert-at-caret">
        <xsl:param name="node"/>
        <xsl:param name="range"/>

        <xsl:sequence select="ixsl:call($range, 'insertNode', [ $node ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:call-template name="local:place-caret">
            <xsl:with-param name="node" select="ixsl:get($node, 'parentNode')"/>
            <xsl:with-param name="offset" select="count($node/preceding-sibling::node()) + 1"/>
        </xsl:call-template>
    </xsl:template>

    <!-- move everything from the caret to the end of the host into a fresh sibling
         of the same name; inline elements wholly after the caret move intact -->
    <xsl:template name="local:split-block">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="range"/>

        <xsl:sequence select="ixsl:call($range, 'setEnd', [ $host, xs:integer(ixsl:get($host, 'childNodes.length')) ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:variable name="fragment" select="ixsl:call($range, 'extractContents', [])"/>
        <xsl:variable name="new" as="element()" select="ixsl:call(ixsl:page(), 'createElement', [ local-name($host) ])"/>
        <xsl:sequence select="ixsl:call($new, 'appendChild', [ $fragment ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:sequence select="ixsl:call($host, 'after', [ $new ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-attribute name="contenteditable" select="'true'" object="$new"/>
        <xsl:if test="not($host/self::li)">
            <xsl:call-template name="local:inject-chrome">
                <xsl:with-param name="block" select="$new"/>
            </xsl:call-template>
        </xsl:if>
        <!-- a split at either extreme leaves one empty half -->
        <xsl:call-template name="local:ensure-placeholder">
            <xsl:with-param name="host" select="$host"/>
        </xsl:call-template>
        <xsl:call-template name="local:ensure-placeholder">
            <xsl:with-param name="host" select="$new"/>
        </xsl:call-template>
        <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="$new"/>
    <xsl:with-param name="offset" select="local:chrome-count($new)"/>
</xsl:call-template>
    </xsl:template>

    <xsl:template name="local:handle-backspace">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="event"/>
        <xsl:param name="range"/>

        <!-- B1: anywhere but the block start stays native -->
        <xsl:if test="local:at-start($host, $range)">
            <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:choose>
                <!-- B4/B5: list items merge into the previous item; the first is inert -->
                <xsl:when test="$host/self::li">
                    <xsl:for-each select="$host/preceding-sibling::li[1]">
                        <xsl:call-template name="local:push-undo">
                            <xsl:with-param name="host" select="$host"/>
                        </xsl:call-template>
                        <xsl:call-template name="local:merge-into-previous">
                            <xsl:with-param name="host" select="$host"/>
                            <xsl:with-param name="prev" select="."/>
                        </xsl:call-template>
                        <xsl:call-template name="local:after-mutation"/>
                    </xsl:for-each>
                </xsl:when>
                <!-- B6 -->
                <xsl:when test="$host/self::figcaption or $host/self::pre"/>
                <xsl:otherwise>
                    <xsl:variable name="prev" as="element()?" select="$host/preceding-sibling::*[1]"/>
                    <xsl:choose>
                        <!-- B2: text blocks merge -->
                        <xsl:when test="$prev[self::p or self::h1 or self::h2 or self::h3 or self::blockquote]">
                            <xsl:call-template name="local:push-undo">
                                <xsl:with-param name="host" select="$host"/>
                            </xsl:call-template>
                            <xsl:call-template name="local:merge-into-previous">
                                <xsl:with-param name="host" select="$host"/>
                                <xsl:with-param name="prev" select="$prev"/>
                            </xsl:call-template>
                            <xsl:call-template name="local:after-mutation"/>
                        </xsl:when>
                        <!-- B3: never merge across composite blocks; an empty block is removed -->
                        <xsl:when test="exists($prev) and local:block-text($host) = ''">
                            <xsl:call-template name="local:push-undo"/>
                            <xsl:sequence select="ixsl:call($host, 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
                            <ixsl:set-property name="rdfaEditorActiveBlock" select="()" object="ixsl:window()"/>
                            <xsl:variable name="prev-host" as="element()?"
                                select="($prev/li[last()], $prev/figcaption, $prev)[@contenteditable = 'true'][1]"/>
                            <xsl:for-each select="$prev-host">
                                <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="."/>
    <xsl:with-param name="offset" select="xs:integer(ixsl:get(., 'childNodes.length'))"/>
</xsl:call-template>
                            </xsl:for-each>
                            <xsl:call-template name="local:after-mutation"/>
                        </xsl:when>
                        <xsl:otherwise/>
                    </xsl:choose>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </xsl:template>

    <!-- counted firstChild moves (never iterate a live child list lazily); no
         normalize() afterwards - the caret index depends on the node count -->
    <xsl:template name="local:merge-into-previous">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="prev" as="element()"/>

        <xsl:call-template name="local:remove-chrome">
            <xsl:with-param name="block" select="$host"/>
        </xsl:call-template>
        <xsl:variable name="index" as="xs:integer" select="xs:integer(ixsl:get($prev, 'childNodes.length'))"/>
        <xsl:for-each select="1 to xs:integer(ixsl:get($host, 'childNodes.length'))">
            <xsl:sequence select="ixsl:call($prev, 'appendChild', [ ixsl:get($host, 'firstChild') ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:sequence select="ixsl:call($host, 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-property name="rdfaEditorActiveBlock" select="()" object="ixsl:window()"/>
        <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="$prev"/>
    <xsl:with-param name="offset" select="$index"/>
</xsl:call-template>
    </xsl:template>

    <!-- ................................ paste / focus ................................ -->

    <!-- block-level element names after canonicalization (attributeless divs became p) -->
    <xsl:variable name="local:block-names" as="xs:string*" select="('p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'ul', 'ol', 'blockquote', 'pre', 'figure', 'table', 'div', 'dl', 'hr', 'section', 'article')"/>

    <xsl:template match="*[@contenteditable = 'true']" mode="ixsl:onpaste">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:if test="exists(local:block-of(.))">
            <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:variable name="html" as="xs:string"
                select="string(ixsl:call(ixsl:get($event, 'clipboardData'), 'getData', [ 'text/html' ]))"/>
            <xsl:choose>
                <!-- formatted paste through the canonical (sanitizing) pipeline -->
                <xsl:when test="$html ne '' and not(self::pre)">
                    <xsl:call-template name="local:paste-html">
                        <xsl:with-param name="host" select="."/>
                        <xsl:with-param name="html" select="$html"/>
                    </xsl:call-template>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:call-template name="local:paste-text">
                        <xsl:with-param name="host" select="."/>
                        <xsl:with-param name="raw" select="string(ixsl:call(ixsl:get($event, 'clipboardData'),
                            'getData', [ 'text/plain' ]))"/>
                    </xsl:call-template>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </xsl:template>

    <xsl:template name="local:paste-text">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="raw" as="xs:string"/>

        <xsl:variable name="text" as="xs:string"
            select="if ($host/self::pre) then $raw else normalize-space($raw)"/>
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:if test="$text ne '' and ixsl:get($selection, 'rangeCount') ge 1">
            <xsl:variable name="range" select="local:caret-range()"/>
            <xsl:call-template name="local:push-undo">
                <xsl:with-param name="host" select="$host"/>
            </xsl:call-template>
            <xsl:sequence select="ixsl:call($range, 'deleteContents', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:variable name="node" select="ixsl:call(ixsl:page(), 'createTextNode', [ $text ])"/>
            <xsl:sequence select="ixsl:call($range, 'insertNode', [ $node ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:place-caret">
                <xsl:with-param name="node" select="$node"/>
                <xsl:with-param name="offset" select="string-length($text)"/>
            </xsl:call-template>
            <xsl:call-template name="local:after-mutation"/>
        </xsl:if>
    </xsl:template>

    <!-- clipboard HTML: browser-parse it on a DETACHED element (scripts inert),
         sanitize/normalize via mode="canonical", then insert - inline fragments at
         the caret, block-level content as new blocks between the split halves -->
    <xsl:template name="local:paste-html">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="html" as="xs:string"/>

        <xsl:variable name="carrier" as="element()" select="local:element('div')"/>
        <ixsl:set-property name="innerHTML" select="$html" object="$carrier"/>
        <xsl:variable name="clean">
            <xsl:apply-templates select="$carrier/node()" mode="canonical"/>
        </xsl:variable>
        <xsl:variable name="has-blocks" as="xs:boolean"
            select="exists($clean/*[local-name() = $local:block-names])"/>
        <xsl:variable name="selection" select="local:selection()"/>

        <xsl:choose>
            <xsl:when test="empty($clean/node()) or ixsl:get($selection, 'rangeCount') lt 1"/>
            <!-- composite hosts cannot contain blocks: flatten to text -->
            <xsl:when test="$has-blocks and $host[self::li or self::figcaption]">
                <xsl:call-template name="local:paste-text">
                    <xsl:with-param name="host" select="$host"/>
                    <xsl:with-param name="raw" select="string($carrier)"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="$has-blocks">
                <!-- stray top-level inline runs become paragraphs -->
                <xsl:variable name="blocks" as="element()*">
                    <xsl:for-each-group select="$clean/node()"
                            group-adjacent="boolean(self::*[local-name() = $local:block-names])">
                        <xsl:choose>
                            <xsl:when test="current-grouping-key()">
                                <xsl:sequence select="current-group()"/>
                            </xsl:when>
                            <xsl:when test="normalize-space(string-join(current-group() ! string(.)))">
                                <p>
                                    <xsl:sequence select="current-group()"/>
                                </p>
                            </xsl:when>
                            <xsl:otherwise/>
                        </xsl:choose>
                    </xsl:for-each-group>
                </xsl:variable>
                <xsl:variable name="range" select="local:caret-range()"/>
                <xsl:call-template name="local:push-undo">
                    <xsl:with-param name="host" select="$host"/>
                </xsl:call-template>
                <xsl:if test="not(ixsl:get($range, 'collapsed'))">
                    <xsl:sequence select="ixsl:call($range, 'deleteContents', [])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:if>
                <!-- split the host, then thread the pasted blocks in after the first half -->
                <xsl:call-template name="local:split-block">
                    <xsl:with-param name="host" select="$host"/>
                    <xsl:with-param name="range" select="$range"/>
                </xsl:call-template>
                <xsl:variable name="stage" as="element()" select="local:element('div')"/>
                <ixsl:set-property name="innerHTML" select="serialize($blocks, map{ 'method': 'xml' })" object="$stage"/>
                <xsl:variable name="count" as="xs:integer" select="xs:integer(ixsl:get($stage, 'childNodes.length'))"/>
                <xsl:iterate select="1 to $count">
                    <xsl:param name="anchor" select="$host"/>
                    <xsl:variable name="node" select="ixsl:get($stage, 'firstChild')"/>
                    <xsl:sequence select="ixsl:call($anchor, 'after', [ $node ])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:next-iteration>
                        <xsl:with-param name="anchor" select="$node"/>
                    </xsl:next-iteration>
                </xsl:iterate>
                <xsl:for-each select="$host/following-sibling::*[position() le $count]">
                    <xsl:call-template name="local:init-block">
                        <xsl:with-param name="block" select="."/>
                    </xsl:call-template>
                </xsl:for-each>
                <!-- caret at the end of the last pasted block's last editable host -->
                <xsl:variable name="last" as="element()?" select="$host/following-sibling::*[$count]"/>
                <xsl:for-each select="($last/descendant-or-self::*[@contenteditable = 'true'])[last()]">
                    <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="."/>
    <xsl:with-param name="offset" select="count(node()) - count(node()[last()][self::br])"/>
</xsl:call-template>
                </xsl:for-each>
                <xsl:call-template name="local:after-mutation"/>
            </xsl:when>
            <!-- inline-only fragment: insert at the caret -->
            <xsl:otherwise>
                <xsl:variable name="range" select="local:caret-range()"/>
                <xsl:call-template name="local:push-undo">
                    <xsl:with-param name="host" select="$host"/>
                </xsl:call-template>
                <xsl:sequence select="ixsl:call($range, 'deleteContents', [])[current-date() lt xs:date('2000-01-01')]"/>
                <xsl:variable name="stage" as="element()" select="local:element('div')"/>
                <ixsl:set-property name="innerHTML" select="serialize($clean/node(), map{ 'method': 'xml' })" object="$stage"/>
                <xsl:variable name="last" select="ixsl:get($stage, 'lastChild')"/>
                <xsl:variable name="fragment" select="ixsl:call(ixsl:page(), 'createDocumentFragment', [])"/>
                <xsl:for-each select="1 to xs:integer(ixsl:get($stage, 'childNodes.length'))">
                    <xsl:sequence select="ixsl:call($fragment, 'appendChild', [ ixsl:get($stage, 'firstChild') ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>
                <xsl:sequence select="ixsl:call($range, 'insertNode', [ $fragment ])[current-date() lt xs:date('2000-01-01')]"/>
                <xsl:for-each select="$last">
                    <xsl:call-template name="local:place-caret">
                        <xsl:with-param name="node" select="ixsl:get(., 'parentNode')"/>
                        <xsl:with-param name="offset" select="count(preceding-sibling::node()) + 1"/>
                    </xsl:call-template>
                </xsl:for-each>
                <xsl:call-template name="local:after-mutation"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <xsl:template match="*[@contenteditable = 'true']" mode="ixsl:onfocusin">
        <xsl:if test="exists(local:block-of(.))">
            <ixsl:set-property name="rdfaEditorActiveBlock" select="." object="ixsl:window()"/>
            <xsl:call-template name="local:update-breadcrumb"/>
        </xsl:if>
    </xsl:template>

    <!-- ................................ toolbar ................................ -->

    <!-- buttons must not steal the selection they act on -->
    <xsl:template match="div[@id = 'edit-toolbar']//button" mode="ixsl:onmousedown">
        <xsl:sequence select="ixsl:call(ixsl:event(), 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
    </xsl:template>

    <xsl:template match="select[@name = 'block-type']" mode="ixsl:onchange">
        <xsl:variable name="name" as="xs:string" select="string(ixsl:get(., 'value'))"/>
        <xsl:for-each select="local:current-block()[self::p or self::h1 or self::h2 or self::h3
                or self::blockquote or self::pre][local-name() ne $name]">
            <xsl:call-template name="local:convert-block">
                <xsl:with-param name="block" select="."/>
                <xsl:with-param name="name" select="$name"/>
            </xsl:call-template>
        </xsl:for-each>
    </xsl:template>

    <!-- rename by rebuild: copy RDFa/lang attributes, move children (text-node
         references survive reparenting, so the caret can be restored exactly) -->
    <xsl:template name="local:convert-block">
        <xsl:param name="block" as="element()"/>
        <xsl:param name="name" as="xs:string"/>

        <xsl:call-template name="local:push-undo"/>
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:variable name="caret-node" select="if (ixsl:get($selection, 'rangeCount') ge 1)
            then ixsl:get($selection, 'anchorNode')[local:block-of(.) is $block] else ()"/>
        <xsl:variable name="caret-offset" as="xs:integer"
            select="if (exists($caret-node)) then xs:integer(ixsl:get($selection, 'anchorOffset')) else 0"/>

        <xsl:variable name="new" as="element()" select="ixsl:call(ixsl:page(), 'createElement', [ $name ])"/>
        <xsl:for-each select="$block/(@about | @property | @typeof | @resource | @content
                | @datatype | @lang | @xml:lang | @contenteditable)">
            <ixsl:set-attribute name="{name()}" select="string(.)" object="$new"/>
        </xsl:for-each>
        <xsl:for-each select="1 to xs:integer(ixsl:get($block, 'childNodes.length'))">
            <xsl:sequence select="ixsl:call($new, 'appendChild', [ ixsl:get($block, 'firstChild') ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:sequence select="ixsl:call($block, 'replaceWith', [ $new ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-property name="rdfaEditorActiveBlock" select="$new" object="ixsl:window()"/>
        <xsl:call-template name="local:focus">
            <xsl:with-param name="element" select="$new"/>
        </xsl:call-template>
        <xsl:choose>
            <xsl:when test="exists($caret-node)">
                <xsl:call-template name="local:place-caret">
                    <xsl:with-param name="node" select="$caret-node"/>
                    <xsl:with-param name="offset" select="$caret-offset"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="local:place-caret">
                    <xsl:with-param name="node" select="$new"/>
                    <xsl:with-param name="offset" select="local:chrome-count($new)"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
        <xsl:call-template name="local:after-mutation"/>
    </xsl:template>

    <!-- inline formatting toggles reuse the annotation wrap/unwrap machinery -->
    <xsl:template match="button[contains-token(@class, 'format-inline')]" mode="ixsl:onclick">
        <xsl:variable name="name" as="xs:string" select="string(@data-element)"/>
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:if test="ixsl:get($selection, 'rangeCount') ge 1">
            <xsl:variable name="range" select="local:caret-range()"/>
            <xsl:variable name="anchor" select="ixsl:get($selection, 'anchorNode')"/>
            <xsl:for-each select="local:host-of($anchor)[exists(local:block-of(.))]">
                <xsl:variable name="existing" as="element()?"
                    select="($anchor/ancestor-or-self::*[local-name() = $name] intersect descendant::*)[1]"/>
                <xsl:choose>
                    <xsl:when test="exists($existing)">
                        <xsl:call-template name="local:push-undo"/>
                        <xsl:call-template name="local:unwrap-element">
                            <xsl:with-param name="element" select="$existing"/>
                        </xsl:call-template>
                        <xsl:call-template name="local:after-mutation"/>
                    </xsl:when>
                    <xsl:when test="not(ixsl:get($selection, 'isCollapsed'))">
                        <!-- capture pre-wrap state; push only when the wrap succeeded -->
                        <xsl:variable name="snapshot-root" as="element()?" select="local:active-root()"/>
                        <xsl:variable name="snapshot" as="xs:string?"
                            select="$snapshot-root ! string(ixsl:get(., 'innerHTML'))"/>
                        <xsl:variable name="wrapped" as="element()?">
                            <xsl:call-template name="local:wrap-range">
                                <xsl:with-param name="range" select="$range"/>
                                <xsl:with-param name="name" select="$name"/>
                            </xsl:call-template>
                        </xsl:variable>
                        <xsl:for-each select="$wrapped">
                            <xsl:call-template name="local:push-undo">
                                <xsl:with-param name="root" select="$snapshot-root"/>
                                <xsl:with-param name="snapshot" select="$snapshot"/>
                            </xsl:call-template>
                            <xsl:call-template name="local:after-mutation"/>
                        </xsl:for-each>
                    </xsl:when>
                    <xsl:otherwise/>
                </xsl:choose>
            </xsl:for-each>
        </xsl:if>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'insert-block')]" mode="ixsl:onclick">
        <xsl:call-template name="local:push-undo"/>
        <xsl:call-template name="local:insert-empty-paragraph">
            <xsl:with-param name="after" select="local:current-block()"/>
        </xsl:call-template>
        <xsl:call-template name="local:after-mutation"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'insert-list')]" mode="ixsl:onclick">
        <xsl:call-template name="local:push-undo"/>
        <xsl:variable name="list" as="element()" select="ixsl:call(ixsl:page(), 'createElement', [ string(@data-list) ])"/>
        <xsl:variable name="li" as="element()" select="local:element('li')"/>
        <ixsl:set-attribute name="contenteditable" select="'true'" object="$li"/>
        <xsl:sequence select="ixsl:call($list, 'appendChild', [ $li ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:choose>
            <xsl:when test="exists(local:current-block())">
                <xsl:sequence select="ixsl:call(local:current-block(), 'after', [ $list ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:for-each select="local:active-root()">
                    <xsl:sequence select="ixsl:call(., 'appendChild', [ $list ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>
            </xsl:otherwise>
        </xsl:choose>
        <xsl:call-template name="local:inject-chrome">
            <xsl:with-param name="block" select="$list"/>
        </xsl:call-template>
        <xsl:call-template name="local:focus-caret">
    <xsl:with-param name="node" select="$li"/>
    <xsl:with-param name="offset" select="0"/>
</xsl:call-template>
        <xsl:call-template name="local:after-mutation"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'delete-block')]" mode="ixsl:onclick">
        <xsl:for-each select="local:current-block()">
            <xsl:variable name="confirmed" as="xs:boolean" select="local:block-text(.) = ''
                or ixsl:call(ixsl:window(), 'confirm', [ 'Delete this block?' ])"/>
            <xsl:if test="$confirmed">
                <xsl:call-template name="local:push-undo"/>
                <xsl:variable name="prev" as="element()?" select="preceding-sibling::*[1]"/>
                <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
                <ixsl:set-property name="rdfaEditorActiveBlock" select="()" object="ixsl:window()"/>
                <xsl:for-each select="($prev/li[last()], $prev/figcaption, $prev)[@contenteditable = 'true'][1]">
                    <xsl:call-template name="local:focus">
                        <xsl:with-param name="element" select="."/>
                    </xsl:call-template>
                </xsl:for-each>
                <xsl:call-template name="local:after-mutation"/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <!-- ................................ link dialog ................................ -->

    <xsl:template match="button[contains-token(@class, 'format-link')]" mode="ixsl:onclick">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="selection" select="local:selection()"/>
        <xsl:if test="ixsl:get($selection, 'rangeCount') ge 1">
            <xsl:variable name="range" select="local:caret-range()"/>
            <xsl:variable name="anchor" select="ixsl:get($selection, 'anchorNode')"/>
            <xsl:for-each select="local:host-of($anchor)[exists(local:block-of(.))]">
                <xsl:variable name="link" as="element()?"
                    select="($anchor/ancestor-or-self::a intersect descendant::*)[1]"/>
                <xsl:choose>
                    <!-- caret inside a link: edit it -->
                    <xsl:when test="exists($link)">
                        <ixsl:set-property name="rdfaEditorEditingLink" select="$link" object="ixsl:window()"/>
                        <xsl:call-template name="local:open-link-dialog">
                            <xsl:with-param name="event" select="$event"/>
                            <xsl:with-param name="href" select="string($link/@href)"/>
                            <xsl:with-param name="editing" select="true()"/>
                        </xsl:call-template>
                    </xsl:when>
                    <!-- selection: create one -->
                    <xsl:when test="not(ixsl:get($selection, 'isCollapsed'))">
                        <ixsl:set-property name="rdfaEditorEditRange" select="$range" object="ixsl:window()"/>
                        <ixsl:set-property name="rdfaEditorEditingLink" select="()" object="ixsl:window()"/>
                        <xsl:call-template name="local:open-link-dialog">
                            <xsl:with-param name="event" select="$event"/>
                            <xsl:with-param name="href" select="''"/>
                            <xsl:with-param name="editing" select="false()"/>
                        </xsl:call-template>
                    </xsl:when>
                    <xsl:otherwise/>
                </xsl:choose>
            </xsl:for-each>
        </xsl:if>
    </xsl:template>

    <xsl:template name="local:render-link-dialog">
        <div id="link-dialog" class="rdfa-editor-ui edit-dialog" role="dialog" aria-modal="true"
                aria-label="Link" style="display: none;">
            <label>Link target (href)</label>
            <input type="text" name="href" placeholder="https://..."/>
            <div class="action-buttons">
                <button type="button" class="btn-danger link-remove" style="display: none;">Remove link</button>
                <button type="button" class="btn-primary link-save">Save</button>
                <button type="button" class="btn-secondary link-cancel">Cancel</button>
            </div>
        </div>
    </xsl:template>

    <xsl:template name="local:open-link-dialog">
        <xsl:param name="event"/>
        <xsl:param name="href" as="xs:string"/>
        <xsl:param name="editing" as="xs:boolean"/>

        <xsl:variable name="dialog" as="element()" select="id('link-dialog', ixsl:page())"/>
        <xsl:for-each select="($dialog//input[@name = 'href'])[1]">
            <ixsl:set-property name="value" select="$href" object="."/>
        </xsl:for-each>
        <xsl:for-each select="$dialog//button[contains-token(@class, 'link-remove')]">
            <ixsl:set-style name="display" select="if ($editing) then 'inline-block' else 'none'"/>
        </xsl:for-each>
        <xsl:call-template name="local:show-at">
            <xsl:with-param name="element" select="$dialog"/>
            <xsl:with-param name="event" select="$event"/>
        </xsl:call-template>
        <xsl:for-each select="($dialog//input[@name = 'href'])[1]">
            <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'link-save')]" mode="ixsl:onclick">
        <xsl:variable name="href" as="xs:string"
            select="string(ixsl:get((ancestor::div[@id = 'link-dialog']//input[@name = 'href'])[1], 'value'))"/>
        <xsl:if test="$href ne ''">
            <xsl:variable name="editing" select="ixsl:get(ixsl:window(), 'rdfaEditorEditingLink')"/>
            <xsl:choose>
                <xsl:when test="exists($editing)">
                    <xsl:call-template name="local:push-undo"/>
                    <xsl:for-each select="$editing">
                        <ixsl:set-attribute name="href" select="$href"/>
                    </xsl:for-each>
                </xsl:when>
                <xsl:otherwise>
                    <!-- capture pre-wrap state; push only when the wrap succeeded -->
                    <xsl:variable name="snapshot-root" as="element()?" select="local:active-root()"/>
                    <xsl:variable name="snapshot" as="xs:string?"
                        select="$snapshot-root ! string(ixsl:get(., 'innerHTML'))"/>
                    <xsl:variable name="wrapped" as="element()?">
                        <xsl:call-template name="local:wrap-range">
                            <xsl:with-param name="range" select="ixsl:get(ixsl:window(), 'rdfaEditorEditRange')"/>
                            <xsl:with-param name="name" select="'a'"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:for-each select="$wrapped">
                        <xsl:call-template name="local:push-undo">
                            <xsl:with-param name="root" select="$snapshot-root"/>
                            <xsl:with-param name="snapshot" select="$snapshot"/>
                        </xsl:call-template>
                        <ixsl:set-attribute name="href" select="$href"/>
                    </xsl:for-each>
                </xsl:otherwise>
            </xsl:choose>
            <xsl:call-template name="local:after-mutation"/>
        </xsl:if>
        <xsl:call-template name="local:hide-dialogs"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'link-remove')]" mode="ixsl:onclick">
        <xsl:for-each select="ixsl:get(ixsl:window(), 'rdfaEditorEditingLink')">
            <xsl:call-template name="local:push-undo"/>
            <xsl:call-template name="local:unwrap-element">
                <xsl:with-param name="element" select="."/>
            </xsl:call-template>
            <xsl:call-template name="local:after-mutation"/>
        </xsl:for-each>
        <xsl:call-template name="local:hide-dialogs"/>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'link-cancel')
            or contains-token(@class, 'figure-cancel')]" mode="ixsl:onclick">
        <xsl:call-template name="local:hide-dialogs"/>
    </xsl:template>

    <xsl:template match="div[@id = ('link-dialog', 'figure-dialog', 'find-dialog')]" mode="ixsl:onkeydown">
        <xsl:if test="string(ixsl:get(ixsl:event(), 'key')) = 'Escape'">
            <xsl:sequence select="ixsl:call(ixsl:event(), 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:hide-dialogs"/>
        </xsl:if>
    </xsl:template>

    <!-- single teardown point for all dialogs -->
    <xsl:template name="local:hide-dialogs">
        <xsl:for-each select="id('link-dialog', ixsl:page()), id('figure-dialog', ixsl:page()),
                id('find-dialog', ixsl:page())">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:for-each>
        <ixsl:set-property name="rdfaEditorEditRange" select="()" object="ixsl:window()"/>
        <ixsl:set-property name="rdfaEditorEditingLink" select="()" object="ixsl:window()"/>
        <ixsl:set-property name="rdfaEditorInsertAfterBlock" select="()" object="ixsl:window()"/>
        <ixsl:set-property name="rdfaEditorFindNode" select="()" object="ixsl:window()"/>
        <ixsl:set-property name="rdfaEditorFindOffset" select="1" object="ixsl:window()"/>
        <!-- return focus to the content -->
        <xsl:for-each select="ixsl:get(ixsl:window(), 'rdfaEditorActiveBlock')[exists(local:block-of(.))]">
            <xsl:call-template name="local:focus">
                <xsl:with-param name="element" select="."/>
            </xsl:call-template>
        </xsl:for-each>
    </xsl:template>

    <!-- ................................ figure dialog ................................ -->

    <xsl:template match="button[contains-token(@class, 'insert-figure')]" mode="ixsl:onclick">
        <ixsl:set-property name="rdfaEditorInsertAfterBlock"
            select="(local:current-block(), local:active-root()/*[last()])[1]" object="ixsl:window()"/>
        <xsl:variable name="dialog" as="element()" select="id('figure-dialog', ixsl:page())"/>
        <xsl:for-each select="$dialog//input">
            <ixsl:set-property name="value" select="''" object="."/>
        </xsl:for-each>
        <xsl:call-template name="local:show-at">
            <xsl:with-param name="element" select="$dialog"/>
            <xsl:with-param name="event" select="ixsl:event()"/>
        </xsl:call-template>
        <xsl:for-each select="($dialog//input[@name = 'src'])[1]">
            <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:render-figure-dialog">
        <div id="figure-dialog" class="rdfa-editor-ui edit-dialog" role="dialog" aria-modal="true"
                aria-label="Insert figure" style="display: none;">
            <label>Image URL (src)</label>
            <input type="text" name="src" placeholder="https://... or relative path"/>
            <label>Alternate text (alt)</label>
            <input type="text" name="alt"/>
            <label>Caption</label>
            <input type="text" name="caption"/>
            <div class="action-buttons">
                <button type="button" class="btn-primary figure-save">Insert</button>
                <button type="button" class="btn-secondary figure-cancel">Cancel</button>
            </div>
        </div>
    </xsl:template>

    <xsl:template match="button[contains-token(@class, 'figure-save')]" mode="ixsl:onclick">
        <xsl:variable name="dialog" as="element()" select="ancestor::div[@id = 'figure-dialog']"/>
        <xsl:variable name="src" as="xs:string" select="string(ixsl:get(($dialog//input[@name = 'src'])[1], 'value'))"/>
        <xsl:if test="$src ne ''">
            <xsl:call-template name="local:push-undo"/>
            <xsl:variable name="figure" as="element()" select="local:element('figure')"/>
            <xsl:variable name="img" as="element()" select="local:element('img')"/>
            <ixsl:set-attribute name="src" select="$src" object="$img"/>
            <ixsl:set-attribute name="alt" select="string(ixsl:get(($dialog//input[@name = 'alt'])[1], 'value'))" object="$img"/>
            <xsl:variable name="figcaption" as="element()" select="local:element('figcaption')"/>
            <ixsl:set-property name="textContent" select="string(ixsl:get(($dialog//input[@name = 'caption'])[1], 'value'))" object="$figcaption"/>
            <ixsl:set-attribute name="contenteditable" select="'true'" object="$figcaption"/>
            <xsl:sequence select="ixsl:call($figure, 'appendChild', [ $img ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call($figure, 'appendChild', [ $figcaption ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:choose>
                <xsl:when test="exists(ixsl:get(ixsl:window(), 'rdfaEditorInsertAfterBlock'))">
                    <xsl:sequence select="ixsl:call(ixsl:get(ixsl:window(), 'rdfaEditorInsertAfterBlock'), 'after', [ $figure ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:for-each select="local:active-root()">
                        <xsl:sequence select="ixsl:call(., 'appendChild', [ $figure ])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>
                </xsl:otherwise>
            </xsl:choose>
            <xsl:call-template name="local:inject-chrome">
                <xsl:with-param name="block" select="$figure"/>
            </xsl:call-template>
            <xsl:call-template name="local:focus">
                <xsl:with-param name="element" select="$figcaption"/>
            </xsl:call-template>
            <xsl:call-template name="local:after-mutation"/>
        </xsl:if>
        <xsl:call-template name="local:hide-dialogs"/>
    </xsl:template>

    <!-- ................................ drag-and-drop ................................ -->
    <!-- ported from LinkedDataHub client/block.xsl; handle-gated draggable because a
         permanently draggable contenteditable block breaks text selection -->

    <xsl:template match="span[contains-token(@class, 'drag-handle')]" mode="ixsl:onmousedown">
        <xsl:for-each select="local:block-of(.)">
            <ixsl:set-attribute name="draggable" select="'true'"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="span[contains-token(@class, 'drag-handle')]" mode="ixsl:onmouseup">
        <xsl:for-each select="local:block-of(.)">
            <ixsl:remove-attribute name="draggable"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="*[parent::*[contains-token(@class, 'rdfa-editor-content')]][@draggable = 'true']" mode="ixsl:ondragstart">
        <xsl:variable name="transfer" select="ixsl:get(ixsl:event(), 'dataTransfer')"/>
        <ixsl:set-property name="rdfaEditorDraggedBlock" select="." object="ixsl:window()"/>
        <ixsl:set-property name="effectAllowed" select="'move'" object="$transfer"/>
        <xsl:sequence select="ixsl:call($transfer, 'setData', [ 'application/x-rdfa-editor-block', '' ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:sequence select="ixsl:call($transfer, 'setDragImage', [ ., 0, 0 ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'add', [ 'dragging' ])[current-date() lt xs:date('2000-01-01')]"/>
    </xsl:template>

    <!-- links cannot navigate on plain click inside contenteditable (the click
         places the caret for editing); the standard editor convention applies:
         Ctrl/Cmd+Click follows the link -->
    <xsl:template match="*[contains-token(@class, 'rdfa-editor-content')]//a[@href]" mode="ixsl:onclick">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:if test="ixsl:get($event, 'ctrlKey') or ixsl:get($event, 'metaKey')">
            <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call(ixsl:window(), 'open',
                [ string(resolve-uri(@href, local:document-uri())), '_blank' ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>
    </xsl:template>

    <!-- images are natively draggable, so a drag starting on one would otherwise
         carry no block identity and snap back; treat it as dragging its block -->
    <xsl:template match="*[contains-token(@class, 'rdfa-editor-content')]//img" mode="ixsl:ondragstart">
        <xsl:variable name="transfer" select="ixsl:get(ixsl:event(), 'dataTransfer')"/>
        <xsl:for-each select="local:block-of(.)">
            <ixsl:set-property name="rdfaEditorDraggedBlock" select="." object="ixsl:window()"/>
            <ixsl:set-property name="effectAllowed" select="'move'" object="$transfer"/>
            <xsl:sequence select="ixsl:call($transfer, 'setData', [ 'application/x-rdfa-editor-block', '' ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call($transfer, 'setDragImage', [ ., 0, 0 ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'add', [ 'dragging' ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="*[contains-token(@class, 'rdfa-editor-content')] | *[contains-token(@class, 'rdfa-editor-content')]//*" mode="ixsl:ondragover">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="dragged" select="ixsl:get(ixsl:window(), 'rdfaEditorDraggedBlock')"/>
        <xsl:variable name="target" as="element()?" select="local:drop-target-of(., $event)"/>
        <xsl:if test="exists($dragged) and exists($target)
                and local:has-transfer-type($event, 'application/x-rdfa-editor-block')">
            <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <ixsl:set-property name="dropEffect" select="'move'" object="ixsl:get($event, 'dataTransfer')"/>
            <xsl:call-template name="local:clear-drop-marks"/>
            <xsl:sequence select="ixsl:call(ixsl:get($target, 'classList'), 'add',
                [ if (local:drop-before($event, $target)) then 'drop-before' else 'drop-after' ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>
    </xsl:template>

    <xsl:template match="*[contains-token(@class, 'rdfa-editor-content')] | *[contains-token(@class, 'rdfa-editor-content')]//*" mode="ixsl:ondrop">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="dragged" select="ixsl:get(ixsl:window(), 'rdfaEditorDraggedBlock')"/>
        <xsl:variable name="target" as="element()?" select="local:drop-target-of(., $event)"/>
        <xsl:if test="exists($dragged) and exists($target)
                and local:has-transfer-type($event, 'application/x-rdfa-editor-block')">
            <xsl:sequence select="ixsl:call($event, 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:clear-drop-marks"/>
            <xsl:call-template name="local:push-undo"/>
            <xsl:sequence select="ixsl:call($target,
                if (local:drop-before($event, $target)) then 'before' else 'after',
                [ $dragged ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:call-template name="local:after-mutation"/>
        </xsl:if>
    </xsl:template>

    <xsl:template match="*[contains-token(@class, 'rdfa-editor-content')] | *[contains-token(@class, 'rdfa-editor-content')]//*" mode="ixsl:ondragend">
        <xsl:for-each select="local:block-of(.)">
            <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'remove', [ 'dragging' ])[current-date() lt xs:date('2000-01-01')]"/>
            <ixsl:remove-attribute name="draggable"/>
        </xsl:for-each>
        <xsl:call-template name="local:clear-drop-marks"/>
        <ixsl:set-property name="rdfaEditorDraggedBlock" select="()" object="ixsl:window()"/>
    </xsl:template>

    <!-- dataTransfer.types marshals to an XDM array or sequence of strings -->
    <xsl:function name="local:has-transfer-type" as="xs:boolean">
        <xsl:param name="event"/>
        <xsl:param name="type" as="xs:string"/>
        <xsl:variable name="types" select="ixsl:get(ixsl:get($event, 'dataTransfer'), 'types')"/>
        <xsl:sequence select="(if ($types instance of array(*)) then $types?* else $types) = $type"/>
    </xsl:function>

    <!-- the block to drop relative to: the hit-tested block when there is one,
         else the geometrically nearest block by vertical midpoint - so gaps between
         blocks, the container padding and the (tall) dragged block itself are all
         valid drop zones instead of snapping the drag back -->
    <xsl:function name="local:drop-target-of" as="element()?">
        <xsl:param name="hit"/>
        <xsl:param name="event"/>
        <xsl:variable name="dragged" select="ixsl:get(ixsl:window(), 'rdfaEditorDraggedBlock')"/>
        <!-- blocks never move between editable regions -->
        <xsl:variable name="root" as="element()?"
            select="($dragged ! local:root-of(.), local:root-of($hit))[1]"/>
        <xsl:variable name="block" as="element()?"
            select="local:block-of($hit)[local:root-of(.) is $root]"/>
        <xsl:choose>
            <xsl:when test="exists($block) and not(exists($dragged) and $block is $dragged)">
                <xsl:sequence select="$block"/>
            </xsl:when>
            <!-- geometric fallback only within the dragged block's own region:
                 a pointer over another region is not a drop zone at all -->
            <xsl:when test="not(local:root-of($hit) is $root)"/>
            <xsl:otherwise>
                <xsl:variable name="y" as="xs:double" select="xs:double(ixsl:get($event, 'clientY'))"/>
                <xsl:variable name="candidates" as="element()*"
                    select="$root/*[not(exists($dragged) and . is $dragged)]"/>
                <xsl:variable name="distances" as="xs:double*" select="$candidates
                    ! (let $rect := ixsl:call(., 'getBoundingClientRect', []) return
                        abs(xs:double(ixsl:get($rect, 'top')) + xs:double(ixsl:get($rect, 'height')) div 2 - $y))"/>
                <xsl:variable name="nearest" as="xs:integer?" select="index-of($distances, min($distances))[1]"/>
                <xsl:sequence select="$candidates[$nearest]"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!-- above or below the vertical midpoint of the target block -->
    <xsl:function name="local:drop-before" as="xs:boolean">
        <xsl:param name="event"/>
        <xsl:param name="target" as="element()"/>
        <xsl:variable name="rect" select="ixsl:call($target, 'getBoundingClientRect', [])"/>
        <xsl:sequence select="xs:double(ixsl:get($event, 'clientY')) - xs:double(ixsl:get($rect, 'top'))
            lt xs:double(ixsl:get($rect, 'height')) div 2"/>
    </xsl:function>

    <xsl:template name="local:clear-drop-marks">
        <xsl:param name="scope" as="element()*" select="local:roots()/*"/>
        <xsl:for-each select="$scope[contains-token(@class, 'drop-before')
                or contains-token(@class, 'drop-after')]">
            <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'remove', [ 'drop-before' ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:sequence select="ixsl:call(ixsl:get(., 'classList'), 'remove', [ 'drop-after' ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
    </xsl:template>

    <!-- ................................ view source ................................ -->

    <xsl:template match="button[@id = 'view-source']" mode="ixsl:onclick">
        <xsl:variable name="canonical" as="element()?">
            <xsl:call-template name="canonical-xhtml">
                <xsl:with-param name="content" select="local:active-root()"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:call-template name="local:show-output">
            <xsl:with-param name="title" select="'Canonical XHTML+RDFa'"/>
            <xsl:with-param name="text" select="serialize($canonical, map{ 'method': 'xml', 'indent': true() })"/>
        </xsl:call-template>
    </xsl:template>

</xsl:stylesheet>
