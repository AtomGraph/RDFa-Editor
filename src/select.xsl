<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:local="urn:rdfa-editor:functions"
xmlns:cm="urn:rdfa-editor:content-model"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    Cross-host selection: select-all scoped to the editable region and deletion
    of selections that span editable hosts.

    Each block is its own contenteditable host, so the browser confines
    selections started inside a host to that host and refuses to edit a
    document-level selection that sweeps across hosts (a drag from the page
    background paints across blocks, but Backspace is native-inert). Both
    Ctrl/Cmd+A stage 2 and such mouse sweeps produce the same thing - a
    document-level DOM Range spanning hosts, which paints natively and which
    the Range API can delete even though native editing cannot - so one delete
    machine serves both. Dispatch lives in edit.xsl (keydown, body keydown,
    paste gate); the machinery lives here, mirroring the tables.xsl split.

    Deletion is block-granular, never one raw deleteContents across the range:
    fully covered blocks are removed whole, partial edge hosts get a
    sub-range delete scoped inside the host, and composites (table, figure)
    holding a range boundary never lose grid structure - their covered cells
    are cleared instead (B3/B4 doctrine: composites are hard boundaries).
    Non-composite edge remnants merge Google-Docs-style (the tail joins the
    head, caret at the seam). One gesture pushes one region-keyed undo entry.
