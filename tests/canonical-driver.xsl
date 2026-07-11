<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    version="3.0">

<!--
    CLI entry for the canonical-XHTML suite: canonical-xhtml.xsl consults the
    content model (cm:*), so it is no longer standalone-compilable - this driver
    imports both modules together (mirrors lint-driver.xsl).
-->

    <xsl:import href="../src/content-model.xsl"/>
    <xsl:import href="../src/canonical-xhtml.xsl"/>

    <xsl:output method="xml" indent="no"/>

</xsl:stylesheet>
