<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:cm="https://w3id.org/atomgraph/rdfa-editor/content-model#"
    version="3.0">

<!--
    CLI entry for the exclusive-c14n suite: the source document, canonicalized by
    cm:c14n, as text - compared byte-exact against libxml2's exc-c14n output.
-->

    <xsl:import href="../src/content-model.xsl"/>
    <xsl:import href="../src/canonical-xhtml.xsl"/>

    <xsl:output method="text" encoding="UTF-8"/>

    <xsl:template name="c14n">
        <xsl:value-of select="cm:c14n(/)"/>
    </xsl:template>

</xsl:stylesheet>
