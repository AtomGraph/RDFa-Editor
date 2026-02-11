# RDFa Editor Implementation Plan

**Total Budget:** €39,000
**Total Hours:** 520 hours
**Average Rate:** €75/hour
**Timeline:** 4 months

## Budget Allocation Summary

| Phase | Hours | Cost | Components |
|-------|-------|------|------------|
| **Phase 1** | 248h | €18,600 | RDF extraction (65h, 80% common cases), basic HTML editing, text annotation, autocomplete, testing |
| **Phase 2** | 213h | €15,975 | Advanced HTML (tables - add/remove only), drag-and-drop, advanced modal, testing |
| **Contingency** | 59h | €4,425 | 13% buffer for unknowns and edge cases |
| **Total** | 520h | €39,000 | Realistic RDFa editor MVP |

**Key Decisions:**
- **Pragmatic RDFa scope:** Target 80% common use cases (Schema.org, basic FOAF, Dublin Core) rather than full W3C test suite compliance. Defers complex features like `@vocab`, `@rel`/`@rev` chaining, and safe CURIEs to Phase 3.
- **Simplified tables:** Include only add/remove rows/columns. Defer merge/split cells to Phase 3.
- **Realistic contingency:** 59 hours (13%) for unexpected issues vs original 1 hour.
- **XSLT 3.0 rewrite justified:** The existing `src/RDFa2RDFXML.xsl` is XSLT 1.0 from 2009, pre-dates RDFa 1.1. Clean rewrite provides maintainable foundation.

---

## Phase 1: Core Functionality (€18,600 - 2 months)

Basic functional editor with essential annotation capabilities. RDFa extraction targets 80% common use cases (Schema.org, basic FOAF, Dublin Core).

### 1. RDFa Visual Styling

**Hours:** 6
**Cost:** €450
**Complexity:** 3/10

#### Description
CSS styling to visually distinguish RDFa-annotated elements from plain HTML. Renders elements with `typeof` attribute as distinct blocks with borders and color-coded type badges.

#### Implementation Notes
- CSS for `[typeof]`, `[property]`, `[resource]` selectors
- Color-coded badges by type category (Person=blue, Event=purple, etc.)
- Border styles for resource blocks
- Highlight on hover
- Simple CSS-only, no JavaScript/IXSL needed

#### Rationale
Start with visual feedback early so developers can see annotated content during development. Simplest feature to implement.

---

### 2. Vocabulary Selector

**Hours:** 8
**Cost:** €600
**Complexity:** 2/10

#### Description
Dropdown selector to switch between vocabularies (Schema.org, FOAF, Dublin Core, etc.). Loads vocabulary data via 3rd party library (rdflib.js) on selection.

#### Implementation Notes
- Simple `<select>` dropdown in toolbar
- IXSL event handler on change
- Load vocabulary via rdflib.js `parse()`
- Cache loaded vocabularies
- Store current vocabulary in global variable

#### Rationale
Need vocabularies loaded before implementing annotation UI. Simple dropdown with lazy loading pattern.

---

### 3. Multiple Export Formats

**Hours:** 4
**Cost:** €300
**Complexity:** 1/10

#### Description
Export RDF graph in multiple serialization formats: RDF/XML (via existing XSLT), then convert to Turtle, JSON-LD, N-Triples using rdflib.js.

#### Implementation Notes
- RDF/XML export already exists (RDFa2RDFXML.xsl)
- Parse RDF/XML with rdflib.js
- Use rdflib.js serializers for other formats
- Button in toolbar with format dropdown

#### Rationale
Quick win - leverages existing XSLT and rdflib.js capabilities. Trivial implementation.

---

### 4. RDF Graph Extraction from DOM (XSLT 3.0 Rewrite)

**Hours:** 65
**Cost:** €4,875
**Complexity:** 8/10

#### Description
Pragmatic XSLT 3.0 rewrite targeting 80% common RDFa use cases. Handles Schema.org microdata patterns, basic FOAF, and simple Dublin Core. Defers complex RDFa 1.1 edge cases to Phase 3.

#### Why Rewrite (Not Extend)?

The existing `src/RDFa2RDFXML.xsl` has fundamental issues:
- **XSLT 1.0** (written in 2009) - incompatible with SaxonJS 3.0 patterns
- **Pre-dates RDFa 1.1** (2012 spec) - missing features like `@prefix` attribute
- **Poor maintainability** - deeply nested recursive templates, debug code
- **Can't leverage XSLT 3.0** - no maps, arrays, higher-order functions

