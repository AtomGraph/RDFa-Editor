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

    <!-- select value marking the free-text custom-IRI state ('' means none/unset) -->
    <xsl:variable name="local:custom" as="xs:string" select="'urn:rdfa-editor:custom'"/>

<!--
    The annotation overlay: rendered once at startup (hidden), then only populated,
    shown and hidden. The form is framed as the statement being asserted - subject,
    predicate, object rows - with type/subject/object overrides in a details
    disclosure. There is no mode selection: the emitted RDFa attributes follow from
    which fields are filled. Form state is read and written via live DOM properties
    (checked/value/disabled/open) - attributes never reflect user input.
-->

    <xsl:template name="local:init-overlay">
        <xsl:for-each select="ixsl:page()//body">
            <xsl:result-document href="?." method="ixsl:append-content">
                <xsl:call-template name="local:render-overlay"/>
            </xsl:result-document>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:render-overlay">
        <!-- the host page preloaded these into the document pool under page-relative URIs -->
        <xsl:variable name="vocab-uris" as="xs:string*"
            select="$vocab-hrefs ! string(resolve-uri(., ixsl:location()))"/>

        <div id="overlay" style="display: none;">
            <div class="overlay-header">
                <h3>RDFa Annotation</h3>
            </div>
            <form id="annotation-form">
                <div class="statement">
                    <span class="stmt-role" title="Subject">S</span>
                    <div id="stmt-subject" class="stmt-value"/>
                    <span class="stmt-role" title="Predicate">P</span>
                    <div class="stmt-control">
                        <select name="property">
                            <xsl:call-template name="local:vocab-options">
                                <xsl:with-param name="hrefs" select="$vocab-uris"/>
                                <xsl:with-param name="kind" select="'property'"/>
                            </xsl:call-template>
                            <option value="{$local:custom}">-- Custom property --</option>
                        </select>
                        <input type="text" name="custom-property" placeholder="Property IRI" style="display: none;"/>
                    </div>
                    <span class="stmt-role" title="Object">O</span>
                    <div class="stmt-control">
                        <input type="text" name="value" placeholder="Literal value"/>
                        <span class="helper-text">The selected text; change it to emit a machine-readable content value</span>
                    </div>
                </div>

                <details id="advanced-fields">
                    <summary>Type, subject &amp; object</summary>
                    <fieldset>
                        <label>Entity type (typeof)</label>
                        <select name="typeof">
                            <option value="">(none)</option>
                            <xsl:call-template name="local:vocab-options">
                                <xsl:with-param name="hrefs" select="$vocab-uris"/>
                                <xsl:with-param name="kind" select="'class'"/>
                            </xsl:call-template>
                            <option value="{$local:custom}">-- Custom type --</option>
                        </select>
                        <input type="text" name="custom-type" placeholder="Type IRI" style="display: none;"/>
                        <span class="helper-text">Types the annotated resource; without a subject the typed
                            resource becomes the object of the property (chaining)</span>
                    </fieldset>
                    <fieldset>
                        <label>Subject (about)</label>
                        <input type="text" name="subject" placeholder="Overrides the subject in scope"/>
                        <span class="helper-text">IRI or _:blank-node identifier</span>
                    </fieldset>
                    <fieldset>
                        <label>Object (resource)</label>
                        <input type="text" name="object" placeholder="Object IRI"/>
                        <span class="helper-text">Makes the object a resource instead of the literal value</span>
                    </fieldset>
                </details>

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
            <xsl:map-entry key="'property'" select="local:select-or-custom($form, 'property', 'custom-property')"/>
            <xsl:map-entry key="'typeof'" select="local:select-or-custom($form, 'typeof', 'custom-type')"/>
            <xsl:map-entry key="'subject'"
                select="string(ixsl:get(($form//input[@name = 'subject'])[1], 'value'))[. ne '']"/>
            <xsl:map-entry key="'object'"
                select="string(ixsl:get(($form//input[@name = 'object'])[1], 'value'))[. ne '']"/>
            <xsl:map-entry key="'value'"
                select="string(ixsl:get(($form//input[@name = 'value'])[1], 'value'))[. ne '']"/>
        </xsl:map>
    </xsl:function>

    <!-- a select whose empty value defers to its free-text custom input -->
    <xsl:function name="local:select-or-custom" as="xs:string?">
        <xsl:param name="form" as="element()"/>
        <xsl:param name="select-name" as="xs:string"/>
        <xsl:param name="custom-name" as="xs:string"/>

        <xsl:variable name="value" as="xs:string"
            select="string(ixsl:get(($form//select[@name = $select-name])[1], 'value'))"/>
        <xsl:sequence select="if ($value eq $local:custom)
            then string(ixsl:get(($form//input[@name = $custom-name])[1], 'value'))[. ne '']
            else $value[. ne '']"/>
    </xsl:function>

    <!-- reset the form; when editing, pre-fill it from the annotated element.
         $value prefills the object row: the selected text, or @content/text when editing -->
    <xsl:template name="local:populate-form">
        <xsl:param name="span" as="element()?" select="()"/>
        <xsl:param name="value" as="xs:string?" select="()"/>

        <xsl:for-each select="id('annotation-form', ixsl:page())">
            <xsl:variable name="form" as="element()" select="."/>
            <xsl:sequence select="ixsl:call(., 'reset', [])[current-date() lt xs:date('2000-01-01')]"/>
            <xsl:for-each select=".//input[@name = ('custom-property', 'custom-type')]">
                <ixsl:set-style name="display" select="'none'"/>
            </xsl:for-each>
            <xsl:for-each select=".//button[tokenize(@class) = 'remove-action']">
                <ixsl:set-style name="display" select="if (exists($span)) then 'inline-block' else 'none'"/>
            </xsl:for-each>
            <xsl:for-each select=".//input[@name = 'value']">
                <ixsl:set-property name="value" select="($value, '')[1]" object="."/>
            </xsl:for-each>
            <!-- disclose the advanced fields when the annotation carries any of them -->
            <xsl:for-each select="id('advanced-fields', ixsl:page())">
                <ixsl:set-property name="open" select="exists($span/(@about | @resource | @typeof))" object="."/>
            </xsl:for-each>

            <xsl:for-each select="$span">
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
                <ixsl:set-property name="value" select="$local:custom" object="."/>
                <xsl:for-each select="($form//input[@name = $custom-name])[1]">
                    <ixsl:set-property name="value" select="$value" object="."/>
                    <ixsl:set-style name="display" select="'block'"/>
                </xsl:for-each>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

    <!-- show an element at the event position, clamped to the viewport with 10px
         padding. Positioned absolutely in page coordinates (client + scroll offset)
         so it scrolls with the content -->
    <xsl:template name="local:show-at">
        <xsl:param name="element" as="element()"/>
        <xsl:param name="event"/>

        <xsl:for-each select="$element">
            <ixsl:set-style name="display" select="'block'"/>
            <ixsl:set-style name="position" select="'absolute'"/>

            <xsl:variable name="client-x" as="xs:double" select="ixsl:get($event, 'clientX')"/>
            <xsl:variable name="client-y" as="xs:double" select="ixsl:get($event, 'clientY')"/>
            <xsl:variable name="scroll-x" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollX')"/>
            <xsl:variable name="scroll-y" as="xs:double" select="ixsl:get(ixsl:window(), 'scrollY')"/>
            <xsl:variable name="viewport-width" as="xs:double" select="ixsl:get(ixsl:window(), 'innerWidth')"/>
            <xsl:variable name="viewport-height" as="xs:double" select="ixsl:get(ixsl:window(), 'innerHeight')"/>
            <xsl:variable name="width" as="xs:double" select="ixsl:get(., 'offsetWidth')"/>
            <xsl:variable name="height" as="xs:double" select="ixsl:get(., 'offsetHeight')"/>

            <ixsl:set-style name="left" select="((if ($client-x + $width + 10 gt $viewport-width)
                then max(($viewport-width - $width - 10, 10)) else $client-x) + $scroll-x) || 'px'"/>
            <ixsl:set-style name="top" select="((if ($client-y + $height + 10 gt $viewport-height)
                then max(($viewport-height - $height - 10, 10)) else $client-y) + $scroll-y) || 'px'"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template name="local:show-overlay">
        <xsl:param name="event"/>
        <xsl:param name="in-scope-subject" as="xs:string?" select="()"/>

        <xsl:call-template name="local:show-at">
            <xsl:with-param name="element" select="id('overlay', ixsl:page())"/>
            <xsl:with-param name="event" select="$event"/>
        </xsl:call-template>

        <xsl:for-each select="id('stmt-subject', ixsl:page())">
            <ixsl:set-attribute name="data-inherited-subject" select="($in-scope-subject, '')[1]"/>
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

    <!-- a subject override is reflected in the statement's S row -->
    <xsl:template match="input[@name = 'subject']" mode="ixsl:onchange">
        <xsl:variable name="value" as="xs:string" select="string(ixsl:get(., 'value'))"/>
        <xsl:for-each select="id('stmt-subject', ixsl:page())">
            <ixsl:set-property name="textContent"
                select="($value[. ne ''], string(@data-inherited-subject))[1]" object="."/>
        </xsl:for-each>
    </xsl:template>

    <!-- the empty 'Custom' option reveals the free-text IRI input -->
    <xsl:template match="select[@name = ('property', 'typeof')]" mode="ixsl:onchange">
        <xsl:variable name="custom-name" as="xs:string"
            select="if (@name = 'property') then 'custom-property' else 'custom-type'"/>
        <xsl:variable name="custom" as="xs:boolean" select="string(ixsl:get(., 'value')) eq $local:custom"/>
        <xsl:for-each select="ancestor::form//input[@name = $custom-name]">
            <ixsl:set-style name="display" select="if ($custom) then 'block' else 'none'"/>
            <xsl:if test="$custom">
                <xsl:sequence select="ixsl:call(., 'focus', [])[current-date() lt xs:date('2000-01-01')]"/>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>

</xsl:stylesheet>
