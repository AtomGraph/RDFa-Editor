<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xsl:stylesheet [
    <!ENTITY rdf        "http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <!ENTITY rdfs       "http://www.w3.org/2000/01/rdf-schema#">
]>

<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xhtml="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:prop="http://saxonica.com/ns/html-property"
xmlns:style="http://saxonica.com/ns/html-style-property"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:rdf="&rdf;"
xmlns:rdfs="&rdfs;"
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
		<!--
        <xsl:for-each select="$span">
            <ixsl:set-attribute name="about" select="concat('#', generate-id())"/>
            <ixsl:set-attribute name="content" select="ixsl:call(ixsl:window(), 'prompt', 'Name?')"/>
            <ixsl:set-attribute name="property" select="'schema:name'"/>
        </xsl:for-each>
		-->

        <xsl:message>
            <!-- a workaround for https://sourceforge.net/p/saxon/mailman/message/35429409/ -->
            <xsl:value-of select="ixsl:call($range, 'surroundContents', $span)"/>
        </xsl:message>

		<xsl:if test="not(id('overlay', ixsl:page()))">
			<xsl:for-each select="ixsl:page()//body">
				<xsl:result-document href="?select=." method="ixsl:append-content">
					<div id="overlay" style="background-color: white; border: 1px solid black;">
						<form>
							<fieldset>
								<label>Subject</label>
								<input type="text" name="subject"/>
							</fieldset>
							<fieldset>
								<label>Property</label>
								<!-- <input type="text" name="property"/> -->
								<select name="property">
									<xsl:for-each select="document('vocabs/foaf.rdf')/rdf:RDF/rdf:Property">
										<xsl:sort select="@rdfs:label"/>

										<option value="{@rdf:about}">
											<xsl:value-of select="@rdfs:label"/>
										</option>
									</xsl:for-each>
								</select>
							</fieldset>
							<fieldset>
								<label>Object</label>
								<input type="text" name="object"/>
							</fieldset>
							<p>
								<button type="button" class="spo-action">OK</button>
							</p>
						</form>
					</div>
				</xsl:result-document>
			</xsl:for-each>
		</xsl:if>

		<ixsl:schedule-action wait="0">
			<xsl:call-template name="show-overlay">
				<xsl:with-param name="selected" select="$span"/>
				<xsl:with-param name="overlay-id" select="'overlay'"/>
			</xsl:call-template>
		</ixsl:schedule-action>
    </xsl:template>

	<xsl:template match="button[tokenize(@class, ' ') = 'spo-action']" mode="ixsl:onclick">
		<!-- <xsl:for-each select="ancestor::div[@id = 'overlay']">
			<ixsl:set-attribute name="style:display" select="'none'"/>
		</xsl:for-each> -->

		<xsl:message>Subject: <xsl:copy-of select="ancestor::form//input[@name = 'subject']/@prop:value"/></xsl:message>
		<xsl:message>Property: <xsl:value-of select="ancestor::form//select[@name = 'property']/@prop:value"/></xsl:message>
		<xsl:message>Object: <xsl:value-of select="ancestor::form//input[@name = 'object']/@prop:value"/></xsl:message>
	</xsl:template>

	<xsl:template name="show-overlay">
		<xsl:param name="selected" as="element()"/>
		<xsl:param name="overlay-id" as="xs:string"/>

		<xsl:for-each select="id($overlay-id, ixsl:page())">
			<ixsl:set-attribute name="style:display" select="'block'"/>
			<ixsl:set-attribute name="style:position" select="'absolute'"/>
			<ixsl:set-attribute name="style:top" select="concat($selected/@prop:offsetTop + $selected/@prop:offsetHeight, 'px')"/>
			<ixsl:set-attribute name="style:left" select="concat($selected/@prop:offsetLeft, 'px')"/>
		</xsl:for-each>
	</xsl:template>

</xsl:stylesheet>