A pragmatic XSLT 3.0 rewrite provides:
- Covers 80% real-world RDFa use cases
- Modern, maintainable code
- Better performance
- Room to add advanced features later (Phase 3)

#### Implementation Plan

**Week 1-2: Foundation & Setup (15 hours)**
- Review W3C RDFa 1.1 Core spec (focus on common patterns)
- Review real-world Schema.org examples
- Design XSLT 3.0 project structure with modes and functions
- Create base templates and processing pipeline
- Define simple context tracking (subject inheritance)

**Week 3-4: Core Triple Extraction (30 hours)**

*Subject Resolution (simple cases):*
- Explicit subjects via `@about` attribute
- Implicit subjects from `@typeof` (basic blank nodes)
- Basic subject inheritance from parent
- `@src` attribute for images
- Fragment identifiers (`#id`)

*Property Extraction (`@property`):*
- Plain literal values (text content)
- `@content` attribute override
- Basic `@datatype` (xsd:string, xsd:integer, xsd:date)
- Language tags via `@xml:lang`

*Resource References:*
- `@resource` for object URIs
- `@href` for links

*Type Declaration:*
- `@typeof` for rdf:type triples
- Multiple types (space-separated)

**Week 5: Prefix & URI Handling (12 hours)**

*Prefix Management (simple):*
- `@prefix` attribute parsing (`prefix: http://...`)
- Legacy `xmlns:prefix` namespace declarations (basic)
- Common prefixes: schema, foaf, dc
- Absolute URI pass-through

*CURIE Resolution (basic):*
- Simple prefix:term expansion
- Fragment identifiers
- Relative URI resolution

**Week 6: Testing & Polish (8 hours)**

*Testing Focus:*
- Schema.org common patterns (Person, Event, Product, Article)
- Basic FOAF (Person, knows, homepage)
- Simple Dublin Core (title, creator, date)
- Test with real-world annotated pages
- Cross-browser testing (Firefox, Chrome)

*Edge Cases (prioritized):*
- Empty attribute values
- Missing prefixes (graceful fallback)
- Basic nested contexts (2-3 levels)

#### XSLT 3.0 Technical Advantages

- **`xsl:map` and `xsl:array`**: Proper data structures for context stacks and prefix mappings
- **User-defined functions** (`xsl:function`): Modular, testable CURIE resolution and subject determination
- **`xsl:iterate`**: More efficient than recursive templates for list processing
- **Higher-order functions**: Clean predicate/object handling with `xsl:for-each` and lambda expressions
- **`xsl:accumulator`**: Elegant context inheritance tracking
- **Type safety**: Static typing catches errors during compilation
- **Built-in assertions**: Development-time validation of invariants

#### What's Included (80% Common Cases)

✓ `@property` for literal properties
✓ `@typeof` for type declarations
✓ `@about` for explicit subjects
✓ `@content` for machine-readable values
✓ `@datatype` (common XSD types: string, integer, date, boolean)
✓ `@resource` and `@href` for object URIs
✓ `@prefix` attribute (simple namespace mappings)
✓ `xmlns:` namespace declarations (basic)
✓ `@xml:lang` language tags
✓ Subject inheritance (parent context)
✓ Fragment identifiers (`#id`)
✓ Multiple values (space-separated)
✓ Blank node generation (basic)

**Covers:** Schema.org microdata patterns, basic FOAF, simple Dublin Core

#### Deferred to Phase 3

✗ `@vocab` default vocabulary
✗ `@rel`/`@rev` incomplete triple chaining
✗ Safe CURIEs `[prefix:term]` vs bare keywords
✗ Complex blank node scenarios
✗ W3C RDFa 1.1 full test suite compliance
✗ Reserved keyword handling
✗ XML Literal support for nested HTML
✗ Term mappings
✗ Advanced prefix conflict resolution

#### Deliverables

- Clean, well-documented XSLT 3.0 codebase (~500 lines)
- Handles common real-world RDFa patterns
- Outputs valid, well-formed RDF/XML
- Performance: <100ms extraction for typical documents
- Test suite with 15+ Schema.org examples
- Inline code comments

#### Rationale

