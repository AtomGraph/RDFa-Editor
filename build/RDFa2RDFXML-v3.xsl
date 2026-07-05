<xsl:stylesheet xmlns:map="http://www.w3.org/2005/xpath-functions/map" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:rdfa="urn:rdfa:functions" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="xs map rdfa" version="3.0" xpath-default-namespace="http://www.w3.org/1999/xhtml">

<!--
    XSLT 3.0 RDFa to RDF/XML Extraction

    Pragmatic implementation targeting 80% common RDFa use cases:
    - Schema.org microdata patterns
    - Basic FOAF (Friend of a Friend)
    - Simple Dublin Core

    Supported RDFa 1.1 attributes:
    - @property (literal properties)
    - @typeof (type declarations)
    - @about (explicit subjects)
    - @content (machine-readable values)
    - @resource, @href (object URIs)
    - @prefix (namespace declarations)
    - @datatype (basic XSD types)
    - @xml:lang (language tags)

    Uses XSLT 3.0 features:
    - xsl:map for prefix mappings
    - xsl:function for CURIE resolution
    - xsl:accumulator for context inheritance
-->

    <xsl:output encoding="UTF-8" indent="yes" method="xml"></xsl:output>

    <!-- Common namespace prefixes (default mappings) -->
    <xsl:variable as="map(xs:string, xs:string)" name="default-prefixes">
        <xsl:map>
            <xsl:map-entry key="'rdf'" select="'http://www.w3.org/1999/02/22-rdf-syntax-ns#'"></xsl:map-entry>
            <xsl:map-entry key="'rdfs'" select="'http://www.w3.org/2000/01/rdf-schema#'"></xsl:map-entry>
            <xsl:map-entry key="'xsd'" select="'http://www.w3.org/2001/XMLSchema#'"></xsl:map-entry>
            <xsl:map-entry key="'schema'" select="'http://schema.org/'"></xsl:map-entry>
            <xsl:map-entry key="'foaf'" select="'http://xmlns.com/foaf/0.1/'"></xsl:map-entry>
            <xsl:map-entry key="'dc'" select="'http://purl.org/dc/terms/'"></xsl:map-entry>
        </xsl:map>
    </xsl:variable>

    <!--
        Context Accumulator
        Tracks the current subject URI as we traverse the DOM tree.
        Enables subject inheritance from parent to child elements.
    -->
    <xsl:accumulator as="xs:string?" initial-value="()" name="subject-context">
        <xsl:accumulator-rule match="*[@about or @typeof]">
            <xsl:variable name="prefixes" select="rdfa:collect-prefixes(.)"></xsl:variable>
            <xsl:sequence select="rdfa:determine-subject(., $prefixes, $value)"></xsl:sequence>
        </xsl:accumulator-rule>
    </xsl:accumulator>

    <!-- Entry point -->
    <xsl:template match="/" name="extract-rdfa">
        <rdf:RDF>
            <xsl:apply-templates mode="rdfa-extract" select="//body"></xsl:apply-templates>
        </rdf:RDF>
    </xsl:template>

    <!-- Main RDFa extraction mode -->
    <xsl:template match="*" mode="rdfa-extract">
        <xsl:param as="xs:string?" name="parent-subject" select="()"></xsl:param>
        <xsl:param as="map(xs:string, xs:string)" name="parent-prefixes" select="$default-prefixes"></xsl:param>

        <!-- Collect prefixes from this element -->
        <xsl:variable as="map(xs:string, xs:string)" name="prefixes">
            <xsl:sequence select="rdfa:merge-prefixes(($parent-prefixes, rdfa:parse-prefix-attr(@prefix), rdfa:parse-xmlns-prefixes(.)))"></xsl:sequence>
        </xsl:variable>

        <!-- Determine subject for this element -->
        <xsl:variable as="xs:string?" name="current-subject" select="rdfa:determine-subject(., $prefixes, $parent-subject)"></xsl:variable>

        <!-- Process @typeof (type declaration) -->
        <xsl:if test="@typeof and $current-subject">
            <xsl:for-each select="tokenize(normalize-space(@typeof), '\s+')">
                <xsl:variable name="type-uri" select="rdfa:resolve-curie(., $prefixes)"></xsl:variable>
                <xsl:if test="$type-uri">
                    <rdf:Description rdf:about="{$current-subject}">
                        <rdf:type rdf:resource="{$type-uri}"></rdf:type>
                    </rdf:Description>
                </xsl:if>
            </xsl:for-each>
        </xsl:if>

        <!-- Process @property (literal or resource property) -->
        <xsl:if test="@property and $current-subject">
            <xsl:variable name="element" select="."></xsl:variable>
            <xsl:for-each select="tokenize(normalize-space(@property), '\s+')">
                <xsl:variable name="prop-uri" select="rdfa:resolve-curie(., $prefixes)"></xsl:variable>
                <xsl:if test="$prop-uri">
                    <xsl:variable name="prop-parts" select="rdfa:split-uri($prop-uri)"></xsl:variable>
                    <rdf:Description rdf:about="{$current-subject}">
                        <xsl:element name="{$prop-parts?local}" namespace="{$prop-parts?namespace}">
                            <xsl:choose>
                                <!-- Object is a resource (@resource or @href) -->
                                <xsl:when test="$element/@resource">
                                    <xsl:attribute name="rdf:resource" select="rdfa:resolve-uri($element/@resource, $prefixes)"></xsl:attribute>
                                </xsl:when>
                                <xsl:when test="$element/@href">
                                    <xsl:attribute name="rdf:resource" select="rdfa:resolve-uri($element/@href, $prefixes)"></xsl:attribute>
                                </xsl:when>
                                <!-- Object is a literal value -->
                                <xsl:otherwise>
                                    <xsl:variable name="content" select="if ($element/@content) then $element/@content else normalize-space($element)"></xsl:variable>

                                    <!-- Add datatype if specified -->
                                    <xsl:if test="$element/@datatype">
                                        <xsl:variable name="datatype-uri" select="rdfa:resolve-curie($element/@datatype, $prefixes)"></xsl:variable>
                                        <xsl:if test="$datatype-uri">
                                            <xsl:attribute name="rdf:datatype" select="$datatype-uri"></xsl:attribute>
                                        </xsl:if>
                                    </xsl:if>

                                    <!-- Add language tag if specified -->
                                    <xsl:if test="$element/@xml:lang and not($element/@datatype)">
                                        <xsl:attribute name="xml:lang" select="$element/@xml:lang"></xsl:attribute>
                                    </xsl:if>

                                    <xsl:value-of select="$content"></xsl:value-of>
                                </xsl:otherwise>
                            </xsl:choose>
                        </xsl:element>
                    </rdf:Description>
                </xsl:if>
            </xsl:for-each>
        </xsl:if>

        <!-- Recursively process children -->
        <xsl:apply-templates mode="rdfa-extract" select="*">
            <xsl:with-param name="parent-subject" select="$current-subject"></xsl:with-param>
            <xsl:with-param name="parent-prefixes" select="$prefixes"></xsl:with-param>
        </xsl:apply-templates>
    </xsl:template>

    <!--
        Function: Determine Subject
        Determines the subject URI for the current element.
        Priority: @about > @typeof (new blank node) > parent subject
    -->
    <xsl:function as="xs:string?" name="rdfa:determine-subject">
        <xsl:param as="element()" name="element"></xsl:param>
        <xsl:param as="map(xs:string, xs:string)" name="prefixes"></xsl:param>
        <xsl:param as="xs:string?" name="parent-subject"></xsl:param>

        <xsl:choose>
            <!-- Explicit subject via @about -->
            <xsl:when test="$element/@about">
                <xsl:sequence select="rdfa:resolve-uri($element/@about, $prefixes)"></xsl:sequence>
            </xsl:when>
            <!-- @typeof creates a new subject (blank node or inferred) -->
            <xsl:when test="$element/@typeof">
                <xsl:choose>
                    <!-- If has @resource or @href, use that as subject -->
                    <xsl:when test="$element/@resource">
                        <xsl:sequence select="rdfa:resolve-uri($element/@resource, $prefixes)"></xsl:sequence>
                    </xsl:when>
                    <xsl:when test="$element/@href">
                        <xsl:sequence select="rdfa:resolve-uri($element/@href, $prefixes)"></xsl:sequence>
                    </xsl:when>
                    <xsl:when test="$element/@src">
                        <xsl:sequence select="rdfa:resolve-uri($element/@src, $prefixes)"></xsl:sequence>
                    </xsl:when>
                    <!-- Generate blank node -->
                    <xsl:otherwise>
                        <xsl:sequence select="concat('_:b', generate-id($element))"></xsl:sequence>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:when>
            <!-- Inherit from parent -->
            <xsl:otherwise>
                <xsl:sequence select="$parent-subject"></xsl:sequence>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!--
        Function: Resolve CURIE
        Expands a CURIE (Compact URI) to a full URI using prefix mappings.
        Examples: "schema:Person" -> "http://schema.org/Person"
    -->
    <xsl:function as="xs:string?" name="rdfa:resolve-curie">
        <xsl:param as="xs:string" name="curie"></xsl:param>
        <xsl:param as="map(xs:string, xs:string)" name="prefixes"></xsl:param>

        <xsl:choose>
            <!-- Absolute URI - return as-is -->
            <xsl:when test="matches($curie, '^https?://')">
                <xsl:sequence select="$curie"></xsl:sequence>
            </xsl:when>
            <!-- CURIE with prefix -->
            <xsl:when test="contains($curie, ':')">
                <xsl:variable name="prefix" select="substring-before($curie, ':')"></xsl:variable>
                <xsl:variable name="local" select="substring-after($curie, ':')"></xsl:variable>
                <xsl:if test="map:contains($prefixes, $prefix)">
                    <xsl:sequence select="concat(map:get($prefixes, $prefix), $local)"></xsl:sequence>
                </xsl:if>
            </xsl:when>
            <!-- No prefix - cannot resolve -->
            <xsl:otherwise>
                <xsl:sequence select="()"></xsl:sequence>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!--
        Function: Resolve URI
        Resolves a URI value, handling CURIEs, absolute URIs, and relative URIs.
    -->
    <xsl:function as="xs:string" name="rdfa:resolve-uri">
        <xsl:param as="xs:string" name="uri"></xsl:param>
        <xsl:param as="map(xs:string, xs:string)" name="prefixes"></xsl:param>

        <xsl:choose>
            <!-- Try CURIE resolution first -->
            <xsl:when test="contains($uri, ':')">
                <xsl:variable name="resolved" select="rdfa:resolve-curie($uri, $prefixes)"></xsl:variable>
                <xsl:sequence select="if ($resolved) then $resolved else $uri"></xsl:sequence>
            </xsl:when>
            <!-- Fragment identifier -->
            <xsl:when test="starts-with($uri, '#')">
                <xsl:sequence select="$uri"></xsl:sequence>
            </xsl:when>
            <!-- Relative or absolute URI -->
            <xsl:otherwise>
                <xsl:sequence select="$uri"></xsl:sequence>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!--
        Function: Parse @prefix Attribute
        Parses the RDFa @prefix attribute into a map.
        Format: "prefix1: http://... prefix2: http://..."
    -->
    <xsl:function as="map(xs:string, xs:string)" name="rdfa:parse-prefix-attr">
        <xsl:param as="xs:string?" name="prefix-attr"></xsl:param>

        <xsl:choose>
            <xsl:when test="$prefix-attr">
                <xsl:map>
                    <xsl:for-each select="tokenize(normalize-space($prefix-attr), '\s+')">
                        <xsl:if test="position() mod 2 = 1 and ends-with(., ':')">
                            <xsl:variable name="prefix" select="substring(., 1, string-length(.) - 1)"></xsl:variable>
                            <xsl:variable name="uri" select="subsequence(tokenize(normalize-space($prefix-attr), '\s+'), position() + 1, 1)"></xsl:variable>
                            <xsl:if test="$uri">
                                <xsl:map-entry key="$prefix" select="$uri"></xsl:map-entry>
                            </xsl:if>
                        </xsl:if>
                    </xsl:for-each>
                </xsl:map>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="map{}"></xsl:sequence>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!--
        Function: Parse xmlns: Prefix Declarations
        Extracts namespace prefix declarations from element attributes.
    -->
    <xsl:function as="map(xs:string, xs:string)" name="rdfa:parse-xmlns-prefixes">
        <xsl:param as="element()" name="element"></xsl:param>

        <xsl:map>
            <xsl:for-each select="$element/@*[starts-with(name(), 'xmlns:')]">
                <xsl:variable name="prefix" select="substring-after(name(), 'xmlns:')"></xsl:variable>
                <xsl:map-entry key="$prefix" select="string(.)"></xsl:map-entry>
            </xsl:for-each>
        </xsl:map>
    </xsl:function>

    <!--
        Function: Merge Prefix Maps
        Combines multiple prefix maps with later maps taking precedence.
    -->
    <xsl:function as="map(xs:string, xs:string)" name="rdfa:merge-prefixes">
        <xsl:param as="map(xs:string, xs:string)*" name="maps"></xsl:param>

        <xsl:sequence select="             if (count($maps) = 0) then map{}             else if (count($maps) = 1) then $maps[1]             else map:merge($maps, map{'duplicates': 'use-last'})         "></xsl:sequence>
    </xsl:function>

    <!--
        Function: Collect Prefixes
        Collects all prefix mappings from an element and its ancestors.
    -->
    <xsl:function as="map(xs:string, xs:string)" name="rdfa:collect-prefixes">
        <xsl:param as="element()" name="element"></xsl:param>

        <xsl:sequence select="rdfa:merge-prefixes((             $default-prefixes,             rdfa:parse-xmlns-prefixes($element),             rdfa:parse-prefix-attr($element/@prefix)         ))"></xsl:sequence>
    </xsl:function>

    <!--
        Function: Split URI
        Splits a URI into namespace and local name parts for RDF/XML element creation.
        Splits on the last occurrence of '#' or '/' to separate namespace from local name.
        Returns a map with 'namespace' and 'local' keys.
    -->
    <xsl:function as="map(xs:string, xs:string)" name="rdfa:split-uri">
        <xsl:param as="xs:string" name="uri"></xsl:param>

        <xsl:variable as="xs:integer" name="split-pos">
            <xsl:choose>
                <xsl:when test="contains($uri, '#')">
                    <xsl:sequence select="string-length(substring-before($uri, concat('#', tokenize($uri, '#')[last()]))) + 1"></xsl:sequence>
                </xsl:when>
                <xsl:when test="contains($uri, '/')">
                    <xsl:sequence select="string-length(substring-before($uri, concat('/', tokenize($uri, '/')[last()]))) + 1"></xsl:sequence>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="0"></xsl:sequence>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>

        <xsl:map>
            <xsl:map-entry key="'namespace'" select="if ($split-pos gt 0) then substring($uri, 1, $split-pos) else $uri"></xsl:map-entry>
            <xsl:map-entry key="'local'" select="if ($split-pos gt 0) then substring($uri, $split-pos + 1) else 'value'"></xsl:map-entry>
        </xsl:map>
    </xsl:function>

</xsl:stylesheet>