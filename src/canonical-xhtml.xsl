<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:cm="urn:rdfa-editor:content-model"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
exclude-result-prefixes="#all"
version="3.0">

<!--
    Canonical XHTML+RDFa serialization form. Pure XSLT 3.0 - no ixsl: dependencies,
    so it runs headless for testing (see tests/run-tests.sh), but NOT standalone-
    compilable: it consults content-model.xsl (cm:*) - include/import both together
    (index.xsl does; the test driver is tests/canonical-driver.xsl).

    Two passes in a fixed order:
    1. mode="canonical"     strips editing ephemera per the LDH v6 convention
                            (everything carrying @data-role is removable by
                            construction), sanitizes, and normalizes browser mess.
                            Nesting analysis must never see chrome, so this runs first.
    2. mode="cm-normalize"  coerces the result to the XHTML Strict content model
                            (blockquote is block-only, p is inline-only, ul holds
                            only li, ...), always RDFa-preserving. The load-init
                            path (edit.xsl) runs this pass ALONE on host content.

    The entry template finally applies the editor contract - region children are
    blocks - which is deliberately not part of the DTD transcription.
    RDFa attributes and pre whitespace are never touched; text is never reflowed.
-->

    <!-- serialization is the caller's job (view-source serialize(), test -o output);
         no xsl:output here - it would conflict with the including stylesheet's -->
    <xsl:mode name="canonical" on-no-match="shallow-copy"/>
    <xsl:mode name="cm-normalize" on-no-match="shallow-copy"/>

    <xsl:template name="canonical-xhtml">
        <xsl:param name="content" as="element()" select="/*"/>
        <xsl:variable name="pass1" as="node()*">
            <xsl:apply-templates select="$content" mode="canonical"/>
        </xsl:variable>
        <xsl:for-each select="$pass1/self::*">
            <xsl:copy>
                <xsl:copy-of select="@*"/>
                <!-- editor contract (not the DTD's rule): region children are blocks -->
                <xsl:sequence select="cm:wrap-inline-runs(cm:normalize(node()), 'p')"/>
            </xsl:copy>
        </xsl:for-each>
    </xsl:template>

    <!-- -im:canonical entry for CLI fallback -->
    <xsl:template match="/" mode="canonical">
        <xsl:call-template name="canonical-xhtml"/>
    </xsl:template>

    <!-- ................ shared coercion primitives ................ -->

    <xsl:function name="cm:normalize" as="node()*">
        <xsl:param name="nodes" as="node()*"/>
        <xsl:apply-templates select="$nodes" mode="cm-normalize"/>
    </xsl:function>

    <!-- block/@data-role/unknown children pass through (the wrapper is inline-only,
         so only known-inline content may be pulled into it - an unknown element like
         an RDFa-bearing article stays bare and lint reports it); adjacent runs of
         anything else with substance (an element or non-whitespace text) get wrapped;
         whitespace-only runs between blocks stay bare. The one grouping axis shared
         by the entry coercion, N2 and the paste handler (edit.xsl) -->
    <xsl:function name="cm:wrap-inline-runs" as="node()*">
        <xsl:param name="kids" as="node()*"/>
        <xsl:param name="wrapper" as="xs:string"/>
        <xsl:for-each-group select="$kids"
                group-adjacent="boolean(self::*[cm:block(local-name(.)) or @data-role
                    or not(cm:known(local-name(.)))])">
            <xsl:choose>
                <xsl:when test="current-grouping-key()">
                    <xsl:sequence select="current-group()"/>
                </xsl:when>
                <xsl:when test="exists(current-group()[self::* or self::text()[normalize-space()]])">
                    <xsl:element name="{$wrapper}">
                        <xsl:sequence select="current-group()"/>
                    </xsl:element>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="current-group()"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each-group>
    </xsl:function>

    <!-- element-only containers (ul, dl, tr): allowed/@data-role children pass,
         adjacent runs of anything else get wrapped in the container's item kind -->
    <xsl:function name="cm:coerce-children" as="node()*">
        <xsl:param name="kids" as="node()*"/>
        <xsl:param name="allowed" as="xs:string*"/>
        <xsl:param name="wrapper" as="xs:string"/>
        <xsl:for-each-group select="$kids"
                group-adjacent="boolean(self::*[local-name() = $allowed or @data-role])">
            <xsl:choose>
                <xsl:when test="current-grouping-key()">
                    <xsl:sequence select="current-group()"/>
                </xsl:when>
                <xsl:when test="exists(current-group()[self::* or self::text()[normalize-space()]])">
                    <xsl:element name="{$wrapper}">
                        <xsl:sequence select="current-group()"/>
                    </xsl:element>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="current-group()"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each-group>
    </xsl:function>

    <!-- ................ pass 1: mode="canonical" ................ -->

    <!-- C1: everything carrying @data-role is ephemeral (chrome, rendering) -->
    <xsl:template match="*[@data-role]" mode="canonical" priority="2"/>

    <!-- S1: active/embedding elements never survive into stored content (the
         canonical form is the sanitization boundary for multi-user content) -->
    <xsl:template match="script | style | iframe | object | embed | applet
        | form | input | button | select | textarea | link | meta | base" mode="canonical" priority="3"/>

    <!-- S1b: comments and processing instructions are noise (Word/HTML paste junk) -->
    <xsl:template match="comment() | processing-instruction()" mode="canonical"/>

    <!-- S2: event-handler attributes are always stripped -->
    <xsl:template match="@*[matches(local-name(), '^on', 'i')]" mode="canonical"/>

    <!-- S3: scripting/data URL schemes are dropped from link and media targets
         (the attribute, not the element); data:image/* remains valid in @src -->
    <xsl:template match="@href[matches(normalize-space(.), '^(javascript|vbscript|data):', 'i')]
        | @src[matches(normalize-space(.), '^(javascript|vbscript):', 'i')]
        | @src[matches(normalize-space(.), '^data:', 'i')][not(matches(normalize-space(.), '^data:image/', 'i'))]"
        mode="canonical"/>

    <!-- C2: editing-state and styling-hook attributes never serialize (tabindex is
         injected to make block images focusable navigation islands) -->
    <xsl:template match="@contenteditable | @draggable | @class | @id | @style | @tabindex
        | @*[starts-with(name(), 'aria-')] | @*[starts-with(name(), 'data-')]" mode="canonical"/>

    <!-- C3/C4: presentational aliases to their semantic elements -->
    <xsl:template match="b" mode="canonical">
        <strong>
            <xsl:apply-templates select="@* | node()" mode="#current"/>
        </strong>
    </xsl:template>

    <xsl:template match="i" mode="canonical">
        <em>
            <xsl:apply-templates select="@* | node()" mode="#current"/>
        </em>
    </xsl:template>

    <!-- C5: legacy presentational wrappers are dropped, content kept -->
    <xsl:template match="font | u" mode="canonical">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <!-- C6: a span left without RDFa or language attributes carries no meaning -->
    <xsl:template match="span[not(@property or @about or @typeof or @resource or @content
            or @datatype or @lang or @xml:lang)]" mode="canonical">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <!-- C7a: browser-generated attributeless div with inline content becomes a
         paragraph; RDFa-bearing divs pass -->
    <xsl:template match="div[not(@property or @about or @typeof or @resource)]
            [empty(*[cm:block(local-name(.))])]" mode="canonical">
        <p>
            <xsl:apply-templates select="@* | node()" mode="#current"/>
        </p>
    </xsl:template>

    <!-- C7b: an attributeless div holding blocks is a semantics-free grouping
         wrapper (p may not contain blocks) - unwrap to its children; stray inline
         residue is re-coerced by pass 2 in the parent's context -->
    <xsl:template match="div[not(@property or @about or @typeof or @resource)]
            [exists(*[cm:block(local-name(.))])]" mode="canonical">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <!-- C11: the editing-DOM run wrapper (edit.xsl wraps stray inline runs of mixed
         flow containers in p.rdfa-editor-run so they stay editable) unwraps, so
         <li>text<ul>...</ul></li> round-trips byte-identical. An annotated wrapper
         has become real content and stays a p -->
    <xsl:template match="p[contains-token(@class, 'rdfa-editor-run')]
            [not(@property or @about or @typeof or @resource or @content or @datatype)]"
        mode="canonical" priority="1">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <!-- C12: HTML5 sectioning wrappers have no XHTML Strict equivalent - unwrap
         clipboard/host wrappers, keep RDFa-bearing ones (dropping them would lose
         triples; lint reports them as unknown-element) -->
    <xsl:template match="(section | article | main | aside | header | footer | nav | hgroup)
            [not(@property or @about or @typeof or @resource)]" mode="canonical">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <!-- C8: empty non-RDFa inline elements are junk; RDFa-bearing empties
         (hidden <span property resource/> definitions) are kept by C6's predicates -->
    <xsl:template match="(strong | em | a | code)[not(normalize-space(.))][not(.//img)]
            [not(@property or @about or @typeof or @resource or @content)]" mode="canonical" priority="1"/>

    <!-- C10: line structure inside pre is text, not markup -->
    <xsl:template match="br[ancestor::pre]" mode="canonical" priority="1">
        <xsl:text>&#10;</xsl:text>
    </xsl:template>

    <!-- C9: a trailing <br> is a caret placeholder, not content -->
    <xsl:template match="br[not(following-sibling::node()[self::* or self::text()[normalize-space()]])]"
        mode="canonical"/>

    <!-- ................ pass 2: mode="cm-normalize" ................ -->

    <!-- N0: ephemera are placed by the editor, not judged by the DTD (the load-init
         path runs this pass alone, where chrome and rendering subtrees still exist) -->
    <xsl:template match="*[@data-role]" mode="cm-normalize" priority="2">
        <xsl:copy-of select="."/>
    </xsl:template>

    <!-- N1: blocks inside an inline-only element (p, h1-h6, dt, caption, pre, inlines).
         An RDFa-bearing parent stays whole - its block children demote to span with
         all attributes kept, so the extracted literal and triples are unchanged. A
         plain parent splits around its block children; inline runs keep a shell
         copying the name and language; whitespace-only residue between blocks drops -->
    <xsl:template match="*[cm:inline-only(local-name(.))][*[cm:block(local-name(.))]]" mode="cm-normalize">
        <xsl:variable name="name" as="xs:string" select="local-name(.)"/>
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test="@property or @about or @typeof or @resource or @content or @datatype">
                <xsl:copy>
                    <xsl:copy-of select="@*"/>
                    <xsl:for-each select="$kids">
                        <xsl:choose>
                            <xsl:when test="self::*[cm:block(local-name(.))]">
                                <span>
                                    <xsl:copy-of select="@* | node()"/>
                                </span>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:copy-of select="."/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:for-each>
                </xsl:copy>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="lang" as="attribute()*" select="@lang | @xml:lang"/>
                <xsl:for-each-group select="$kids"
                        group-adjacent="boolean(self::*[cm:block(local-name(.))])">
                    <xsl:choose>
                        <xsl:when test="current-grouping-key()">
                            <xsl:sequence select="current-group()"/>
                        </xsl:when>
                        <xsl:when test="exists(current-group()[self::* or self::text()[normalize-space()]])">
                            <xsl:element name="{$name}">
                                <xsl:copy-of select="$lang"/>
                                <xsl:sequence select="current-group()"/>
                            </xsl:element>
                        </xsl:when>
                        <xsl:otherwise/>
                    </xsl:choose>
                </xsl:for-each-group>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- N2: blockquote (and noscript) is block-only per Strict - stray text/inline
         runs become paragraphs; RDFa attributes on the container are untouched -->
    <xsl:template match="blockquote | noscript" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="cm:wrap-inline-runs($kids, 'p')"/>
        </xsl:copy>
    </xsl:template>

    <!-- N3: ul/ol hold only li - stray children become item content (li is flow) -->
    <xsl:template match="ul | ol" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="cm:coerce-children($kids, 'li', 'li')"/>
        </xsl:copy>
    </xsl:template>

    <!-- N4: dl holds only dt/dd - strays become dd content (dd is flow, dt is not) -->
    <xsl:template match="dl" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="cm:coerce-children($kids, ('dt', 'dd'), 'dd')"/>
        </xsl:copy>
    </xsl:template>

    <!-- N5: tr holds only th/td - strays become cell content (td is flow) -->
    <xsl:template match="tr" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="cm:coerce-children($kids, ('th', 'td'), 'td')"/>
        </xsl:copy>
    </xsl:template>

    <!-- N5b: table sections hold only tr - a stray cell run keeps its cells in a
         fresh row; anything else becomes a one-cell row -->
    <xsl:template match="thead | tbody | tfoot" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each-group select="$kids"
                    group-adjacent="boolean(self::*[local-name() = 'tr' or @data-role])">
                <xsl:choose>
                    <xsl:when test="current-grouping-key()">
                        <xsl:sequence select="current-group()"/>
                    </xsl:when>
                    <xsl:when test="exists(current-group()[self::* or self::text()[normalize-space()]])">
                        <tr>
                            <xsl:choose>
                                <xsl:when test="every $n in current-group()[self::*]
                                        satisfies local-name($n) = ('th', 'td')">
                                    <xsl:sequence select="current-group()"/>
                                </xsl:when>
                                <xsl:otherwise>
                                    <td>
                                        <xsl:sequence select="current-group()"/>
                                    </td>
                                </xsl:otherwise>
                            </xsl:choose>
                        </tr>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:sequence select="current-group()"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:for-each-group>
        </xsl:copy>
    </xsl:template>

    <!-- N6: children a table cannot hold are hoisted before it (mirrors browser
         foster parenting); whitespace and ephemera stay put -->
    <xsl:template match="table" mode="cm-normalize">
        <xsl:variable name="kids" as="node()*">
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:variable>
        <xsl:variable name="valid" as="xs:string*"
            select="'caption', 'col', 'colgroup', 'thead', 'tfoot', 'tbody', 'tr'"/>
        <xsl:sequence select="$kids[(self::*[not(local-name() = $valid)][not(@data-role)])
            or self::text()[normalize-space()]]"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="$kids[self::*[local-name() = $valid or @data-role]
                or self::text()[not(normalize-space())]]"/>
        </xsl:copy>
    </xsl:template>

    <!-- N7: Appendix B pre exclusions, text-preserving: size/position markup
         unwraps, replaced objects fall back to their alternative text -->
    <xsl:template match="(big | small | sub | sup)[ancestor::pre]" mode="cm-normalize" priority="1">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

    <xsl:template match="(img | object)[ancestor::pre]" mode="cm-normalize" priority="1">
        <xsl:value-of select="@alt"/>
    </xsl:template>

    <!-- N8: Appendix B nesting prohibitions - the inner element keeps all its
         attributes (RDFa preserved; a dead @href is harmless) under a valid name -->
    <xsl:template match="a[ancestor::a]" mode="cm-normalize" priority="1">
        <span>
            <xsl:copy-of select="@*"/>
            <xsl:apply-templates select="node()" mode="#current"/>
        </span>
    </xsl:template>

    <xsl:template match="label[ancestor::label]" mode="cm-normalize" priority="1">
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>

</xsl:stylesheet>
