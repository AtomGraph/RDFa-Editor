<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:rdfae="https://w3id.org/atomgraph/rdfa-editor#"
exclude-result-prefixes="#all"
version="3.0">

<!--
    Every user-visible string the editor emits comes from here, so the chrome can be
    translated without touching the templates that render it. The catalog is plain
    RDF/XML - rdf:Description carrying rdfs:label per language, keyed by rdf:nodeID -
    which is the same shape a host is likely to keep its own strings in.

    A host translates the editor by overriding rdfae:translations() to return its own
    catalog (import precedence decides), or by pointing $translations-href at another
    document. Overriding rdfae:label() as well replaces the language selection, for a
    host that resolves it from something richer than a parameter.
-->

    <!-- the string catalog. A relative href resolves against the page URI and the host
         page must preload it into the SaxonJS document pool, exactly as $vocab-hrefs does -->
    <xsl:param name="translations-href" as="xs:string" select="'translations.rdf'"/>

    <!-- the language labels are selected in. A host with its own notion of the user's
         language (a negotiated Accept-Language, a profile setting) redeclares this -->
    <xsl:param name="translations-lang" as="xs:string" select="'en'"/>

    <!-- keyed by rdf:nodeID, the catalog's own identifiers; also matches rdf:about so a
         host catalog that names its terms with IRIs resolves through the same lookup -->
    <xsl:key name="resources" match="*[*][@rdf:about] | *[*][@rdf:nodeID]" use="@rdf:about | @rdf:nodeID"/>

    <!-- resolved against the page URI in the browser, the way the vocabularies are, so
         doc() hits the preloaded pool; against the stylesheet itself under Saxon, where
         there is no page and the test drivers read the file from disk. Two declarations
         rather than a branch, because ixsl:location() does not exist to compile against
         outside SaxonJS -->

    <xsl:function name="rdfae:translations" as="document-node()" use-when="system-property('xsl:product-name') = 'SaxonJS'">
        <xsl:sequence select="doc(string(resolve-uri($translations-href, ixsl:location())))"/>
    </xsl:function>

    <xsl:function name="rdfae:translations" as="document-node()" use-when="not(system-property('xsl:product-name') = 'SaxonJS')">
        <xsl:sequence select="document(resolve-uri($translations-href, static-base-uri()))"/>
    </xsl:function>

    <!-- the label for a catalog key: the exact language, else any variant of it (es-ES
         answering es), else whatever the catalog holds, else the key itself - an untranslated
         string is a visible key rather than an empty control -->
    <xsl:function name="rdfae:label" as="xs:string">
        <xsl:param name="key" as="xs:string"/>

        <xsl:variable name="labels" as="element()*" select="key('resources', $key, rdfae:translations())/rdfs:label"/>
        <xsl:sequence select="string(($labels[@xml:lang = $translations-lang], $labels[starts-with(@xml:lang, substring($translations-lang, 1, 2))], $labels, $key)[1])"/>
    </xsl:function>

</xsl:stylesheet>
