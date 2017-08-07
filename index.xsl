<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xhtml="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:prop="http://saxonica.com/ns/html-property"
xmlns:style="http://saxonica.com/ns/html-style-property"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
exclude-result-prefixes="xs prop"
extension-element-prefixes="ixsl"
version="2.0"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
>

    <xsl:template name="main"/>

    <xsl:template match="*" mode="ixsl:ondblclick">
        <xsl:variable name="selection" select="ixsl:call(ixsl:window(), 'getSelection')"/>
		<xsl:message>Selection: <xsl:copy-of select="$selection"/></xsl:message>

        <xsl:variable name="range" select="ixsl:call($selection, 'getRangeAt', 0)"/>
		<xsl:message>Range: <xsl:copy-of select="$range"/></xsl:message>

		<xsl:variable name="span" select="ixsl:call(ixsl:page(), 'createElement', 'span')" as="element()"/>
		<xsl:for-each select="$span">
			<ixsl:set-attribute name="about" select="concat('#', generate-id())"/>
			<ixsl:set-attribute name="content" select="ixsl:call(ixsl:window(), 'prompt', 'Name?')"/>
			<ixsl:set-attribute name="property" select="'schema:name'"/>
		</xsl:for-each>

		<xsl:message>
			<!-- a workaround for https://sourceforge.net/p/saxon/mailman/message/35429409/ -->
			<xsl:value-of select="ixsl:call($range, 'surroundContents', $span)"/>
		</xsl:message>
    </xsl:template>
    
</xsl:stylesheet>