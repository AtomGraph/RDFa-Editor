<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:lint="https://w3id.org/atomgraph/rdfa-editor/lint#"
    version="3.0">

<!--
    CLI entry for the RDFa lint suite: one line per issue ('code path message'),
    empty output for a clean fixture. xsl:import (not include) so this module's
    text output method takes import precedence over the extractor's xml one.
-->

    <xsl:import href="../src/RDFa2RDFXML-v3.xsl"/>
    <xsl:import href="../src/content-model.xsl"/>
    <xsl:import href="../src/lint-rdfa.xsl"/>
    <xsl:import href="../src/lint-xhtml.xsl"/>

    <xsl:output method="text" encoding="UTF-8"/>

    <xsl:template name="lint-report">
        <xsl:param name="content" as="element()" select="/*"/>
        <xsl:for-each select="lint:lintable($content) ! (lint:element-issues(.), lint:nesting-issues(.))">
            <xsl:value-of select="@code || ' ' || @path || ' ' || normalize-space(.) || '&#10;'"/>
        </xsl:for-each>
    </xsl:template>

</xsl:stylesheet>