Foundation for entire editor. Focus on real-world patterns (Schema.org dominant) rather than spec edge cases. Can add advanced features incrementally in Phase 3. This pragmatic scope makes 65h realistic.

---

### 5. Basic HTML Editing

**Hours:** 45
**Cost:** €3,375
**Complexity:** 7/10

#### Description
Insert and edit basic HTML elements: paragraphs (p), headings (h1-h3), lists (ul/ol→li), links (a), images (img). Uses contenteditable with IXSL event handlers.

#### Implementation Notes
- Toolbar buttons for each element type
- IXSL click handlers to insert elements
- Use `document.execCommand` where possible (heading, paragraph)
- Custom handlers for:
  - Lists: ensure `<li>` children, proper nesting
  - Links: prompt for URL, set `href`
  - Images: prompt for URL/alt, insert `<img>`
- Preserve RDFa attributes when transforming elements
- Handle cursor positioning after insertion

#### Rationale
Need content to annotate. Start with simple elements before tackling tables. Each element type needs specific handling logic.

---

### 6. Text Selection to RDFa Wrapping

**Hours:** 35
**Cost:** €2,625
**Complexity:** 6/10

#### Description
Capture browser selection range, wrap selected text in `<span>` element, apply RDFa attributes atomically while preserving surrounding DOM structure.

#### Implementation Notes
- Get selection via `window.getSelection()`
- Extract `Range` object
- Handle edge cases:
  - Partial text node selection
  - Selection spans multiple elements
  - Selection crosses existing RDFa boundaries
  - Empty selections
- Create `<span>` wrapper
- Apply RDFa attributes (`@property`, `@resource`, `@typeof`, `@content`)
- Use `Range.surroundContents()` or manual extraction/insertion
- Don't break existing RDFa context

#### Rationale
Core annotation mechanism. Browser Selection API has many edge cases. Must be robust to avoid corrupting DOM.

---

### 7. Property/Type Autocomplete

**Hours:** 20
**Cost:** €1,500
**Complexity:** 4/10

#### Description
Dropdown with keyboard navigation to filter vocabulary terms by prefix match. Display property/class labels, descriptions, and URIs from loaded vocabulary.

#### Implementation Notes
- Input field with keyup handler (IXSL)
- Filter vocabulary via XPath: `//*[starts-with(local-name(), $input)]`
- Display matches in dropdown
- Keyboard navigation (up/down arrows, enter to select)
- Show: label, description, full URI
- Insert selected CURIE into form field
- Highlight matched prefix

#### Rationale
Makes annotation usable - users need to discover available properties. Standard autocomplete pattern, simplified by XPath filtering.

---

### 8. Annotation Modal (Basic)

**Hours:** 20
**Cost:** €1,500
**Complexity:** 6/10

#### Description
Modal dialog for creating RDFa annotations. Initial version: single "Property" tab with basic form fields. Handles literal vs resource object toggle, subject selection, field validation.

#### Implementation Notes
- Modal overlay with IXSL show/hide handlers
- Display selected text
- Form fields:
  - Subject: dropdown (current context / custom URI / blank node)
  - Property: autocomplete input
  - Object type: radio (literal / resource)
  - Object value: text input (literal) or URI input (resource)
- "Apply" button disabled until property selected
- On submit:
  - Call text wrapping function
  - Apply RDFa attributes based on form state
  - Close modal

#### Rationale
Central UI for annotation. Start with simple single-tab version. Form logic for object type toggle and validation.

---

### Testing & Debugging (Phase 1)

**Hours:** 45
**Cost:** €3,375

#### Activities
- Integration testing of core workflow
- Test RDF extraction with various annotation patterns
- Test HTML editing with RDFa preservation
- Browser compatibility testing (Firefox, Chrome)
- Fix bugs discovered during testing
- Edge case handling for selection/wrapping

---

## Phase 2: Advanced Features (€15,975 - 2 additional months)

Complex HTML structures (simplified tables), drag-and-drop, and full annotation capabilities.

### 9. Annotation Modal (Advanced)

**Hours:** 15
**Cost:** €1,125
**Complexity:** 6/10

#### Description
Extend annotation modal with additional tabs for Type declarations and Resource creation. Add content override field for machine-readable values.

#### Implementation Notes
- Add tab navigation (Property / Type / Resource)
- **Type tab:**
  - Autocomplete for class selection
  - Resource URI input (existing or new)
  - Generates `@typeof` attribute
