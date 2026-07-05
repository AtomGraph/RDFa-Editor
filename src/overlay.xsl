<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
xmlns="http://www.w3.org/1999/xhtml"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
xmlns:xs="http://www.w3.org/2001/XMLSchema"
xmlns:local="urn:rdfa-editor:functions"
extension-element-prefixes="ixsl"
xpath-default-namespace="http://www.w3.org/1999/xhtml"
version="3.0">

<!--
    The annotation overlay: rendered once at startup (hidden), then only populated,
    shown and hidden. Form state is read and written via live DOM properties
    (checked/value/disabled) - attributes never reflect user input.
-->

    <xsl:template name="local:init-overlay">
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <xsl:call-template name="local:render-overlay"/>
            </xsl:result-document>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:render-overlay">
        <div id="overlay" style="display: none;">
            <div class="overlay-header">
                <h3>RDFa Annotation</h3>
                <span id="selected-text-preview" class="selected-text-preview"/>
            </div>
            <form id="annotation-form">
                <div class="pattern-selector">
                    <label class="pattern-option">
                        <input type="radio" name="pattern" value="property" checked="checked"/>
                        <span>Add property</span>
                    </label>
                    <label class="pattern-option">
                        <input type="radio" name="pattern" value="entity"/>
                        <span>Create entity</span>
                    </label>
                    <label class="pattern-option">
                        <input type="radio" name="pattern" value="advanced"/>
                        <span>Advanced</span>
                    </label>
                </div>

                <div id="inherited-subject-section" class="inherited-context">
                    <div class="inherited-label">Subject in scope:</div>
                    <div id="inherited-subject-value" class="inherited-value"/>
                </div>

                <fieldset id="subject-fieldset" style="display: none;">
                    <label>Subject (about)</label>
                    <input type="text" name="subject" placeholder="https://example.org/resource"/>
                    <span class="helper-text">IRI or _:blank-node identifier</span>
                </fieldset>

                <fieldset id="typeof-fieldset" style="display: none;">
                    <label>Entity type (typeof)</label>
                    <select name="typeof">
                        <xsl:call-template name="local:vocab-options">
                            <xsl:with-param name="hrefs" select="$vocab-hrefs"/>
                            <xsl:with-param name="kind" select="'class'"/>
                        </xsl:call-template>
                        <option value="">-- Custom type --</option>
                    </select>
                    <input type="text" name="custom-type" placeholder="Type IRI" style="display: none;"/>
                    <span class="helper-text">Type of the resource being described</span>
                </fieldset>

                <fieldset id="property-fieldset">
                    <label>Property</label>
                    <select name="property">
                        <xsl:call-template name="local:vocab-options">
                            <xsl:with-param name="hrefs" select="$vocab-hrefs"/>
                            <xsl:with-param name="kind" select="'property'"/>
                        </xsl:call-template>
                        <option value="">-- Custom property --</option>
                    </select>
                    <input type="text" name="custom-property" placeholder="Property IRI" style="display: none;"/>
                    <span class="helper-text">The predicate to annotate with</span>
                </fieldset>

                <fieldset id="value-fieldset">
                    <label>Value</label>
                    <div class="value-options">
                        <label class="value-option">
                            <input type="radio" name="value-type" value="text" checked="checked"/>
                            <span>Use selected text</span>
                        </label>
                        <label class="value-option">
                            <input type="radio" name="value-type" value="custom"/>
                            <span>Custom value (content)</span>
                        </label>
                    </div>
                    <input type="text" name="custom-value" id="custom-value-input"
                           placeholder="Machine-readable value" disabled="disabled"/>
                    <span class="helper-text">For dates, codes or IRIs different from the display text</span>
                </fieldset>

                <fieldset id="object-fieldset" style="display: none;">
                    <label>Object (resource)</label>
                    <input type="text" name="object" placeholder="Object IRI"/>
                    <span class="helper-text">Resource IRI the property points to</span>
                </fieldset>

                <div class="action-buttons">
                    <button type="button" class="btn-danger remove-action" style="display: none;">Remove</button>
                    <button type="button" class="btn-primary spo-action">Annotate</button>
                    <button type="button" class="btn-secondary cancel-action">Cancel</button>
                </div>
            </form>
        </div>
    </xsl:template>

    <!-- all form reads via live properties: the checked/value attributes never change on user input -->
    <xsl:function name="local:form-values" as="map(xs:string, xs:string?)">
        <xsl:param name="form" as="element()"/>

        <xsl:map>
            <xsl:map-entry key="'pattern'"
                select="($form//input[@name = 'pattern'])[ixsl:get(., 'checked')] ! string(ixsl:get(., 'value'))"/>
            <xsl:map-entry key="'property'" select="local:select-or-custom($form, 'property', 'custom-property')"/>
            <xsl:map-entry key="'typeof'" select="local:select-or-custom($form, 'typeof', 'custom-type')"/>
            <xsl:map-entry key="'subject'"
                select="string(ixsl:get(($form//input[@name = 'subject'])[1], 'value'))[. ne '']"/>
            <xsl:map-entry key="'object'"
                select="string(ixsl:get(($form//input[@name = 'object'])[1], 'value'))[. ne '']"/>
            <xsl:map-entry key="'value-type'"
                select="($form//input[@name = 'value-type'])[ixsl:get(., 'checked')] ! string(ixsl:get(., 'value'))"/>
            <xsl:map-entry key="'content'"
                select="string(ixsl:get(($form//input[@name = 'custom-value'])[1], 'value'))[. ne '']"/>
        </xsl:map>
    </xsl:function>

    <!-- a select whose empty value defers to its free-text custom input -->
    <xsl:function name="local:select-or-custom" as="xs:string?">
        <xsl:param name="form" as="element()"/>
        <xsl:param name="select-name" as="xs:string"/>
        <xsl:param name="custom-name" as="xs:string"/>

        <xsl:variable name="value" as="xs:string"
            select="string(ixsl:get(($form//select[@name = $select-name])[1], 'value'))"/>
        <xsl:sequence select="if ($value ne '') then $value
            else string(ixsl:get(($form//input[@name = $custom-name])[1], 'value'))[. ne '']"/>
    </xsl:function>

    <!-- the annotation pattern implied by an annotated element's attributes -->
    <xsl:function name="local:span-pattern" as="xs:string">
        <xsl:param name="span" as="element()"/>

        <xsl:sequence select="if ($span/@typeof) then 'entity'
            else if ($span/@about or $span/@resource) then 'advanced'
            else 'property'"/>
    </xsl:function>

    <!-- reset the form; when editing, pre-fill it from the annotated element -->
    <xsl:template name="local:populate-form">
        <xsl:param name="span" as="element()?" select="()"/>

        <xsl:for-each select="id('annotation-form', ixsl:page())">
            <xsl:sequence select="ixsl:call(., 'reset', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:for-each select=".//input[@name = ('custom-property', 'custom-type')]">
                <ixsl:set-style name="display" select="'none'"/>
            </xsl:for-each>
            <xsl:for-each select=".//button[tokenize(@class) = 'remove-action']">
                <ixsl:set-style name="display" select="if (exists($span)) then 'inline-block' else 'none'"/>
            </xsl:for-each>
            <!-- reset() restores attribute defaults only - disabled is a live property -->
            <xsl:for-each select=".//input[@name = 'custom-value']">
                <ixsl:set-property name="disabled" select="true()" object="."/>
            </xsl:for-each>

            <xsl:for-each select="$span">
                    <xsl:variable name="form" as="element()" select="id('annotation-form', ixsl:page())"/>
                    <xsl:for-each select="$form//input[@name = 'pattern'][@value = local:span-pattern($span)]">
                        <ixsl:set-property name="checked" select="true()" object="."/>
                    </xsl:for-each>
                    <xsl:for-each select="@property">
                        <xsl:call-template name="local:set-select-or-custom">
                            <xsl:with-param name="form" select="$form"/>
                            <xsl:with-param name="select-name" select="'property'"/>
                            <xsl:with-param name="custom-name" select="'custom-property'"/>
                            <xsl:with-param name="value" select="string(.)"/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <xsl:for-each select="@typeof">
                        <xsl:call-template name="local:set-select-or-custom">
                            <xsl:with-param name="form" select="$form"/>
                            <xsl:with-param name="select-name" select="'typeof'"/>
                            <xsl:with-param name="custom-name" select="'custom-type'"/>
                            <xsl:with-param name="value" select="string(.)"/>
                        </xsl:call-template>
                    </xsl:for-each>
                    <xsl:for-each select="$form//input[@name = 'subject']">
                        <ixsl:set-property name="value" select="string($span/@about)" object="."/>
                    </xsl:for-each>
                    <xsl:for-each select="$form//input[@name = 'object']">
                        <ixsl:set-property name="value" select="string($span/@resource)" object="."/>
                    </xsl:for-each>
                    <xsl:if test="@content">
                        <xsl:for-each select="$form//input[@name = 'value-type'][@value = 'custom']">
                            <ixsl:set-property name="checked" select="true()" object="."/>
                        </xsl:for-each>
                        <xsl:for-each select="$form//input[@name = 'custom-value']">
                            <ixsl:set-property name="disabled" select="false()" object="."/>
                            <ixsl:set-property name="value" select="string($span/@content)" object="."/>
                        </xsl:for-each>
                    </xsl:if>
                </xsl:for-each>
        </xsl:for-each>
    </xsl:template>

    <!-- set a select's value via the live property; an IRI absent from the options
         leaves the select empty, so route it to the custom input instead -->
    <xsl:template name="local:set-select-or-custom">
        <xsl:param name="form" as="element()"/>
        <xsl:param name="select-name" as="xs:string"/>
        <xsl:param name="custom-name" as="xs:string"/>
        <xsl:param name="value" as="xs:string"/>

        <xsl:for-each select="($form//select[@name = $select-name])[1]">
            <ixsl:set-property name="value" select="$value" object="."/>
            <xsl:if test="string(ixsl:get(., 'value')) ne $value">
                <ixsl:set-property name="value" select="''" object="."/>
                <xsl:for-each select="($form//input[@name = $custom-name])[1]">
                    <ixsl:set-property name="value" select="$value" object="."/>
                    <ixsl:set-style name="display" select="'block'"/>
                </xsl:for-each>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:update-form-visibility">
        <xsl:param name="pattern" as="xs:string"/>

        <xsl:for-each select="id('subject-fieldset', ixsl:page()) | id('object-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'advanced') then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('typeof-fieldset', ixsl:page())">
            <ixsl:set-style name="display" select="if ($pattern = 'entity') then 'block' else 'none'"/>
        </xsl:for-each>
    </xsl:template>

    <!-- show at the event position, clamped to the viewport with 10px padding.
         Positioned absolutely in page coordinates (client + scroll offset) so the
         overlay scrolls with the annotated content -->
    <xsl:template name="local:show-overlay">
        <xsl:param name="event"/>
        <xsl:param name="selected-text" as="xs:string?" select="()"/>
        <xsl:param name="in-scope-subject" as="xs:string?" select="()"/>

        <xsl:for-each select="id('overlay', ixsl:page())">
            <ixsl:set-style name="display" select="'block'"/>
            <ixsl:set-style name="position" select="'absolute'"/>

            <xsl:variable name="client-x" as="xs:double" select="ixsl:get($event, 'clientX')"/>
            <xsl:variable name="client-y" as="xs:double" select="ixsl:get($event, 'clientY')"/>
            <xsl:variable name="scroll-x" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollX')"/>
            <xsl:variable name="scroll-y" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollY')"/>
            <xsl:variable name="viewport-width" as="xs:double" select="ixsl:get(ixsl:window(), 'innerWidth')"/>
            <xsl:variable name="viewport-height" as="xs:double" select="ixsl:get(ixsl:window(), 'innerHeight')"/>
            <xsl:variable name="overlay-width" as="xs:double" select="ixsl:get(., 'offsetWidth')"/>
            <xsl:variable name="overlay-height" as="xs:double" select="ixsl:get(., 'offsetHeight')"/>

            <ixsl:set-style name="left" select="((if ($client-x + $overlay-width + 10 gt $viewport-width)
                then max(($viewport-width - $overlay-width - 10, 10)) else $client-x) + $scroll-x) || 'px'"/>
            <ixsl:set-style name="top" select="((if ($client-y + $overlay-height + 10 gt $viewport-height)
                then max(($viewport-height - $overlay-height - 10, 10)) else $client-y) + $scroll-y) || 'px'"/>
        </xsl:for-each>

        <xsl:for-each select="id('selected-text-preview', ixsl:page())">
            <ixsl:set-property name="textContent" object="."
                select="($selected-text[. ne ''] ! ('&#x201C;' || . || '&#x201D;'), '')[1]"/>
        </xsl:for-each>
        <xsl:for-each select="id('inherited-subject-section', ixsl:page())">
            <ixsl:set-style name="display" select="if (exists($in-scope-subject)) then 'block' else 'none'"/>
        </xsl:for-each>
        <xsl:for-each select="id('inherited-subject-value', ixsl:page())">
            <ixsl:set-property name="textContent" select="($in-scope-subject, '')[1]" object="."/>
        </xsl:for-each>
    </xsl:template>

    <!-- single teardown point: hiding the overlay always clears the interaction state -->
    <xsl:template name="local:hide-overlay">
        <xsl:for-each select="id('overlay', ixsl:page())">
            <ixsl:set-style name="display" select="'none'"/>
        </xsl:for-each>
        <ixsl:set-property name="editingSpan" select="()" object="ixsl:window()"/>
        <ixsl:set-property name="range" select="()" object="ixsl:window()"/>
    </xsl:template>

    <xsl:template match="input[@name = 'pattern']" mode="ixsl:onchange">
        <xsl:call-template name="local:update-form-visibility">
            <xsl:with-param name="pattern" select="ixsl:get(., 'value')"/>
        </xsl:call-template>
    </xsl:template>

    <xsl:template match="input[@name = 'value-type']" mode="ixsl:onchange">
        <xsl:variable name="custom" as="xs:boolean" select="ixsl:get(., 'value') = 'custom'"/>
        <xsl:for-each select="id('custom-value-input', ixsl:page())">
            <ixsl:set-property name="disabled" select="not($custom)" object="."/>
            <xsl:if test="$custom">
                <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <!-- the empty 'Custom' option reveals the free-text IRI input -->
    <xsl:template match="select[@name = ('property', 'typeof')]" mode="ixsl:onchange">
        <xsl:variable name="custom-name" as="xs:string"
            select="if (@name = 'property') then 'custom-property' else 'custom-type'"/>
        <xsl:variable name="custom" as="xs:boolean" select="string(ixsl:get(., 'value')) eq ''"/>
        <xsl:for-each select="ancestor::form//input[@name = $custom-name]">
            <ixsl:set-style name="display" select="if ($custom) then 'block' else 'none'"/>
            <xsl:if test="$custom">
                <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

</xsl:stylesheet>
