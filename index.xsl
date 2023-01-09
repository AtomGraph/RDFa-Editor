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

    <xsl:include href="RDFa2RDFXML.xsl.c14n"/>

    <xsl:template name="main"/>

    <xsl:template match="p[ixsl:get(., 'contentEditable') = 'true']" mode="ixsl:ondblclick">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:sequence select="ixsl:call(ixsl:event(), 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:variable name="selection" select="ixsl:call(ixsl:window(), 'getSelection', [])" as="item()"/>
        <xsl:message>exists($selection): <xsl:value-of select="exists($selection)"/></xsl:message>
        <xsl:variable name="range" select="ixsl:call($selection, 'getRangeAt', [ 0 ])" as="item()"/>
        <xsl:message>ixsl:get($range, 'collapsed'): <xsl:value-of select="ixsl:get($range, 'collapsed')"/></xsl:message>

        <ixsl:set-property name="range" select="$range" object="ixsl:window()"/>

        <xsl:if test="not(id('overlay', ixsl:page()))">
            <xsl:for-each select="ixsl:page()//body">
                <xsl:result-document href="?." method="ixsl:append-content">
                    <div id="overlay" style="background-color: white; border: 1px solid black;">
                        <form>
                            <fieldset>
                                <button type="button" class="bold-action" style="font-style: bold">B</button>
                                <button type="button" class="italic-action" style="font-style: italic">I</button>
                            </fieldset>
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

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="event" select="$event"/>
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'block'"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template match="p[ixsl:get(., 'contentEditable') = 'true']" mode="ixsl:onfocusout">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:variable name="target" select="ixsl:get(ixsl:event(), 'target')" as="element()"/>

        <xsl:if test="not($target/@id = 'overlay')">
            <xsl:call-template name="show-overlay">
                <xsl:with-param name="event" select="$event"/>
                <xsl:with-param name="overlay-id" select="'overlay'"/>
                <xsl:with-param name="display" select="'none'"/>
            </xsl:call-template>
        </xsl:if>
    </xsl:template>

    <xsl:template match="button[tokenize(@class, ' ') = 'spo-action']" mode="ixsl:onclick">
        <xsl:variable name="subject" select="ixsl:get(ancestor::form//input[@name = 'subject'], 'value')" as="xs:anyURI"/>
        <xsl:variable name="property" select="ixsl:get(ancestor::form//select[@name = 'property'], 'value')" as="xs:anyURI"/>
        <xsl:variable name="object" select="ixsl:get(ancestor::form//input[@name = 'object'], 'value')" as="xs:string"/>

        <xsl:message>Subject: <xsl:copy-of select="$subject"/></xsl:message>
        <xsl:message>Property: <xsl:value-of select="$property"/></xsl:message>
        <xsl:message>Object: <xsl:value-of select="$object"/></xsl:message>

        <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'range')"/>
        <xsl:variable name="span" select="ixsl:call(ixsl:page(), 'createElement', [ 'span' ])" as="element()"/>
        <xsl:sequence select="ixsl:call($range, 'surroundContents', [ $span ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-attribute name="id" select="generate-id($span)" object="$span"/>

        <xsl:for-each select="$span">
            <xsl:if test="$subject">
                <ixsl:set-attribute name="about" select="$subject"/>
            </xsl:if>
            <ixsl:set-attribute name="property" select="$property"/>
            <ixsl:set-attribute name="resource" select="$object"/>
        </xsl:for-each>

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'none'"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template match="button[tokenize(@class, ' ') = 'bold-action']" mode="ixsl:onclick">
        <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'range')"/>
        <xsl:variable name="span" select="ixsl:call(ixsl:page(), 'createElement', [ 'span' ])" as="element()"/>
        <xsl:sequence select="ixsl:call($range, 'surroundContents', [ $span ])[current-date() lt xs:date('2000-01-01')]"/>
        <ixsl:set-attribute name="id" select="generate-id($span)" object="$span"/>

        <xsl:for-each select="$span">
            <ixsl:set-style name="font-weight" select="'bold'"/>
        </xsl:for-each>

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'none'"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template name="show-overlay">
        <xsl:param name="event"/>
        <xsl:param name="overlay-id" as="xs:string"/>
        <xsl:param name="display" as="xs:string"/>

        <xsl:for-each select="id($overlay-id, ixsl:page())">
            <ixsl:set-style name="display" select="$display" object="."/>
            <xsl:if test="not($display = 'none')">
                <ixsl:set-style name="position" select="'absolute'" object="."/>
                <ixsl:set-style name="top" select="ixsl:get($event, 'clientY') || 'px'" object="."/>
                <ixsl:set-style name="left" select="ixsl:get($event, 'clientX') || 'px'" object="."/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="button[@id = 'parse-rdf']" mode="ixsl:onclick">
        <xsl:message>
            <xsl:apply-templates select="../preceding-sibling::p" mode="rdf2rdfxml"/>
        </xsl:message>
    </xsl:template>

</xsl:stylesheet>