-->

    <!-- ................................ predicates ................................ -->

    <!-- the host's content is entirely inside the selection (chrome- and
         placeholder-insensitive via the local:at-* probes); an empty host counts
         as fully selected, so Ctrl+A escalates immediately where stage 1 would
         have nothing to select -->
    <xsl:function name="local:host-fully-selected" as="xs:boolean">
        <xsl:param name="host" as="element()"/>
        <xsl:param name="range"/>
        <xsl:sequence select="local:block-text($host) = ''
            or (not(ixsl:get($range, 'collapsed'))
                and local:at-start($host, $range) and local:at-end($host, $range))"/>
    </xsl:function>

    <!-- true for a non-collapsed selection that engages an editable region but is
         not confined to a single host: the boundary hosts differ, or a boundary
         sits outside any host (region level, page background). Host-page
         contenteditables don't count (the local:block-of clamp), and selections
         that never touch a region stay native -->
    <xsl:function name="local:selection-crosses-hosts" as="xs:boolean">
        <xsl:variable name="range" select="local:caret-range()"/>
        <xsl:choose>
            <xsl:when test="empty($range) or ixsl:get($range, 'collapsed')">
                <xsl:sequence select="false()"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="start-host" as="element()?"
                    select="local:host-of(ixsl:get($range, 'startContainer'))[exists(local:block-of(.))]"/>
                <xsl:variable name="end-host" as="element()?"
                    select="local:host-of(ixsl:get($range, 'endContainer'))[exists(local:block-of(.))]"/>
                <xsl:sequence select="(empty($start-host) or empty($end-host) or not($start-host is $end-host))
                    and (some $root in local:roots() satisfies ixsl:call($range, 'intersectsNode', [ $root ]))"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!-- the node lies entirely inside the range: it intersects it and neither
         range boundary sits at or below the node (an offset in a parent points
         between children, so a boundary inside the node means its container is
         in the node's subtree - pure XDM containment, no compareBoundaryPoints) -->
    <xsl:function name="local:covered-by" as="xs:boolean">
        <xsl:param name="node" as="node()"/>
        <xsl:param name="range"/>
        <xsl:sequence select="ixsl:call($range, 'intersectsNode', [ $node ])
            and empty(ixsl:get($range, 'startContainer')/ancestor-or-self::node()
                intersect $node/descendant-or-self::node())
            and empty(ixsl:get($range, 'endContainer')/ancestor-or-self::node()
                intersect $node/descendant-or-self::node())"/>
    </xsl:function>

    <!-- ................................ region select ................................ -->

    <!-- a document-level range over all of the region's blocks: it paints across
         host boundaries and never extends beyond the region. Focus stays where it
         was, so the same keydown template keeps firing -->
    <xsl:template name="local:select-region">
        <xsl:param name="region" as="element()"/>
        <xsl:variable name="blocks" as="element()*" select="$region/*[not(@data-role)]"/>
        <xsl:if test="exists($blocks)">
            <xsl:variable name="range" select="ixsl:call(ixsl:page(), 'createRange', [])"/>
            <xsl:sequence select="ixsl:call($range, 'setStartBefore', [ $blocks[1] ])[current-date() lt xs:date('2000-01-01')],
                ixsl:call($range, 'setEndAfter', [ $blocks[last()] ])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:variable name="selection" select="local:selection()"/>
            <xsl:sequence select="ixsl:call($selection, 'removeAllRanges', [])[current-date() lt xs:date('2000-01-01')],
                ixsl:call($selection, 'addRange', [ $range ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:if>
    </xsl:template>

    <!-- ................................ delete machine ................................ -->

    <!-- delete a cross-host selection: reads and classification first, one undo
         push, then the mutations in fixed order. Reached from the host and body
         keydown dispatchers (edit.xsl) -->
    <xsl:template name="local:delete-cross-host-selection">
        <xsl:variable name="range" select="local:caret-range()"/>
        <xsl:if test="exists($range) and not(ixsl:get($range, 'collapsed'))">
            <!-- the single region this gesture acts on: the start's region, else
                 the first region the sweep reaches (one gesture = one region-keyed
                 history entry; blocks never leave their region) -->
            <xsl:variable name="region" as="element()?"
                select="(local:root-of(ixsl:get($range, 'startContainer')),
                    local:roots()[ixsl:call($range, 'intersectsNode', [ . ])])[1]"/>
            <xsl:variable name="all" as="element()*" select="$region/*[not(@data-role)]"/>
            <xsl:if test="exists($all)">
                <xsl:variable name="work" select="ixsl:call($range, 'cloneRange', [])"/>
                <!-- clamp boundaries that lie outside the region (page content,
                     another region) to the region's extremes -->
                <xsl:if test="not(local:root-of(ixsl:get($work, 'startContainer')) is $region)">
                    <xsl:sequence select="ixsl:call($work, 'setStartBefore', [ $all[1] ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:if>
                <xsl:if test="not(local:root-of(ixsl:get($work, 'endContainer')) is $region)">
                    <xsl:sequence select="ixsl:call($work, 'setEndAfter', [ $all[last()] ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:if>
                <!-- a sweep can land a boundary inside chrome: the handle is not
                     content, move the boundary out of the ephemeral subtree -->
                <xsl:for-each select="(ixsl:get($work, 'startContainer')/ancestor-or-self::*[@data-role])[1]">
                    <xsl:sequence select="ixsl:call($work, 'setStartAfter', [ . ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>
                <xsl:for-each select="(ixsl:get($work, 'endContainer')/ancestor-or-self::*[@data-role])[1]">
                    <xsl:sequence select="ixsl:call($work, 'setEndBefore', [ . ])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:for-each>

                <xsl:variable name="blocks" as="element()*" select="$all[ixsl:call($work, 'intersectsNode', [ . ])]"/>
                <xsl:if test="exists($blocks) and not(ixsl:get($work, 'collapsed'))">
                    <!-- boundary hosts (a partial edge is an edge with a boundary
                         host); clamped boundaries sit at region level - no host -->
                    <xsl:variable name="start-host" as="element()?"
                        select="local:host-of(ixsl:get($work, 'startContainer'))[local:root-of(.) is $region]"/>
                    <xsl:variable name="end-host" as="element()?"
                        select="local:host-of(ixsl:get($work, 'endContainer'))[local:root-of(.) is $region]"/>
                    <!-- only the two edge blocks can be partially covered -->
                    <xsl:variable name="head-block" as="element()?" select="$blocks[1][not(local:covered-by(., $work))]"/>
                    <xsl:variable name="tail-block" as="element()?" select="$blocks[last()][not(local:covered-by(., $work))]"/>
                    <xsl:variable name="partial-blocks" as="element()*" select="$head-block | $tail-block"/>
                    <!-- composites holding a range boundary: their structure is
                         never ripped (composites are hard boundaries - B3/B4) -->
                    <xsl:variable name="partial-composites" as="element()*"
                        select="$partial-blocks/descendant-or-self::*[self::table or self::figure]
                            [ixsl:call($work, 'intersectsNode', [ . ])][not(local:covered-by(., $work))]"/>
                    <!-- removals: covered blocks whole, plus the maximal covered
                         fragments of the edge blocks - except grid parts of a
                         boundary-holding composite (rows, cells, captions, the
                         figure image), which survive with their content cleared -->
                    <xsl:variable name="removals" as="element()*" select="
                        $blocks[local:covered-by(., $work)]
                        | $partial-blocks/descendant::*
                            [not(ancestor-or-self::*[@data-role])]
                            [not((self::tbody or self::thead or self::tfoot or self::tr
                                or self::td or self::th or self::caption or self::figcaption or self::img)
                                and exists(ancestor::*[self::table or self::figure]))]
                            [local:covered-by(., $work)]
                            [not(local:covered-by(.., $work))]"/>
                    <!-- covered cells of a boundary-holding composite: cleared, kept -->
                    <xsl:variable name="clears" as="element()*" select="
                        $partial-blocks/descendant::*[self::td or self::th or self::caption or self::figcaption]
                            [exists(ancestor::*[self::table or self::figure])]
                            [local:covered-by(., $work)]
                            [not(local:covered-by((ancestor::*[self::table or self::figure])[last()], $work))]"/>
                    <!-- flow containers of the edge blocks touched by the range:
                         after the removals they may have lost their last block -->
                    <xsl:variable name="collapse-candidates" as="element()*" select="
                        $partial-blocks/descendant::*[cm:flow(local-name(.))][not(self::figure)]
                            [not(@contenteditable = 'true')]
                            [ixsl:call($work, 'intersectsNode', [ . ])]"/>
                    <!-- caret fallbacks for a fully-covered sweep: the untouched
                         neighbors of the swept range -->
                    <xsl:variable name="next-block" as="element()?" select="$blocks[last()]/following-sibling::*[not(@data-role)][1]"/>
                    <xsl:variable name="prev-block" as="element()?" select="$blocks[1]/preceding-sibling::*[not(@data-role)][1]"/>
                    <!-- remnants merge (Google Docs) only between plain text hosts:
                         never across a composite boundary, never with pre (B6) -->
                    <xsl:variable name="merge" as="xs:boolean" select="exists($start-host) and exists($end-host)
                        and not($start-host is $end-host)
                        and empty($start-host/ancestor::* intersect $partial-composites)
                        and empty($end-host/ancestor::* intersect $partial-composites)
                        and empty(($start-host, $end-host)/self::pre)"/>
                    <!-- sub-ranges for the partial edge hosts, cloned before any
                         mutation (a range scoped to one host cannot escape it) -->
                    <xsl:variable name="head-sub" select="if (exists($start-host)) then ixsl:call($work, 'cloneRange', []) else ()"/>
                    <xsl:for-each select="$start-host">
                        <xsl:sequence select="ixsl:call($head-sub, 'setEnd', [ ., xs:integer(ixsl:get(., 'childNodes.length')) ])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>
                    <xsl:variable name="tail-sub" select="if (exists($end-host)) then ixsl:call($work, 'cloneRange', []) else ()"/>
                    <xsl:for-each select="$end-host">
                        <xsl:sequence select="ixsl:call($tail-sub, 'setStart', [ ., 0 ])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>

                    <!-- mutate: one region-keyed history entry, snapshot first -->
                    <xsl:call-template name="local:push-undo">
                        <xsl:with-param name="root" select="$region"/>
                    </xsl:call-template>
                    <xsl:for-each select="$head-sub, $tail-sub">
                        <xsl:sequence select="ixsl:call(., 'deleteContents', [])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>
                    <xsl:for-each select="$clears">
                        <xsl:call-template name="local:clear-host">
                            <xsl:with-param name="host" select="."/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <xsl:for-each select="$removals">
                        <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
                    </xsl:for-each>
                    <!-- the seam: the first text node of the tail remnant, captured
                         before the merge moves it (the reference rides through the
                         move and any container collapse - B4c) -->
                    <xsl:variable name="seam-text" as="text()?"
                        select="($end-host//text()[not(ancestor::*[@data-role])])[1]"/>
                    <xsl:if test="$merge">
                        <xsl:call-template name="local:merge-into-previous">
                            <xsl:with-param name="host" select="$end-host"/>
                            <xsl:with-param name="prev" select="$start-host"/>
                        </xsl:call-template>
                    </xsl:if>
                    <!-- structural containers emptied by the deletion or the merge -->
                    <xsl:for-each select="($head-block, $tail-block)[exists(local:root-of(.))]">
                        <xsl:call-template name="local:prune-husks">
                            <xsl:with-param name="scope" select="."/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <!-- flow containers that lost their last block revert to text hosts -->
                    <xsl:for-each select="$collapse-candidates[exists(local:root-of(.))]">
                        <xsl:call-template name="local:collapse-container">
                            <xsl:with-param name="container" select="."/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <xsl:for-each select="($start-host, $end-host)[exists(local:root-of(.))][@contenteditable = 'true']">
                        <xsl:call-template name="local:ensure-placeholder">
                            <xsl:with-param name="host" select="."/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <!-- a boundary at a block's very edge can sweep the handle away:
                         re-inject (idempotent, top-level only) -->
                    <xsl:for-each select="$region/*[not(@data-role)]">
                        <xsl:call-template name="local:inject-chrome">
                            <xsl:with-param name="block" select="."/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <ixsl:set-property name="activeBlock" select="()" object="local:editor-state()"/>
                    <xsl:choose>
                        <!-- everything went: reseed so the region can hold a caret -->
                        <xsl:when test="empty($region/*[not(@data-role)])">
                            <xsl:call-template name="local:seed-region">
                                <xsl:with-param name="region" select="$region"/>
                            </xsl:call-template>
                        </xsl:when>
                        <xsl:when test="$merge and exists($seam-text) and exists(local:host-of($seam-text))">
                            <xsl:call-template name="local:focus-caret">
                                <xsl:with-param name="node" select="$seam-text"/>
                                <xsl:with-param name="offset" select="0"/>
                            </xsl:call-template>
                        </xsl:when>
                        <xsl:when test="exists(local:last-host-in($head-block[exists(local:root-of(.))]))">
                            <xsl:for-each select="local:last-host-in($head-block)">
                                <xsl:call-template name="local:focus-caret">
                                    <xsl:with-param name="node" select="."/>
                                    <xsl:with-param name="offset"
                                        select="count(node()) - count(node()[last()][self::br])"/>
                                </xsl:call-template>
                            </xsl:for-each>
                        </xsl:when>
                        <xsl:when test="exists(local:first-host-in($tail-block[exists(local:root-of(.))]))">
                            <xsl:for-each select="local:first-host-in($tail-block)">
                                <xsl:call-template name="local:focus-caret">
                                    <xsl:with-param name="node" select="."/>
                                    <xsl:with-param name="offset" select="local:chrome-count(.)"/>
                                </xsl:call-template>
                            </xsl:for-each>
                        </xsl:when>
                        <xsl:when test="exists(local:first-host-in($next-block))">
                            <xsl:for-each select="local:first-host-in($next-block)">
                                <xsl:call-template name="local:focus-caret">
                                    <xsl:with-param name="node" select="."/>
                                    <xsl:with-param name="offset" select="local:chrome-count(.)"/>
                                </xsl:call-template>
                            </xsl:for-each>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:for-each select="local:last-host-in($prev-block)">
                                <xsl:call-template name="local:focus-caret">
                                    <xsl:with-param name="node" select="."/>
                                    <xsl:with-param name="offset"
                                        select="count(node()) - count(node()[last()][self::br])"/>
                                </xsl:call-template>
                            </xsl:for-each>
                        </xsl:otherwise>
                    </xsl:choose>
                    <xsl:call-template name="local:after-mutation"/>
                </xsl:if>
            </xsl:if>
        </xsl:if>
    </xsl:template>

    <!-- ................................ cleanup helpers ................................ -->

    <!-- empty a covered cell keeping the grid: content out, then a flow cell
         reverts to a text host (collapse handles editability and placeholder),
         an inline-only host (caption) just gets its placeholder back -->
    <xsl:template name="local:clear-host">
        <xsl:param name="host" as="element()"/>
        <xsl:for-each select="1 to xs:integer(ixsl:get($host, 'childNodes.length'))">
            <xsl:sequence select="ixsl:call($host, 'removeChild', [ ixsl:get($host, 'firstChild') ])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>
        <xsl:choose>
            <xsl:when test="cm:flow(local-name($host))">
                <xsl:call-template name="local:collapse-container">
                    <xsl:with-param name="container" select="$host"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="local:ensure-placeholder">
                    <xsl:with-param name="host" select="$host"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- remove structural containers emptied by a deletion (a list whose items
         all went, a quote whose blocks all went), innermost first, re-probing
         after each removal so emptiness cascades upward -->
    <xsl:template name="local:prune-husks">
        <xsl:param name="scope" as="element()"/>
        <xsl:variable name="husk" as="element()?" select="($scope/descendant-or-self::*
            [self::ul or self::ol or self::dl or self::blockquote]
            [empty(*[not(@data-role)])][not(text()[normalize-space()])])[last()]"/>
        <xsl:for-each select="$husk">
            <xsl:sequence select="ixsl:call(., 'remove', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:if test="not(. is $scope)">
                <xsl:call-template name="local:prune-husks">
                    <xsl:with-param name="scope" select="$scope"/>
                </xsl:call-template>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <!-- an emptied region cannot hold a caret: seed a fresh paragraph host (the
         empty-blockquote idiom with the region as explicit parent) -->
    <xsl:template name="local:seed-region">
        <xsl:param name="region" as="element()"/>
        <xsl:variable name="p" as="element()" select="local:element('p')"/>
        <xsl:sequence select="ixsl:call($p, 'appendChild', [ local:element('br') ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-attribute name="contenteditable" select="'true'" object="$p"/>
        <xsl:sequence select="ixsl:call($region, 'appendChild', [ $p ])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:call-template name="local:inject-chrome">
            <xsl:with-param name="block" select="$p"/>
        </xsl:call-template>
        <xsl:call-template name="local:focus-caret">
            <xsl:with-param name="node" select="$p"/>
            <xsl:with-param name="offset" select="local:chrome-count($p)"/>
        </xsl:call-template>
    </xsl:template>

</xsl:stylesheet>
