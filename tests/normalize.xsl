<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    exclude-result-prefixes="xs rdf"
    version="3.0">

<!--
    Canonicalizes RDF/XML (in the striped rdf:Description subset the extractor emits
    and the expected files are authored in) into a sorted, prefix- and grouping-
    independent triple list, so actual and expected output compare with plain diff.
-->

    <xsl:output method="xml" indent="yes"/>

    <xsl:template match="/rdf:RDF">
        <xsl:variable name="triples" as="element(t)*">
            <xsl:for-each select="rdf:Description">
                <xsl:variable name="subject" as="xs:string"
                    select="(@rdf:about, @rdf:nodeID ! ('_:' || .))[1]"/>
                <xsl:for-each select="*">
                    <t s="{$subject}" p="{namespace-uri() || local-name()}">
                        <xsl:choose>
                            <xsl:when test="@rdf:resource">
                                <xsl:attribute name="o" select="@rdf:resource"/>
                            </xsl:when>
                            <xsl:when test="@rdf:nodeID">
                                <xsl:attribute name="o" select="'_:' || @rdf:nodeID"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:attribute name="l" select="string(.)"/>
                                <xsl:if test="@rdf:datatype">
                                    <xsl:attribute name="dt" select="@rdf:datatype"/>
                                </xsl:if>
                                <xsl:if test="@xml:lang">
                                    <xsl:attribute name="lang" select="@xml:lang"/>
                                </xsl:if>
                            </xsl:otherwise>
                        </xsl:choose>
                    </t>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:variable>

        <triples>
            <xsl:perform-sort select="$triples">
                <xsl:sort select="@s"/>
                <xsl:sort select="@p"/>
                <xsl:sort select="@o"/>
                <xsl:sort select="@l"/>
                <xsl:sort select="@dt"/>
                <xsl:sort select="@lang"/>
            </xsl:perform-sort>
        </triples>
    </xsl:template>

</xsl:stylesheet>
