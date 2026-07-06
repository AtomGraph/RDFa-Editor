<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
exclude-result-prefixes="#all"
version="3.0">

<!--
    Canonical XHTML+RDFa serialization form. Pure XSLT 3.0 - no ixsl: dependencies,
    so it runs headless via xslt3 for testing (see tests/run-tests.sh).

    Strips editing ephemera per the LDH v6 convention (everything carrying @data-role
    is removable by construction: injected chrome, hydrated rendering output) and
    normalizes browser-generated markup mess. RDFa attributes and pre whitespace are
    never touched; text is never reflowed.
-->

    <!-- serialization is the caller's job (view-source serialize(), test -o output);
         no xsl:output here - it would conflict with the including stylesheet's -->
    <xsl:mode name="canonical" on-no-match="shallow-copy"/>

    <xsl:template name="canonical-xhtml">
        <xsl:param name="content" as="element()" select="/*"/>
        <xsl:apply-templates select="$content" mode="canonical"/>
    </xsl:template>

    <!-- -im:canonical entry for CLI fallback -->
    <xsl:template match="/" mode="canonical">
        <xsl:apply-templates select="*" mode="#current"/>
    </xsl:template>

    <!-- C1: everything carrying @data-role is ephemeral (chrome, rendering) -->
    <xsl:template match="*[@data-role]" mode="canonical" priority="2"/>

    <!-- C2: editing-state and styling-hook attributes never serialize -->
    <xsl:template match="@contenteditable | @draggable | @class | @id | @style
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

    <!-- C7: browser-generated attributeless div becomes a paragraph; RDFa-bearing divs pass -->
    <xsl:template match="div[not(@property or @about or @typeof or @resource)]" mode="canonical">
        <p>
            <xsl:apply-templates select="@* | node()" mode="#current"/>
        </p>
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

</xsl:stylesheet>