- **Resource tab:**
  - Create new resource block with `@about`
  - Set multiple properties on resource
- **Content override field** (all tabs):
  - Optional `@content` attribute
  - For machine-readable values differing from display text
- Tab state management
- Validation per tab

#### Rationale
Complete annotation capabilities. Type and Resource declarations are essential for semantic documents. Tabs organize complex form.

---

### 10. Advanced HTML Editing (Tables, Figures, Definition Lists)

**Hours:** 58
**Cost:** €4,350
**Complexity:** 7/10

#### Description
Insert and edit complex HTML structures. Tables with add/remove rows/columns only (defer merge/split). Figures and definition lists with proper nesting.

#### Implementation Notes

**Tables (38 hours):**
- Insert table dialog (rows × columns): 5h
- Table structure: `contenteditable="false"`
- Only cell contents (`<td>`, `<th>`): `contenteditable="true"`
- Click table → show overlay toolbar: 8h
- Operations:
  - Add row above/below: 6h
  - Remove row: 4h
  - Add column left/right: 8h
  - Remove column: 6h
  - Convert cell to/from header (`<th>`): 3h
- Handle RDFa on table/tr/td elements: 4h
- Basic copy/paste (plain structure): 4h

**Figures (10 hours):**
- Insert figure with image
- Add/edit figcaption
- Nested contenteditable handling

**Definition Lists (10 hours):**
- Insert dl with dt/dd pairs
- Add/remove terms
- Proper nesting enforcement

#### What's Included

✓ Insert table with N rows × M columns
✓ Add/remove rows
✓ Add/remove columns
✓ Convert cells to/from headers (`<th>`)
✓ RDFa attributes on table elements
✓ Basic copy/paste

#### Deferred to Phase 3

✗ Merge cells (colspan/rowspan)
✗ Split merged cells
✗ Advanced copy/paste with formatting
✗ Table resize handles
✗ Cell background colors

#### Rationale

Add/remove operations cover 80% of table editing needs. Merge/split is complex (12h saved) and less frequently needed. Focus on getting tables working well for data/content, defer formatting.

---

### 11. Block Drag-and-Drop

**Hours:** 80
**Cost:** €6,000
**Complexity:** 8/10

#### Description
Drag resource blocks (elements with `@typeof`) to new positions at any nesting level. Show visual drop zone indicators. Preserve or explicitly set `@about` and prefix scope to maintain RDFa context after move.

#### Implementation Notes
- Identify draggable blocks (elements with `@typeof`)
- IXSL dragstart/dragover/drop handlers
- Visual drop zones:
  - Before element
  - After element
  - As child (first/last)
  - Indentation level indicators
- Highlight valid drop targets during drag
- **RDFa context preservation:**
  - Check if moved element has explicit `@about`
  - If inheriting from parent context, auto-add `@about` on move
  - Preserve prefix declarations (copy parent `@prefix` if needed)
  - Warn if move would break references
- DOM tree manipulation
- Undo support (record move operation)

#### Rationale
Enables document reorganization. Complex due to RDFa context inheritance - moving a block can change its subject. Must preserve semantics.

---

### Testing & Debugging (Phase 2)

**Hours:** 60
**Cost:** €4,500

#### Activities
- Integration testing of drag-and-drop with RDFa context
- Table editing edge cases (merge/split, copy/paste)
- Advanced annotation scenarios (type hierarchies, multiple properties)
- RDF extraction validation with complex structures
- Browser compatibility for drag events
- Performance testing with large documents
- Bug fixes

---

### Documentation & Polish

**Hours:** 10
**Cost:** €750

#### Activities
- Basic usage documentation
- Vocabulary setup instructions
- Example annotations
- Keyboard shortcuts reference
- Known limitations
- Code comments for future maintenance

---

### Contingency/Buffer

**Hours:** 59
**Cost:** €4,425

13% contingency buffer for:
- Unexpected edge cases in RDFa extraction
- Browser compatibility issues
- Integration challenges between components
- Performance optimization needs
- Scope clarifications during implementation

This healthy buffer makes the plan realistic given the technical complexity.

---

## Deferred Features (Phase 3 - Future)

The following features are not included in the €39,000 budget but could be implemented in a follow-up phase.

