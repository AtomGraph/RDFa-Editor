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
xmlns:local="http://example.org/local"
xmlns:err="http://www.w3.org/2005/xqt-errors"
exclude-result-prefixes="xs prop local err"
extension-element-prefixes="ixsl"
version="3.0"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
>

    <xsl:include href="RDFa2RDFXML-v3.xsl"/>

    <!-- Function to detect inherited RDFa subject from ancestor elements -->
    <xsl:function name="local:get-inherited-subject" as="xs:string?">
        <xsl:param name="element" as="element()"/>
        <xsl:variable name="ancestor" select="$element/ancestor::*[@about or @resource or @typeof][1]"/>
        <xsl:choose>
            <xsl:when test="$ancestor/@about">
                <xsl:sequence select="string($ancestor/@about)"/>
            </xsl:when>
            <xsl:when test="$ancestor/@resource">
                <xsl:sequence select="string($ancestor/@resource)"/>
            </xsl:when>
            <xsl:when test="$ancestor/@typeof">
                <xsl:sequence select="'[blank node]'"/>
            </xsl:when>
        </xsl:choose>
    </xsl:function>

    <xsl:template name="main">
        <!-- Initialize window properties for edit mode tracking -->
        <ixsl:set-property name="editMode" select="false()" object="ixsl:window()"/>
        <ixsl:set-property name="editingSpan" select="()" object="ixsl:window()"/>
    </xsl:template>

    <xsl:template match="p[ixsl:get(., 'contentEditable') = 'true']" mode="ixsl:oncontextmenu">
        <xsl:variable name="event" select="ixsl:event()"/>
        <xsl:sequence select="ixsl:call(ixsl:event(), 'preventDefault', [])[current-date() lt xs:date('2000-01-01')]"/>
        <xsl:variable name="selection" select="ixsl:call(ixsl:window(), 'getSelection', [] )"/>
        <xsl:variable name="range" select="ixsl:call($selection, 'getRangeAt', [ 0 ])"/>
        <xsl:variable name="selected-text" select="ixsl:call($selection, 'toString', [])"/>

        <!-- Pre-validate selection using IXSL (no DOM modification) -->
        <!-- Get range container information -->
        <xsl:variable name="startContainer" select="ixsl:get($range, 'startContainer')"/>
        <xsl:variable name="endContainer" select="ixsl:get($range, 'endContainer')"/>
        <xsl:variable name="commonAncestor" select="ixsl:get($range, 'commonAncestorContainer')"/>

        <!-- Check node types (3 = TEXT_NODE) -->
        <xsl:variable name="startNodeType" select="ixsl:get($startContainer, 'nodeType')"/>
        <xsl:variable name="endNodeType" select="ixsl:get($endContainer, 'nodeType')"/>

        <!-- Validation logic: surroundContents() succeeds if:
             1. Start and end are in the same container, OR
             2. Both containers are text nodes and share same parent, OR
             3. Start/end containers are parent/child with no partial element selection
        -->
        <xsl:variable name="is-valid" select="
            (ixsl:call($startContainer, 'isSameNode', [$endContainer])) or
            ($startNodeType = 3 and $endNodeType = 3 and
             ixsl:call(ixsl:get($startContainer, 'parentNode'), 'isSameNode', [ixsl:get($endContainer, 'parentNode')]))
        "/>

        <xsl:choose>
            <xsl:when test="$is-valid">
                <!-- Valid selection - show popup -->
                <!-- Store range and context element for later use -->
                <ixsl:set-property name="range" select="$range" object="ixsl:window()"/>
                <ixsl:set-property name="contextElement" select="." object="ixsl:window()"/>

                <!-- Detect inherited subject -->
                <xsl:variable name="inherited-subject" select="local:get-inherited-subject(.)"/>

		<xsl:if test="not(id('overlay', ixsl:page()))">
			<xsl:for-each select="ixsl:page()//body">
				<xsl:result-document href="?." method="ixsl:append-content">
					<div id="overlay">
                        <div class="overlay-header">
                            <h3>Add RDFa Annotation</h3>
                            <span class="selected-text-preview" id="selected-text-preview"></span>
                        </div>
						<form id="annotation-form">
                            <!-- Pattern Selection -->
                            <div class="pattern-selector">
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="property" checked="checked"/>
                                    <span>Add Property</span>
                                </label>
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="entity"/>
                                    <span>Create Entity</span>
                                </label>
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="advanced"/>
                                    <span>Advanced</span>
                                </label>
                            </div>

                            <!-- Inherited Subject Indicator -->
                            <div id="inherited-subject-section" class="inherited-context">
                                <div class="inherited-label">✓ Subject inherited from ancestor:</div>
                                <div id="inherited-subject-value" class="inherited-value"></div>
                            </div>

                            <!-- Subject Field (for advanced pattern) -->
                            <fieldset id="subject-fieldset" style="display: none;">
                                <label>Subject (about/resource)</label>
                                <input type="text" name="subject" placeholder="http://example.org/resource"/>
                                <span class="helper-text">URI or blank node identifier</span>
                            </fieldset>

                            <!-- Entity Type Field (for entity pattern) -->
                            <fieldset id="typeof-fieldset" style="display: none;">
                                <label>Entity Type (typeof)</label>
                                <select name="typeof">
                                    <option value="">-- Select type --</option>
                                    <optgroup label="Schema.org">
                                        <option value="http://schema.org/Person">Person</option>
                                        <option value="http://schema.org/Article">Article</option>
                                        <option value="http://schema.org/Organization">Organization</option>
                                        <option value="http://schema.org/Place">Place</option>
                                        <option value="http://schema.org/Event">Event</option>
                                    </optgroup>
                                    <optgroup label="FOAF">
                                        <option value="http://xmlns.com/foaf/0.1/Person">Person</option>
                                        <option value="http://xmlns.com/foaf/0.1/Document">Document</option>
                                        <option value="http://xmlns.com/foaf/0.1/Organization">Organization</option>
                                    </optgroup>
                                </select>
                                <span class="helper-text">Type of the resource being created</span>
                            </fieldset>

                            <!-- Property Field (all patterns) -->
							<fieldset id="property-fieldset">
								<label>Property</label>
								<select name="property">
                                    <optgroup label="Schema.org (Common)">
                                        <option value="http://schema.org/name">name</option>
                                        <option value="http://schema.org/description">description</option>
                                        <option value="http://schema.org/author">author</option>
                                        <option value="http://schema.org/datePublished">datePublished</option>
                                        <option value="http://schema.org/url">url</option>
                                    </optgroup>
									<optgroup label="FOAF">
										<xsl:for-each select="document('vocabs/foaf.rdf')/rdf:RDF/rdf:Property">
											<xsl:sort select="@rdfs:label"/>
											<option value="{@rdf:about}">
												<xsl:value-of select="@rdfs:label"/>
											</option>
										</xsl:for-each>
									</optgroup>
                                    <optgroup label="Dublin Core">
                                        <option value="http://purl.org/dc/terms/title">title</option>
                                        <option value="http://purl.org/dc/terms/creator">creator</option>
                                        <option value="http://purl.org/dc/terms/created">created</option>
                                        <option value="http://purl.org/dc/terms/description">description</option>
                                    </optgroup>
                                    <option value="">-- Custom property --</option>
								</select>
                                <span class="helper-text">The property/predicate to annotate</span>
							</fieldset>

                            <!-- Value/Content Field -->
                            <fieldset id="value-fieldset">
                                <label>Value</label>
                                <div class="value-options">
                                    <label class="value-option">
                                        <input type="radio" name="value-type" value="text" checked="checked"/>
                                        <span>Use selected text</span>
                                    </label>
                                    <label class="value-option">
                                        <input type="radio" name="value-type" value="custom"/>
                                        <span>Custom value:</span>
                                    </label>
                                </div>
                                <input type="text" name="custom-value" id="custom-value-input" placeholder="Enter custom value" disabled="disabled"/>
                                <span class="helper-text">For dates, codes, or URIs different from display text</span>
                            </fieldset>

                            <!-- Object/Resource Field (for advanced pattern) -->
                            <fieldset id="object-fieldset" style="display: none;">
                                <label>Object/Resource</label>
                                <input type="text" name="object" placeholder="Value or URI"/>
                                <span class="helper-text">The value or resource URI</span>
                            </fieldset>

                            <!-- Action Buttons -->
							<div class="action-buttons">
								<button type="button" class="btn-primary spo-action">Annotate</button>
                                <button type="button" class="btn-secondary cancel-action">Cancel</button>
							</div>
						</form>
					</div>
				</xsl:result-document>
			</xsl:for-each>
		</xsl:if>

        <!-- Clear edit mode and reset form to defaults -->
        <ixsl:set-property name="editMode" select="false()" object="ixsl:window()"/>
        <xsl:for-each select="id('annotation-form', ixsl:page())">
            <xsl:sequence select="ixsl:call(., 'reset', [])[current-date() lt xs:date('2000-01-01')]"/>
        </xsl:for-each>

        <xsl:call-template name="show-overlay">
            <xsl:with-param name="event" select="$event"/>
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'block'"/>
            <xsl:with-param name="inherited-subject" select="$inherited-subject"/>
            <xsl:with-param name="selected-text" select="$selected-text"/>
        </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <!-- Invalid selection - show red flash without popup -->
                <xsl:message>Invalid selection detected - showing red flash feedback only</xsl:message>

                <!-- Create red flash overlay -->
                <xsl:variable name="flash-range" select="$range"/>
                <xsl:variable name="rect" select="ixsl:call($flash-range, 'getBoundingClientRect', [])"/>
                <xsl:variable name="overlay" select="ixsl:call(ixsl:page(), 'createElement', [ 'div' ])" as="element()"/>
                <ixsl:set-attribute name="class" select="'invalid-selection-flash'" object="$overlay"/>
                <ixsl:set-style name="position" select="'fixed'" object="$overlay"/>
                <ixsl:set-style name="left" select="ixsl:get($rect, 'left') || 'px'" object="$overlay"/>
                <ixsl:set-style name="top" select="ixsl:get($rect, 'top') || 'px'" object="$overlay"/>
                <ixsl:set-style name="width" select="ixsl:get($rect, 'width') || 'px'" object="$overlay"/>
                <ixsl:set-style name="height" select="ixsl:get($rect, 'height') || 'px'" object="$overlay"/>
                <ixsl:set-style name="pointer-events" select="'none'" object="$overlay"/>
                <ixsl:set-style name="z-index" select="'9999'" object="$overlay"/>

                <!-- Append to body -->
                <xsl:for-each select="ixsl:page()//body">
                    <xsl:result-document href="?." method="ixsl:append-content">
                        <xsl:sequence select="$overlay"/>
                    </xsl:result-document>
                </xsl:for-each>

                <!-- Remove overlay after animation (1200ms) -->
                <xsl:sequence select="ixsl:call(ixsl:window(), 'setTimeout', [
                    ixsl:call(ixsl:window(), 'Function', ['
                        var overlay = document.querySelector(''.invalid-selection-flash'');
                        if (overlay) {
                            overlay.remove();
                        }
                    '])
                    , 1200
                ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

	<xsl:template match="button[tokenize(@class, ' ') = 'spo-action']" mode="ixsl:onclick">
        <!-- Get selected pattern -->
        <xsl:variable name="pattern" select="ixsl:get(ancestor::form//input[@name = 'pattern'][@checked or @checked = 'checked'], 'value')"/>

        <!-- Get form values -->
        <xsl:variable name="property" select="ixsl:get(ancestor::form//select[@name = 'property'], 'value')"/>
        <xsl:variable name="subject" select="ixsl:get(ancestor::form//input[@name = 'subject'], 'value')"/>
        <xsl:variable name="typeof" select="ixsl:get(ancestor::form//select[@name = 'typeof'], 'value')"/>
        <xsl:variable name="value-type" select="ixsl:get(ancestor::form//input[@name = 'value-type'][@checked or @checked = 'checked'], 'value')"/>
        <xsl:variable name="custom-value" select="ixsl:get(ancestor::form//input[@name = 'custom-value'], 'value')"/>
        <xsl:variable name="object" select="ixsl:get(ancestor::form//input[@name = 'object'], 'value')"/>

		<xsl:message>Pattern: <xsl:value-of select="$pattern"/></xsl:message>
		<xsl:message>Property: <xsl:value-of select="$property"/></xsl:message>
        <xsl:message>Typeof: <xsl:value-of select="$typeof"/></xsl:message>

        <!-- Check if we're in edit mode or creating new annotation -->
        <xsl:variable name="editMode" select="ixsl:get(ixsl:window(), 'editMode')"/>
        <xsl:variable name="editingSpan" select="ixsl:get(ixsl:window(), 'editingSpan')"/>

        <xsl:choose>
            <!-- Edit Mode: Update existing span -->
            <xsl:when test="$editMode">
                <xsl:message>Edit mode: updating existing span</xsl:message>

                <!-- Clear all existing RDFa attributes first -->
                <xsl:for-each select="$editingSpan">
                    <xsl:sequence select="ixsl:call(., 'removeAttribute', ['property'])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:sequence select="ixsl:call(., 'removeAttribute', ['typeof'])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:sequence select="ixsl:call(., 'removeAttribute', ['about'])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:sequence select="ixsl:call(., 'removeAttribute', ['resource'])[current-date() lt xs:date('2000-01-01')]"/>
                    <xsl:sequence select="ixsl:call(., 'removeAttribute', ['content'])[current-date() lt xs:date('2000-01-01')]"/>

                    <!-- Apply updated RDFa attributes based on selected pattern -->
                    <xsl:choose>
                        <!-- Pattern A: Add Property (inherits subject) -->
                        <xsl:when test="$pattern = 'property' or not($pattern)">
                            <ixsl:set-attribute name="property" select="$property"/>
                            <xsl:if test="$value-type = 'custom' and $custom-value">
                                <ixsl:set-attribute name="content" select="$custom-value"/>
                            </xsl:if>
                        </xsl:when>

                        <!-- Pattern B: Create Entity -->
                        <xsl:when test="$pattern = 'entity'">
                            <xsl:if test="$typeof">
                                <ixsl:set-attribute name="typeof" select="$typeof"/>
                            </xsl:if>
                            <ixsl:set-attribute name="property" select="$property"/>
                            <xsl:if test="$value-type = 'custom' and $custom-value">
                                <ixsl:set-attribute name="content" select="$custom-value"/>
                            </xsl:if>
                        </xsl:when>

                        <!-- Pattern C: Advanced (full control) -->
                        <xsl:when test="$pattern = 'advanced'">
                            <xsl:if test="$subject">
                                <ixsl:set-attribute name="about" select="$subject"/>
                            </xsl:if>
                            <ixsl:set-attribute name="property" select="$property"/>
                            <xsl:if test="$object">
                                <ixsl:set-attribute name="resource" select="$object"/>
                            </xsl:if>
                            <xsl:if test="$value-type = 'custom' and $custom-value">
                                <ixsl:set-attribute name="content" select="$custom-value"/>
                            </xsl:if>
                        </xsl:when>
                    </xsl:choose>
                </xsl:for-each>

                <!-- Clear edit mode -->
                <ixsl:set-property name="editMode" select="false()" object="ixsl:window()"/>
                <ixsl:set-property name="editingSpan" select="()" object="ixsl:window()"/>

                <!-- Hide overlay -->
                <xsl:call-template name="show-overlay">
                    <xsl:with-param name="overlay-id" select="'overlay'"/>
                    <xsl:with-param name="display" select="'none'"/>
                </xsl:call-template>
            </xsl:when>

            <!-- Create Mode: Create new annotation -->
            <xsl:otherwise>
                <xsl:variable name="range" select="ixsl:get(ixsl:window(), 'range')"/>
                <xsl:variable name="span" select="ixsl:call(ixsl:page(), 'createElement', [ 'span' ])" as="element()"/>

                <xsl:try>
                    <xsl:sequence select="ixsl:call($range, 'surroundContents', [ $span ])[current-date() lt xs:date('2000-01-01')]"/>
                    <ixsl:set-attribute name="id" select="generate-id($span)" object="$span"/>

                    <!-- Apply RDFa attributes based on selected pattern -->
                    <xsl:for-each select="$span">
                <xsl:choose>
                    <!-- Pattern A: Add Property (inherits subject) -->
                    <xsl:when test="$pattern = 'property' or not($pattern)">
                        <ixsl:set-attribute name="property" select="$property"/>
                        <xsl:if test="$value-type = 'custom' and $custom-value">
                            <ixsl:set-attribute name="content" select="$custom-value"/>
                        </xsl:if>
                    </xsl:when>

                    <!-- Pattern B: Create Entity -->
                    <xsl:when test="$pattern = 'entity'">
                        <xsl:if test="$typeof">
                            <ixsl:set-attribute name="typeof" select="$typeof"/>
                        </xsl:if>
                        <ixsl:set-attribute name="property" select="$property"/>
                        <xsl:if test="$value-type = 'custom' and $custom-value">
                            <ixsl:set-attribute name="content" select="$custom-value"/>
                        </xsl:if>
                    </xsl:when>

                    <!-- Pattern C: Advanced (full control) -->
                    <xsl:when test="$pattern = 'advanced'">
                        <xsl:if test="$subject">
                            <ixsl:set-attribute name="about" select="$subject"/>
                        </xsl:if>
                        <ixsl:set-attribute name="property" select="$property"/>
                        <xsl:if test="$object">
                            <ixsl:set-attribute name="resource" select="$object"/>
                        </xsl:if>
                        <xsl:if test="$value-type = 'custom' and $custom-value">
                            <ixsl:set-attribute name="content" select="$custom-value"/>
                        </xsl:if>
                    </xsl:when>
                </xsl:choose>
            </xsl:for-each>

            <xsl:call-template name="show-overlay">
                <xsl:with-param name="overlay-id" select="'overlay'"/>
                <xsl:with-param name="display" select="'none'"/>
            </xsl:call-template>

            <xsl:catch errors="*">
                <!-- Selection crosses boundaries - show red flash feedback -->
                <xsl:message>Invalid selection - showing red flash</xsl:message>

                <!-- Close the popup first -->
                <xsl:call-template name="show-overlay">
                    <xsl:with-param name="overlay-id" select="'overlay'"/>
                    <xsl:with-param name="display" select="'none'"/>
                </xsl:call-template>

                <!-- Create red flash overlay -->
                <xsl:variable name="sel" select="ixsl:call(ixsl:window(), 'getSelection', [])"/>
                <xsl:variable name="flash-range" select="ixsl:call($sel, 'getRangeAt', [0])"/>
                <xsl:variable name="rect" select="ixsl:call($flash-range, 'getBoundingClientRect', [])"/>
                <xsl:variable name="overlay" select="ixsl:call(ixsl:page(), 'createElement', [ 'div' ])" as="element()"/>
                <ixsl:set-attribute name="class" select="'invalid-selection-flash'" object="$overlay"/>
                <ixsl:set-style name="position" select="'fixed'" object="$overlay"/>
                <ixsl:set-style name="left" select="ixsl:get($rect, 'left') || 'px'" object="$overlay"/>
                <ixsl:set-style name="top" select="ixsl:get($rect, 'top') || 'px'" object="$overlay"/>
                <ixsl:set-style name="width" select="ixsl:get($rect, 'width') || 'px'" object="$overlay"/>
                <ixsl:set-style name="height" select="ixsl:get($rect, 'height') || 'px'" object="$overlay"/>
                <ixsl:set-style name="pointer-events" select="'none'" object="$overlay"/>
                <ixsl:set-style name="z-index" select="'9999'" object="$overlay"/>

                <!-- Append to body -->
                <xsl:for-each select="ixsl:page()//body">
                    <xsl:result-document href="?." method="ixsl:append-content">
                        <xsl:sequence select="$overlay"/>
                    </xsl:result-document>
                </xsl:for-each>

                <!-- Remove overlay after animation (1200ms) -->
                <xsl:sequence select="ixsl:call(ixsl:window(), 'setTimeout', [
                    ixsl:call(ixsl:window(), 'Function', ['
                        var overlay = document.querySelector(''.invalid-selection-flash'');
                        if (overlay) {
                            overlay.remove();
                        }
                    '])
                    , 1200
                ])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:catch>
        </xsl:try>
            </xsl:otherwise>
        </xsl:choose>
	</xsl:template>

	<xsl:template name="show-overlay">
		<xsl:param name="event"/>
		<xsl:param name="overlay-id" as="xs:string"/>
		<xsl:param name="display" as="xs:string"/>
        <xsl:param name="inherited-subject" as="xs:string?"/>
        <xsl:param name="selected-text" as="xs:string?"/>

		<xsl:for-each select="id($overlay-id, ixsl:page())">
			<ixsl:set-style name="display" select="$display" object="."/>
            <xsl:if test="not($display = 'none')">
                <ixsl:set-style name="position" select="'fixed'" object="."/>

                <!-- Smart positioning: ensure overlay stays within viewport bounds -->
                <xsl:variable name="clientX" select="ixsl:get($event, 'clientX')"/>
                <xsl:variable name="clientY" select="ixsl:get($event, 'clientY')"/>
                <xsl:variable name="viewportWidth" select="ixsl:get(ixsl:window(), 'innerWidth')"/>
                <xsl:variable name="viewportHeight" select="ixsl:get(ixsl:window(), 'innerHeight')"/>

                <!-- Get overlay dimensions (use offsetWidth/Height after making visible) -->
                <xsl:variable name="overlayWidth" select="ixsl:get(., 'offsetWidth')"/>
                <xsl:variable name="overlayHeight" select="ixsl:get(., 'offsetHeight')"/>

                <!-- Calculate adjusted position to keep overlay in viewport -->
                <!-- Add 10px padding from edges -->
                <xsl:variable name="adjustedX" select="
                    if ($clientX + $overlayWidth + 10 > $viewportWidth)
                    then max(($viewportWidth - $overlayWidth - 10, 10))
                    else $clientX
                "/>
                <xsl:variable name="adjustedY" select="
                    if ($clientY + $overlayHeight + 10 > $viewportHeight)
                    then max(($viewportHeight - $overlayHeight - 10, 10))
                    else $clientY
                "/>

                <ixsl:set-style name="top" select="$adjustedY || 'px'" object="."/>
                <ixsl:set-style name="left" select="$adjustedX || 'px'" object="."/>

                <!-- Populate selected text preview -->
                <xsl:for-each select="id('selected-text-preview', ixsl:page())">
                    <ixsl:set-property name="textContent" select="if ($selected-text) then '&quot;' || $selected-text || '&quot;' else ''"/>
                </xsl:for-each>

                <!-- Populate inherited subject if available -->
                <xsl:for-each select="id('inherited-subject-section', ixsl:page())">
                    <ixsl:set-style name="display" select="if ($inherited-subject) then 'block' else 'none'"/>
                </xsl:for-each>
                <xsl:for-each select="id('inherited-subject-value', ixsl:page())">
                    <ixsl:set-property name="textContent" select="if ($inherited-subject) then $inherited-subject else ''"/>
                </xsl:for-each>
            </xsl:if>
		</xsl:for-each>
	</xsl:template>

    <!-- Pattern selector change handler -->
    <xsl:template match="input[@name='pattern']" mode="ixsl:onchange">
        <xsl:variable name="pattern" select="ixsl:get(., 'value')"/>

        <!-- Show/hide fields based on selected pattern -->
        <xsl:for-each select="id('subject-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'advanced') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('typeof-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'entity') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('object-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'advanced') then 'block' else 'none'"/>
        </xsl:for-each>
    </xsl:template>

    <!-- Value type selector change handler -->
    <xsl:template match="input[@name='value-type']" mode="ixsl:onchange">
        <xsl:variable name="is-custom" select="ixsl:get(., 'value') = 'custom'"/>

        <!-- Enable/disable custom value input based on which radio is selected -->
        <xsl:for-each select="id('custom-value-input', ixsl:page())">
            <xsl:choose>
                <xsl:when test="$is-custom">
                    <!-- Enable: remove disabled attribute -->
                    <ixsl:remove-attribute name="disabled"/>
                    <!-- Focus the input when enabled -->
                    <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
                </xsl:when>
                <xsl:otherwise>
                    <!-- Disable: set disabled attribute -->
                    <ixsl:set-attribute name="disabled" select="'disabled'"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
    </xsl:template>

    <!-- Cancel button handler -->
    <xsl:template match="button[tokenize(@class, ' ') = 'cancel-action']" mode="ixsl:onclick">
        <xsl:call-template name="show-overlay">
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'none'"/>
        </xsl:call-template>
    </xsl:template>

    <!-- Click handler for existing annotations - edit mode -->
    <xsl:template match="span[@property]" mode="ixsl:onclick">
        <xsl:variable name="event" select="ixsl:event()"/>

        <!-- Store reference to the span being edited -->
        <ixsl:set-property name="editingSpan" select="." object="ixsl:window()"/>
        <ixsl:set-property name="editMode" select="true()" object="ixsl:window()"/>

        <!-- Get existing RDFa values -->
        <xsl:variable name="existing-property" select="string(@property)"/>
        <xsl:variable name="existing-typeof" select="string(@typeof)"/>
        <xsl:variable name="existing-about" select="string(@about)"/>
        <xsl:variable name="existing-resource" select="string(@resource)"/>
        <xsl:variable name="existing-content" select="string(@content)"/>
        <xsl:variable name="existing-text" select="string(.)"/>

        <!-- Determine pattern based on existing attributes -->
        <xsl:variable name="pattern" select="
            if (@typeof) then 'entity'
            else if (@about or @resource) then 'advanced'
            else 'property'
        "/>

        <!-- Detect inherited subject for display -->
        <xsl:variable name="inherited-subject" select="local:get-inherited-subject(.)"/>

        <!-- Ensure overlay exists -->
        <xsl:if test="not(id('overlay', ixsl:page()))">
            <xsl:for-each select="ixsl:page()//body">
                <xsl:result-document href="?." method="ixsl:append-content">
                    <div id="overlay">
                        <div class="overlay-header">
                            <h3>Add RDFa Annotation</h3>
                            <span class="selected-text-preview" id="selected-text-preview"></span>
                        </div>
                        <form>
                            <!-- Pattern Selection -->
                            <div class="pattern-selector">
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="property" checked="checked"/>
                                    <span>Add Property</span>
                                </label>
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="entity"/>
                                    <span>Create Entity</span>
                                </label>
                                <label class="pattern-option">
                                    <input type="radio" name="pattern" value="advanced"/>
                                    <span>Advanced</span>
                                </label>
                            </div>

                            <!-- Inherited Subject Indicator -->
                            <div id="inherited-subject-section" class="inherited-context">
                                <div class="inherited-label">✓ Subject inherited from ancestor:</div>
                                <div id="inherited-subject-value" class="inherited-value"></div>
                            </div>

                            <!-- Subject Field (for advanced pattern) -->
                            <fieldset id="subject-fieldset" style="display: none;">
                                <label>Subject (about/resource)</label>
                                <input type="text" name="subject" placeholder="http://example.org/resource"/>
                                <span class="helper-text">URI or blank node identifier</span>
                            </fieldset>

                            <!-- Entity Type Field (for entity pattern) -->
                            <fieldset id="typeof-fieldset" style="display: none;">
                                <label>Entity Type (typeof)</label>
                                <select name="typeof">
                                    <option value="">-- Select type --</option>
                                    <optgroup label="Schema.org">
                                        <option value="http://schema.org/Person">Person</option>
                                        <option value="http://schema.org/Article">Article</option>
                                        <option value="http://schema.org/Organization">Organization</option>
                                        <option value="http://schema.org/Place">Place</option>
                                        <option value="http://schema.org/Event">Event</option>
                                    </optgroup>
                                    <optgroup label="FOAF">
                                        <option value="http://xmlns.com/foaf/0.1/Person">Person</option>
                                        <option value="http://xmlns.com/foaf/0.1/Document">Document</option>
                                        <option value="http://xmlns.com/foaf/0.1/Organization">Organization</option>
                                    </optgroup>
                                </select>
                                <span class="helper-text">Type of the resource being created</span>
                            </fieldset>

                            <!-- Property Field (all patterns) -->
                            <fieldset id="property-fieldset">
                                <label>Property</label>
                                <select name="property">
                                    <optgroup label="Schema.org (Common)">
                                        <option value="http://schema.org/name">name</option>
                                        <option value="http://schema.org/description">description</option>
                                        <option value="http://schema.org/author">author</option>
                                        <option value="http://schema.org/datePublished">datePublished</option>
                                        <option value="http://schema.org/url">url</option>
                                    </optgroup>
                                    <optgroup label="FOAF">
                                        <xsl:for-each select="document('vocabs/foaf.rdf')/rdf:RDF/rdf:Property">
                                            <xsl:sort select="@rdfs:label"/>
                                            <option value="{@rdf:about}">
                                                <xsl:value-of select="@rdfs:label"/>
                                            </option>
                                        </xsl:for-each>
                                    </optgroup>
                                    <optgroup label="Dublin Core">
                                        <option value="http://purl.org/dc/terms/title">title</option>
                                        <option value="http://purl.org/dc/terms/creator">creator</option>
                                        <option value="http://purl.org/dc/terms/created">created</option>
                                        <option value="http://purl.org/dc/terms/description">description</option>
                                    </optgroup>
                                    <option value="">-- Custom property --</option>
                                </select>
                                <span class="helper-text">The property/predicate to annotate</span>
                            </fieldset>

                            <!-- Value/Content Field -->
                            <fieldset id="value-fieldset">
                                <label>Value</label>
                                <div class="value-options">
                                    <label class="value-option">
                                        <input type="radio" name="value-type" value="text" checked="checked"/>
                                        <span>Use selected text</span>
                                    </label>
                                    <label class="value-option">
                                        <input type="radio" name="value-type" value="custom"/>
                                        <span>Custom value:</span>
                                    </label>
                                </div>
                                <input type="text" name="custom-value" id="custom-value-input" placeholder="Enter custom value" disabled="disabled"/>
                                <span class="helper-text">For dates, codes, or URIs different from display text</span>
                            </fieldset>

                            <!-- Object/Resource Field (for advanced pattern) -->
                            <fieldset id="object-fieldset" style="display: none;">
                                <label>Object/Resource</label>
                                <input type="text" name="object" placeholder="Value or URI"/>
                                <span class="helper-text">The value or resource URI</span>
                            </fieldset>

                            <!-- Action Buttons -->
                            <div class="action-buttons">
                                <button type="button" class="btn-primary spo-action">Annotate</button>
                                <button type="button" class="btn-secondary cancel-action">Cancel</button>
                            </div>
                        </form>
                    </div>
                </xsl:result-document>
            </xsl:for-each>
        </xsl:if>

        <!-- Pre-populate form fields with existing values -->
        <!-- Set pattern radio button -->
        <xsl:for-each select="ixsl:page()//input[@name='pattern'][@value = $pattern]">
            <ixsl:set-property name="checked" select="true()"/>
        </xsl:for-each>

        <!-- Set property value -->
        <xsl:for-each select="ixsl:page()//select[@name='property']">
            <ixsl:set-property name="value" select="$existing-property"/>
        </xsl:for-each>

        <!-- Set typeof value if exists -->
        <xsl:if test="$existing-typeof">
            <xsl:for-each select="ixsl:page()//select[@name='typeof']">
                <ixsl:set-property name="value" select="$existing-typeof"/>
            </xsl:for-each>
        </xsl:if>

        <!-- Set subject value if exists -->
        <xsl:if test="$existing-about">
            <xsl:for-each select="ixsl:page()//input[@name='subject']">
                <ixsl:set-property name="value" select="$existing-about"/>
            </xsl:for-each>
        </xsl:if>

        <!-- Set custom value if exists -->
        <xsl:if test="$existing-content">
            <xsl:for-each select="ixsl:page()//input[@name='value-type'][@value='custom']">
                <ixsl:set-property name="checked" select="true()"/>
            </xsl:for-each>
            <xsl:for-each select="ixsl:page()//input[@name='custom-value']">
                <ixsl:set-property name="value" select="$existing-content"/>
                <!-- Enable by removing disabled attribute -->
                <ixsl:remove-attribute name="disabled"/>
            </xsl:for-each>
        </xsl:if>

        <!-- Show/hide fieldsets based on pattern -->
        <xsl:for-each select="id('subject-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'advanced') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('typeof-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'entity') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('object-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'advanced') then 'block' else 'none'"/>
        </xsl:for-each>

        <!-- Show overlay at click position -->
        <xsl:call-template name="show-overlay">
            <xsl:with-param name="event" select="$event"/>
            <xsl:with-param name="overlay-id" select="'overlay'"/>
            <xsl:with-param name="display" select="'block'"/>
            <xsl:with-param name="inherited-subject" select="$inherited-subject"/>
            <xsl:with-param name="selected-text" select="$existing-text"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template match="button[@id = 'parse-rdf']" mode="ixsl:onclick">
        <!-- Extract RDF using the new XSLT 3.0 transformation -->
        <xsl:variable name="rdf-output">
            <xsl:call-template name="extract-rdfa"/>
        </xsl:variable>

        <!-- Serialize the RDF/XML to string -->
        <xsl:variable name="rdf-string" select="serialize($rdf-output, map{'method': 'xml', 'indent': true()})"/>

        <!-- Display in modal -->
        <xsl:for-each select="id('rdf-content', ixsl:page())">
            <ixsl:set-property name="textContent" select="$rdf-string"/>
        </xsl:for-each>

        <xsl:for-each select="id('rdf-modal', ixsl:page())">
            <ixsl:set-style name="display" select="'flex'"/>
        </xsl:for-each>
    </xsl:template>

    <!-- Modal close handler -->
    <xsl:template match="span[tokenize(@class, ' ') = 'modal-close']" mode="ixsl:onclick">
        <xsl:for-each select="id('rdf-modal', ixsl:page())">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:for-each>
    </xsl:template>

    <!-- Close modal when clicking outside -->
    <xsl:template match="div[@id = 'rdf-modal']" mode="ixsl:onclick">
        <xsl:variable name="target" select="ixsl:get(ixsl:event(), 'target')"/>
        <!-- Only close if clicking the modal backdrop, not the content -->
        <xsl:if test="ixsl:call($target, 'isSameNode', [.])">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:if>
    </xsl:template>

</xsl:stylesheet>