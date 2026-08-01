<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
version="3.0">

<!--
    The demo/dist entry: the core editor layered with the LinkedDataHub blocks
    extension. xsl:import puts the core at LOWER import precedence, so the
    included extension's declarations override it - $object-block-types, the
    per-type mode="rdfae:render-island" templates and the rdfae:render-extra-*
    hook stubs. This is exactly the shape LinkedDataHub's client.xsl uses to
    integrate the editor (docs/ldh/MIGRATION.md par. 10/12): in production,
    client.xsl plays the ldh-blocks.xsl role with its real ldh:RenderRow
    renderers. Core-only consumers compile src/index.xsl instead.
-->

    <xsl:import href="index.xsl"/>
    <xsl:include href="ldh-blocks.xsl"/>

</xsl:stylesheet>