### Advanced RDFa 1.1 Features
- **Hours:** 40
- **Cost:** €3,000
- `@vocab` default vocabulary, `@rel`/`@rev` chaining, safe CURIEs, XML Literals, W3C test suite compliance

### Table Merge/Split
- **Hours:** 20
- **Cost:** €1,500
- Merge cells (colspan/rowspan), split merged cells, advanced copy/paste

### Undo/Redo System
- **Hours:** 140
- **Cost:** €10,500
- Track all DOM mutations, atomic operations, multi-step undo/redo

### RDFa Diff View
- **Hours:** 60
- **Cost:** €4,500
- Visual diff showing DOM and triple changes between versions

### Hover Previews
- **Hours:** 25
- **Cost:** €1,875
- Tooltips on annotated spans showing triples and CURIE previews

### Document Outline Navigator
- **Hours:** 16
- **Cost:** €1,200
- Tree view of all typed resources, click to navigate

### Selection Inspector Panel
- **Hours:** 16
- **Cost:** €1,200
- Sidebar showing properties for selected element

### Floating Selection Toolbar
- **Hours:** 16
- **Cost:** €1,200
- Toolbar near text selection for quick actions

### Template System
- **Hours:** 16
- **Cost:** €1,200
- Insert pre-defined HTML+RDFa snippets

**Total Phase 3:** ~349 hours = €26,175

---

## Deliverables

### After Phase 1 (€18,600 - 2 months)
- ✓ Pragmatic RDFa extraction (XSLT 3.0, 80% common cases)
- ✓ Handles Schema.org, basic FOAF, simple Dublin Core
- ✓ Create HTML content (paragraphs, headings, lists, links, images)
- ✓ Select text and annotate with RDFa properties
- ✓ Autocomplete from loaded vocabulary
- ✓ Visual highlighting of annotated content
- ✓ Export RDF in multiple formats
- ✓ Working editor suitable for most documents

### After Phase 2 (€34,575 - 4 months)
- ✓ All Phase 1 features
- ✓ Tables (add/remove rows/columns, convert headers)
- ✓ Figures and definition lists
- ✓ Drag-and-drop block reorganization with RDFa context preservation
- ✓ Full annotation capabilities (types, resources, content override)
- ✓ Production-ready MVP for semantic document authoring

### With Contingency Buffer (€39,000 total)
- Includes 59 hours (13%) buffer for unexpected issues
- Realistic budget for actual implementation

---

## Technical Stack

- **XSLT 3.0** via SaxonJS 2
- **IXSL** (Saxon Interactive XSLT) for browser event handling
- **rdflib.js** for vocabulary loading and RDF serialization
- **Native browser APIs:**
  - contenteditable
  - Selection/Range API
  - Drag and Drop API
  - DOMParser/XMLSerializer

---

## Risk Factors

1. **XSLT/IXSL expertise** - Rare skillset, may require learning curve
2. **RDFa extraction complexity** - Even 80% scope has subtle edge cases
3. **contenteditable quirks** - Browser inconsistencies, especially with tables
4. **RDFa context inheritance** - Parent-child subject relationships can be tricky
5. **Debugging tooling** - XSLT debugging less mature than JavaScript

## Risk Mitigation

- **Pragmatic RDFa scope**: 65 hours for 80% common cases instead of 105h for full spec - more achievable
- **13% contingency buffer**: 59 hours for unexpected issues and edge cases
- **Early validation**: Phase 1 delivers working RDF extraction before investing in advanced UI features
- **Test-driven approach**: Build test suite with real-world examples (Schema.org patterns)
- **Incremental scope**: Can add advanced RDFa features in Phase 3 if needed

---

## Success Criteria

- ✓ Handles common RDFa patterns (Schema.org, basic FOAF, simple Dublin Core)
- ✓ Can create and edit semantic HTML documents with RDFa annotations
- ✓ Extracted RDF validates against test vocabularies
- ✓ Works in Firefox and Chrome (latest versions)
- ✓ Users can annotate without manual HTML/RDFa knowledge
- ✓ Document structure preserved during editing operations
- ✓ RDF semantics maintained during drag-and-drop reorganization
- ✓ Performance: <100ms RDF extraction for typical documents
- ✓ Tables support add/remove rows/columns (core 80% use case)
- ✓ Realistic budget with 13% contingency buffer
