# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

RDFa-Editor is a prototype demonstrating declarative RDFa annotation on XHTML using client-side XSLT transformations. The application allows users to double-click text, enter metadata, and generate RDFa attributes (`about`, `content`, `property`) directly in the DOM. Currently works in Firefox.

## Architecture

### XSLT-Based Client-Side Processing

The application uses **SaxonJS 2** (formerly Saxon-CE 1.1) as an XSLT 2.0 processor in the browser. This is the core architectural pattern:

1. **index.html** - Entry point that loads SaxonJS and triggers the initial transformation
2. **index.xsl** - Main XSLT stylesheet with interactive event handlers using Saxon's `ixsl:` namespace
3. **RDFa2RDFXML.xsl** - XSLT transformation for converting RDFa annotations to RDF/XML format
4. **SaxonJS2.js** - The Saxon XSLT processor library

### XSLT Compilation Pipeline

XSLT stylesheets must be compiled to SEF (Stylesheet Export Format) JSON files before use:

- **Entity Expansion**: XML entities in XSLT files are expanded using `xmlstarlet c14n`, creating `.c14n` canonicalized versions (gitignored)
- **SEF Compilation**: The canonicalized XSLT is compiled to `index.xsl.sef.json` using SaxonJS's `xslt3` command

### Interactive Event Model

The application uses Saxon's interactive XSLT extensions (`xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"`):

- **Right-click handler** (`mode="ixsl:oncontextmenu"`) on editable paragraphs to show annotation overlay
- **Click handler** (`mode="ixsl:onclick"`) on form buttons to apply RDFa attributes to selected text
- **DOM manipulation** via `ixsl:set-attribute`, `ixsl:set-property`, `ixsl:set-style`
- **Window/Selection API access** via `ixsl:window()`, `ixsl:page()`, `ixsl:call()`

### RDFa Annotation Workflow

1. User right-clicks on editable text in a `<p contenteditable="true">` element
2. Browser selection is captured via `window.getSelection()` and stored in `window.range`
3. Overlay form displays with fields for Subject, Property (from FOAF vocab), and Object
4. On form submission, a `<span>` element wraps the selected range
5. RDFa attributes (`about`, `property`, `resource`) are set on the span element

### Vocabulary Integration

The system loads RDF vocabularies (currently FOAF in `vocabs/foaf.rdf`) and parses them with XSLT's `document()` function to populate dropdown menus with available properties.

## Common Commands

### Build SEF Files

Run this after modifying any XSLT files:

```bash
bash generate-sef.sh
```

This command:
1. Canonicalizes all `.xsl` files to `.c14n` versions using xmlstarlet
2. Compiles `index.xsl.c14n` to `index.xsl.sef.json` using npx xslt3

### Development Server

Since this uses client-side XSLT with file loading (`document()` function), you'll need a local web server. Any HTTP server will work:

```bash
# Python 3
python -m http.server 8000

# Node.js (if you have http-server installed)
npx http-server
```

Then open `http://localhost:8000/index.html` in Firefox.

## Key Technical Constraints

- **Browser compatibility**: Only tested in Firefox due to XSLT 2.0 requirements
- **XSLT namespace handling**: The main stylesheet uses `xpath-default-namespace="http://www.w3.org/1999/xhtml"` so XPath expressions match HTML elements without prefixes
- **Mode attribute**: All template matches use `mode="rdf2rdfxml"` to isolate RDFa processing templates
- **Entity declarations**: XSLT files use DOCTYPE entity declarations for common RDF namespaces, which must be expanded via c14n before compilation
- **File references**: The RDFa2RDFXML transformation is included via `xsl:include href="RDFa2RDFXML.xsl.c14n"` (note the .c14n extension)
