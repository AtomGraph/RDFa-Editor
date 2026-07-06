<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xpath-default-namespace="http://www.w3.org/1999/xhtml"
    version="3.0">

<!--
    Comparison normalizer for canonical-XHTML tests: drops whitespace-only text
    nodes only where they are insignificant (element-only containers), so that
    hand-authored expected files and transform output diff cleanly. pre subtrees
    and mixed content are untouched - which is why xsl:strip-space/c14n won't do.
-->

    <xsl:mode on-no-match="shallow-copy"/>

    <xsl:output method="xml" indent="yes"/>

    <xsl:template match="text()[not(normalize-space())][not(ancestor::pre)]
        [parent::html | parent::head | parent::body | parent::div | parent::section
         | parent::article | parent::ul | parent::ol | parent::figure]"/>

</xsl:stylesheet>
