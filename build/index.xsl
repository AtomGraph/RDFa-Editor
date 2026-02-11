<xsl:stylesheet xmlns="http://www.w3.org/1999/xhtml" xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT" xmlns:prop="http://saxonica.com/ns/html-property" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#" xmlns:style="http://saxonica.com/ns/html-style-property" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="xs prop" extension-element-prefixes="ixsl" version="2.0" xpath-default-namespace="http://www.w3.org/1999/xhtml">

    <xsl:include href="RDFa2RDFXML.xsl"></xsl:include>

    <xsl:template name="main"></xsl:template>

    <xsl:template match="p[ixsl:get(., 'contentEditable') = 'true']" mode="ixsl:oncontextmenu">
        <xsl:variable name="event" select="ixsl:event()"></xsl:variable>
        <xsl:sequence select="ixsl:call(ixsl:event(), 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"></xsl:sequence>
        <xsl:variable name="selection" select="ixsl:call(ixsl:window(), 'getSelection', [] )"></xsl:variable>
        <xsl:variable name="range" select="ixsl:call($selection, 'getRangeAt', [ 0 ])"></xsl:variable>

        <ixsl:set-property name="range" object="ixsl:window()" select="$range"></ixsl:set-property>

		<xsl:if test="not(id('overlay', ixsl:page()))">
			<xsl:for-each select="ixsl:page()//body">
				<xsl:result-document href="?." method="ixsl:append-content">
					<div id="overlay" style="background-color: white; border: 1px solid black;">
						<form>
							<fieldset>
								<label>Subject</label>
								<input name="subject" type="text"></input>
							</fieldset>
							<fieldset>
								<label>Property</label>
								<!-- <input type="text" name="property"/> -->
								<select name="property">
									<xsl:for-each select="document('vocabs/foaf.rdf')/rdf:RDF/rdf:Property">
										<xsl:sort select="@rdfs:label"></xsl:sort>

										<option value="{@rdf:about}">
											<xsl:value-of select="@rdfs:label"></xsl:value-of>
										</option>
									</xsl:for-each>
								</select>
							</fieldset>
							<fieldset>
								<label>Object</label>
								<input name="object" type="text"></input>
							</fieldset>
							<p>
								<button class="spo-action" type="button">OK</button>
							</p>
						</form>
					</div>
				</xsl:result-document>
			</xsl:for-each>
		</xsl:if>

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="event" select="$event"></xsl:with-param>
            <xsl:with-param name="overlay-id" select="'overlay'"></xsl:with-param>
            <xsl:with-param name="display" select="'block'"></xsl:with-param>
        </xsl:call-template>
    </xsl:template>

	<xsl:template match="button[tokenize(@class, ' ') = 'spo-action']" mode="ixsl:onclick">
        <xsl:variable as="xs:anyURI" name="subject" select="ixsl:get(ancestor::form//input[@name = 'subject'], 'value')"></xsl:variable>
        <xsl:variable as="xs:anyURI" name="property" select="ixsl:get(ancestor::form//select[@name = 'property'], 'value')"></xsl:variable>
        <xsl:variable as="xs:string" name="object" select="ixsl:get(ancestor::form//input[@name = 'object'], 'value')"></xsl:variable>

		<xsl:message>Subject: <xsl:copy-of select="$subject"></xsl:copy-of></xsl:message>
		<xsl:message>Property: <xsl:value-of select="$property"></xsl:value-of></xsl:message>
		<xsl:message>Object: <xsl:value-of select="$object"></xsl:value-of></xsl:message>

        <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'range')"></xsl:variable>
        <xsl:variable as="element()" name="span" select="ixsl:call(ixsl:page(), 'createElement', [ 'span' ])"></xsl:variable>
        <xsl:sequence select="ixsl:call($range, 'surroundContents', [ $span ])[current-date() lt xs:date('2000-01-01')]"></xsl:sequence>
        <ixsl:set-attribute name="id" object="$span" select="generate-id($span)"></ixsl:set-attribute>

        <xsl:for-each select="$span">
            <xsl:if test="$subject">
                <ixsl:set-attribute name="about" select="$subject"></ixsl:set-attribute>
            </xsl:if>
            <ixsl:set-attribute name="property" select="$property"></ixsl:set-attribute>
            <ixsl:set-attribute name="resource" select="$object"></ixsl:set-attribute>
        </xsl:for-each>

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="overlay-id" select="'overlay'"></xsl:with-param>
            <xsl:with-param name="display" select="'none'"></xsl:with-param>
        </xsl:call-template>
	</xsl:template>

	<xsl:template name="show-overlay">
		<xsl:param name="event"></xsl:param>
		<xsl:param as="xs:string" name="overlay-id"></xsl:param>
		<xsl:param as="xs:string" name="display"></xsl:param>

		<xsl:for-each select="id($overlay-id, ixsl:page())">
			<ixsl:set-style name="display" object="." select="$display"></ixsl:set-style>
            <xsl:if test="not($display = 'none')">
                <ixsl:set-style name="position" object="." select="'absolute'"></ixsl:set-style>
                <ixsl:set-style name="top" object="." select="ixsl:get($event, 'clientY') || 'px'"></ixsl:set-style>
                <ixsl:set-style name="left" object="." select="ixsl:get($event, 'clientX') || 'px'"></ixsl:set-style>
            </xsl:if>
		</xsl:for-each>
	</xsl:template>

    <xsl:template match="button[@id = 'parse-rdf']" mode="ixsl:onclick">
        <xsl:message>
            <xsl:apply-templates mode="rdf2rdfxml" select="../preceding-sibling::p"></xsl:apply-templates>
        </xsl:message>
    </xsl:template>

</xsl:stylesheet>