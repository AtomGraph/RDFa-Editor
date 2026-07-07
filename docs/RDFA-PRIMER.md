# RDFa 1.1 Primer - Third Edition

**Rich Structured Data Markup for Web Documents**

W3C Working Group Note 17 March 2015

## Document Information

- **This version:** http://www.w3.org/TR/2015/NOTE-rdfa-primer-20150317/
- **Latest published version:** http://www.w3.org/TR/rdfa-primer/
- **Latest editor's draft:** http://www.w3.org/2010/02/rdfa/sources/rdfa-primer/Overview-src.html
- **Previous version:** http://www.w3.org/TR/2013/NOTE-rdfa-primer-20130822/

### Editors

- Ivan Herman, W3C (ivan@w3.org)
- Ben Adida, Creative Commons (ben@adida.net)
- Manu Sporny, Digital Bazaar (msporny@digitalbazaar.com)
- Mark Birbeck, webBackPlane.com (mark.birbeck@webBackplane.com)

---

## Abstract

Web content consumption has evolved from predominantly human-focused to increasingly machine-readable. "Sites now identify page titles, content types, and preview images for social media integration. Search engines extract structured details to provide richer results. Publishers produce structured data to improve search rankings."

RDFa (Resource Description Framework in Attributes) enables adding structured data directly to HTML pages through markup attributes. This Primer demonstrates expressing machine-readable data within human-readable web content.

**Note:** This is a Primer only. Complete specifications exist in RDFa 1.1 Core, RDFa Lite, XHTML+RDFa 1.1, and HTML5+RDFa 1.1 documents.

---

## 1. Introduction

### 1.1 Overview

The web bridges human consumption and machine interpretation. HTML elements carry presentation instructions browsers follow faithfully, yet "only humans understand that a headline expresses a blog post title, that italicized text indicates publication date, or that single-word links represent subject categories."

RDFa allows augmenting visual web content with machine-readable hints, enabling:

- Calendar applications to extract dinner party announcements
- Address books to capture author contact information
- Search engines to provide richer results
- Social networks to share thumbnails and attribution

### 1.2 HTML vs. XHTML

RDFa 1.0 was specified exclusively for XHTML. RDFa 1.1 supports both XHTML and HTML5, as well as XML-based languages like SVG. This document uses HTML throughout for simplicity.

### 1.3 Validation

RDFa relies on attributes—some reuse existing HTML attributes (e.g., `href`, `src`), while others are new. HTML validators may not recognize new RDFa attributes until updated. "Browsers simply ignore attributes they do not recognize. None of the RDFa-specific attributes affect visual display."

---

## 2. Using RDFa

### 2.1 The Basics: RDFa Lite

RDFa Lite 1.1 represents a minimal subset designed for simple to moderate structured data tasks without burdening authors with unnecessary complexity.

#### 2.1.1 Adding Machine-Readable Hints to Web Pages

##### 2.1.1.1 Social Networking Sites

Alice publishes a blog and wants to provide structural information using Dublin Core vocabulary terms. Her blog contains publication dates and titles:

**Before RDFa:**

```html
<html>
<head>
  ...
</head>
<body>
  ...
  <h2>The Trouble with Bob</h2>
  <p>Date: 2011-09-10</p>
  ...
</body>
```

**With RDFa:**

```html
<html>
<head>
  ...
</head>
<body>
  ...
  <h2 property="http://purl.org/dc/terms/title">The Trouble with Bob</h2>
  <p>Date: <span property="http://purl.org/dc/terms/created">2011-09-10</span></p>
  ...
</body>
```

RDFa uses URLs to identify everything. "Using URLs removes the possibility for ambiguities in terminology. The term 'title' might mean 'the title of a work', 'a job title', or 'the deed for real-estate property'. When each vocabulary term is a URL, detailed explanation is one click away."

##### 2.1.1.2 Links with Flavor

RDFa allows adding "flavor" (semantic meaning) to existing clickable links. Alice declares her content as freely reusable under Creative Commons licensing:

**Before RDFa:**

```html
<p>All content on this site is licensed under
   <a href="http://creativecommons.org/licenses/by/3.0/">
     a Creative Commons License</a>. ©2011 Alice Birpemswick.</p>
```

**With RDFa:**

```html
<p>All content on this site is licensed under
   <a property="http://creativecommons.org/ns#license"
      href="http://creativecommons.org/licenses/by/3.0/">
     a Creative Commons License</a>. ©2011 Alice Birpemswick.</p>
```

When `property` appears on elements with `href` or `src`, the attribute value becomes the property target rather than textual content.

##### 2.1.1.3 Setting a Default Vocabulary

For simple use cases involving predominantly single vocabularies, the `vocab` attribute reduces repetition:

**Original approach:**

```html
<html>
<head>
  ...
</head>
<body>
  ...
  <h2 property="http://purl.org/dc/terms/title">The Trouble with Bob</h2>
  <p>Date: <span property="http://purl.org/dc/terms/created">2011-09-10</span></p>
  ...
</body>
```

**With vocab attribute:**

```html
<html>
<head>
  ...
</head>
<body vocab="http://purl.org/dc/terms/">
  ...
  <h2 property="title">The Trouble with Bob</h2>
  <p>Date: <span property="created">2011-09-10</span></p>
  ...
</body>
```

Property values are single terms concatenated with the `vocab` URL. The attribute applies to all elements below its declaration point and can appear on any HTML element.

**Mixing approaches:**

```html
<html>
<head>
  ...
</head>
<body vocab="http://purl.org/dc/terms/">
  ...
  <h2 property="title">The Trouble with Bob</h2>
  <p>Date: <span property="created">2011-09-10</span></p>
  ...
  <p>All content on this site is licensed under
   <a property="http://creativecommons.org/ns#license"
      href="http://creativecommons.org/licenses/by/3.0/">
     a Creative Commons License</a>. ©2011 Alice Birpemswick.</p>
</body>
</html>
```

**Alternative using nested vocab:**

```html
<html>
<head>
  ...
</head>
<body vocab="http://purl.org/dc/terms/">
  ...
  <h2 property="title">The Trouble with Bob</h2>
  <p>Date: <span property="created">2011-09-10</span></p>
  ...
  <p vocab="http://creativecommons.org/ns#">All content on this site is licensed under
    <a property="license" href="http://creativecommons.org/licenses/by/3.0/">
      a Creative Commons License</a>. ©2011 Alice Birpemswick.</p>
</body>
</html>
```

Nested `vocab` attributes override inherited definitions from parent elements.

##### 2.1.1.4 Multiple Items per Page

Blog homepages typically list multiple entries, each with independent titles, authors, and dates. The `resource` attribute specifies the "context"—the exact URL to which contained RDFa markup applies:

```html
<body vocab="http://purl.org/dc/terms/">
   ...
   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      <p>Date: <span property="created">2011-09-10</span></p>
      <h3 property="creator">Alice</h3>
      ...
   </div>
   ...
   <div resource="/alice/posts/jos_barbecue">
      <h2 property="title">Jo's Barbecue</h2>
      <p>Date: <span property="created">2011-09-14</span></p>
      <h3 property="creator">Eve</h3>
      ...
   </div>
   ...
</body>
```

Relative URLs work alongside absolute URLs. Innermost `resource` values override outer values for contained markup:

```html
<div resource="/alice/posts/trouble_with_bob">
    <h2 property="title">The trouble with Bob</h2>
    ...
    The trouble with Bob is that he takes much better photos than I do:
    ...
    <div resource="http://example.com/bob/photos/sunset.jpg">
      <img src="http://example.com/bob/photos/sunset.jpg" />
      <span property="title">Beautiful Sunset</span>
      by <span property="creator">Bob</span>.
    </div>
 </div>
```

#### 2.1.2 Exploring Further: Social Networks

##### 2.1.2.1 Contact Information

Alice wants to share contact information using the Friend-of-a-Friend (FOAF) vocabulary. She declares a new FOAF "Person" using `typeof`:

**Initial contact markup:**

```html
<div>
  <p>
     Alice Birpemswick,
     Email: <a href="mailto:alice@example.com">alice@example.com</a>,
     Phone: <a href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
</div>
```

**With RDFa and typeof:**

```html
<div typeof="http://xmlns.com/foaf/0.1/Person">
  ...
```

**Simplified with vocab:**

```html
<div vocab="http://xmlns.com/foaf/0.1/" typeof="Person">
  ...
```

**Complete contact information:**

```html
<div vocab="http://xmlns.com/foaf/0.1/" typeof="Person">
  <p>
    <span property="name">Alice Birpemswick</span>,
    Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
    Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
</div>
```

Without specifying `resource`, the `typeof` attribute on the enclosing `div` implicitly sets the property subject. This creates a "blank node"—a node without a URL identifier.

##### 2.1.2.2 Describing Social Networks

Alice lists her friends with RDFa:

**Initial HTML:**

```html
<div>
   <ul>
      <li>
        <a href="http://example.com/bob/">Bob</a>
      </li>
      <li>
        <a href="http://example.com/eve/">Eve</a>
      </li>
      <li>
        <a href="http://example.com/manu/">Manu</a>
      </li>
   </ul>
</div>
```

**Adding Person types:**

```html
<div vocab="http://xmlns.com/foaf/0.1/">
   <ul>
      <li typeof="Person">
        <a href="http://example.com/bob/">Bob</a>
      </li>
      <li typeof="Person">
        <a href="http://example.com/eve/">Eve</a>
      </li>
      <li typeof="Person">
        <a href="http://example.com/manu/">Manu</a>
      </li>
   </ul>
</div>
```

Each `typeof` creates a new blank node with distinct properties.

**Adding homepages:**

```html
<div vocab="http://xmlns.com/foaf/0.1/">
   <ul>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/bob/">Bob</a>
      </li>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/eve/">Eve</a>
      </li>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/manu/">Manu</a>
      </li>
   </ul>
</div>
```

**Adding names with separate spans:**

```html
<div vocab="http://xmlns.com/foaf/0.1/">
  <ul>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/bob/">
          <span property="name">Bob</span>
        </a>
      </li>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/eve/">
          <span property="name">Eve</span>
        </a>
      </li>
      <li typeof="Person">
        <a property="homepage" href="http://example.com/manu/">
          <span property="name">Manu</span>
        </a>
      </li>
   </ul>
</div>
```

**Expressing relationships using foaf:knows:**

```html
<div vocab="http://xmlns.com/foaf/0.1/" typeof="Person">
   <p>
    <span property="name">Alice Birpemswick</span>,
    Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
    Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
   <ul>
      <li property="knows" typeof="Person">
        <a property="homepage" href="http://example.com/bob/">
          <span property="name">Bob</span>
        </a>
      </li>
      <li property="knows" typeof="Person">
        <a property="homepage" href="http://example.com/eve/">
          <span property="name">Eve</span>
        </a>
      </li>
      <li property="knows" typeof="Person">
        <a property="homepage" href="http://example.com/manu/">
          <span property="name">Manu</span>
        </a>
      </li>
   </ul>
</div>
```

#### 2.1.3 Repeated Patterns

When Alice marks up multiple blog items with the same licensing statements, repetition becomes tedious and error-prone. HTML+RDFa introduces "Property copying" using `rdfa:copy` and `rdfa:Pattern`:

**Repetitive approach:**

```html
<body vocab="http://purl.org/dc/terms/">
   ...
   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      <p>Date: <span property="created">2011-09-10</span></p>
      <h3 property="creator">Alice</h3>
      ...
      <p vocab="http://creativecommons.org/ns#">All content on this blog item is licensed under
        <a property="license" href="http://creativecommons.org/licenses/by/3.0/">
          a Creative Commons License</a>. <span property="attributionName">©2011 Alice Birpemswick</span>.</p>
   </div>
   ...
   <div resource="/alice/posts/jims_concert">
      <h2 property="title">I was at Jim's concert the other day</h2>
      <p>Date: <span property="created">2011-10-22</span></p>
      <h3 property="creator">Alice</h3>
      ...
      <p vocab="http://creativecommons.org/ns#">All content on this blog item is licensed under
        <a property="license" href="http://creativecommons.org/licenses/by/3.0/">
          a Creative Commons License</a>. <span property="attributionName">©2011 Alice Birpemswick</span>.</p>
   </div>
   ...
</body>
```

**Using Property copying:**

```html
<body vocab="http://purl.org/dc/terms/">
   ...
   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      <p>Date: <span property="created">2011-09-10</span></p>
      <h3 property="creator">Alice</h3>
      ...
      <link property="rdfa:copy" href="#ccpattern"/>
    </div>
   ...
   <div resource="/alice/posts/jims_concert">
      <h2 property="title">I was at Jim's concert the other day</h2>
      <p>Date: <span property="created">2011-10-22</span></p>
      <h3 property="creator">Alice</h3>
      ...
      <link property="rdfa:copy" href="#ccpattern"/>
   </div>
   ...

   <div resource="#ccpattern" typeof="rdfa:Pattern">
      <p vocab="http://creativecommons.org/ns#">All content on this blog item is licensed under
        <a property="license" href="http://creativecommons.org/licenses/by/3.0/">
          a Creative Commons License</a>. <span property="attributionName">©2011 Alice Birpemswick</span>.</p>
   </div>

</body>
```

The `link` element is conceptually replaced with the pattern's RDFa statements. CSS can hide pattern visibility if desired.

#### 2.1.4 Internal References

Alice wants to combine FOAF data with blog items. Initially, this requires embedding FOAF data within blog posts and using full URIs to avoid vocabulary conflicts:

**Embedded approach:**

```html
<div vocab="http://purl.org/dc/terms/">

   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      ...
      <h3 vocab="http://xmlns.com/foaf/0.1/"
          property="http://purl.org/dc/terms/creator" typeof="Person">
        <span property="name">Alice Birpemswick</span>,
        Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
        Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
      </h3>
      ...
   </div>
   ...
</div>
```

For better page layout, Alice assigns the FOAF data a separate URI:

**Improved approach with separate URI:**

```html
<div vocab="http://xmlns.com/foaf/0.1/" resource="#me" typeof="Person">
  <p>
   <span property="name">Alice Birpemswick</span>,
     Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
     Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
  ...
</div>
```

**Linking blog items to FOAF data:**

```html
<div vocab="http://purl.org/dc/terms/">
   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      <h3 property="creator" resource="#me">Alice</h3>
      ...
   </div>
</div>
   ...
<div class="sidebar" vocab="http://xmlns.com/foaf/0.1/" resource="#me" typeof="Person">
  <p>
   <span property="name">Alice Birpemswick</span>,
     Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
     Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
  ...
</div>
```

The `resource` attribute with `property` indicates the relation's "target." This allows distributing structured data across the page while using an explicit URI instead of blank nodes.

**Multiple references to same data:**

```html
<div vocab="http://purl.org/dc/terms/">
   <div resource="/alice/posts/trouble_with_bob">
      <h2 property="title">The trouble with Bob</h2>
      <h3 property="creator" resource="#me">Alice</h3>
      ...
   </div>
</div>
   ...
<div vocab="http://purl.org/dc/terms/">
   <div resource="/alice/posts/my_photos">
      <h2 property="title">I will post my photos nevertheless…</h2>
      <h3 property="creator" resource="#me">Alice</h3>
      ...
   </div>
</div>
   ...
<div class="sidebar" vocab="http://xmlns.com/foaf/0.1/" resource="#me" typeof="Person">
  <p>
   <span property="name">Alice Birpemswick</span>,
     Email: <a property="mbox" href="mailto:alice@example.com">alice@example.com</a>,
     Phone: <a property="phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
  ...
</div>
```

#### 2.1.5 Using Multiple Vocabularies

Complex structured data often requires multiple vocabularies. Alice uses Dublin Core, FOAF, Creative Commons, and schema.org vocabularies:

**Full URLs approach:**

```html
<html>
 <head>
    ...
 </head>
 <body vocab="http://schema.org/">
   <div resource="/alice/posts/trouble_with_bob" typeof="BlogPosting">
      <h2 property="http://purl.org/dc/terms/title">The trouble with Bob</h2>
      ...
      <h3 property="http://purl.org/dc/terms/creator" resource="#me">Alice</h3>
      <div property="articleBody">
        <p>The trouble with Bob is that he takes much better photos than I do:</p>
      </div>
      ...
   </div>
   ...
  </body>
 </html>
```

##### 2.1.5.1 Using Prefixes

When vocabularies intertwine, RDFa's `prefix` attribute efficiently manages multiple vocabulary URLs. Prefixes use `prefix:reference` syntax, where the prefix URL concatenates with the reference:

**With prefixes:**

```html
<html>
 <head>
   ...
 </head>
 <body prefix="dc: http://purl.org/dc/terms/ schema: http://schema.org/">
   <div resource="/alice/posts/trouble_with_bob" typeof="schema:BlogPosting">
      <h2 property="dc:title">The trouble with Bob</h2>
      ...
      <h3 property="dc:creator" resource="#me">Alice</h3>
      <div property="schema:articleBody">
        <p>The trouble with Bob is that he takes much better photos than I do:</p>
      </div>
     ...
   </div>
 </body>
</html>
```

**Combining vocab and prefix:**

```html
<html>
 <head>
   ...
 </head>
 <body vocab="http://purl.org/dc/terms/" prefix="schema: http://schema.org/">
   <div resource="/alice/posts/trouble_with_bob" typeof="schema:BlogPosting">
      <h2 property="title">The trouble with Bob</h2>
      ...
      <h3 property="creator" resource="#me">Alice</h3>
      <div property="schema:articleBody">
        <p>The trouble with Bob is that he takes much better photos than I do:</p>
      </div>
      ...
   </div>
 </body>
</html>
```

Prefix and vocab attributes can appear anywhere, affecting elements below. Concentrating vocabulary choices reduces errors.

##### 2.1.5.2 Repeating Properties

When using multiple vocabularies, both properties may apply to the same element. Alice can list multiple property values:

**Separate elements approach:**

```html
<html>
 <head>
   ...
 </head>
 <body prefix="dc: http://purl.org/dc/terms/ schema: http://schema.org/">
   <div resource="/alice/posts/trouble_with_bob" typeof="schema:BlogPosting">
      <h2 property="dc:title">The trouble with Bob</h2>
      ...
      <h3 property="dc:creator" resource="#me">
        <span property="schema:creator" resource="#me">Alice</span>
      </h3>
      <div property="schema:articleBody">
        <p>The trouble with Bob is that he takes much better photos than I do:</p>
      </div>
     ...
   </div>
 </body>
</html>
```

**Property list approach:**

```html
<html>
 <head>
   ...
 </head>
 <body prefix="dc: http://purl.org/dc/terms/ schema: http://schema.org/">
   <div resource="/alice/posts/trouble_with_bob" typeof="schema:BlogPosting">
      <h2 property="dc:title">The trouble with Bob</h2>
      ...
      <h3 property="dc:creator schema:creator" resource="#me">Alice</h3>
      <div property="schema:articleBody">
        <p>The trouble with Bob is that he takes much better photos than I do:</p>
      </div>
     ...
   </div>
 </body>
</html>
```

The `property` attribute accepts space-separated values. Similarly, `typeof` accepts multiple values:

```html
<div class="sidebar" prefix="foaf: http://xmlns.com/foaf/0.1/ schema: http://schema.org/"
     resource="#me" typeof="foaf:Person schema:Person">
  <p>
   <span property="foaf:name">Alice Birpemswick</span>,
     Email: <a property="foaf:mbox" href="mailto:alice@example.com">alice@example.com</a>,
     Phone: <a property="foaf:phone" href="tel:+1-617-555-7332">+1 617.555.7332</a>
  </p>
  ...
</div>
```

##### 2.1.5.3 Default Prefixes

RDFa defines an "initial context" with pre-defined prefixes for widely-used vocabularies. "These common vocabularies tend to be defined repeatedly, and authors sometimes forget declarations altogether."

RDFa processors recognize common prefixes like `dc:` even without explicit declaration:

```html
<html>
 <head>
   ...
 </head>
 <body>
   <div>
      <h2 property="dc:title">The trouble with Bob</h2>
      ...
      <h3 property="dc:creator" resource="#me">Alice</h3>
       ...
   </div>
 </body>
</html>
```

Processors expand `dc:title` and `dc:creator` to full URLs automatically. However, explicitly declaring prefixes is considered best practice for clarity and portability.

Default prefixes evolve over 5-10 years, but W3C policy guarantees no established prefix removal. Authors should explicitly declare prefixes for document intent clarity.

### 2.2 Going Deeper: RDFa Core

RDFa Lite covers most straightforward markup tasks. RDFa Core provides additional attributes for complex cases where Lite creates awkward or error-prone structures.

**Note:** "RDFa Lite does not define a separate class of RDFa processors. Conforming RDFa processors handle all RDFa features, including those beyond Lite."

#### 2.2.1 Using the `content` Attribute

Alice's date markup uses machine-readable format but lacks human readability:

```html
<html>
 <head>
   ...
 </head>
 <body>
   ...
   <h2 property="http://purl.org/dc/terms/title">The Trouble with Bob</h2>
   <p>Date: <span property="http://purl.org/dc/terms/created">2011-09-10</span></p>
   ...
 </body>
</html>
```

The `content` attribute provides machine-readable data while displaying human-friendly text:

```html
<html>
 <head>
   ...
 </head>
 <body>
   ...
   <h2 property="http://purl.org/dc/terms/title">The Trouble with Bob</h2>
   <p>Date: <span property="http://purl.org/dc/terms/created"
       content="2011-09-10">10th of September, 2011</span></p>
   ...
 </body>
</html>
```

The `content` attribute instructs processors to use its value instead of textual content. This maintains unambiguous machine interpretation while improving human readability.

The `content` attribute is essential for `meta` elements, which lack text content in conforming HTML. Facebook's Open Graph Protocol example:

```html
<html>
 <head prefix="og: http://ogp.me/ns#">
   ...
   <meta property="og:title" content="The Trouble with Bob" />
   <meta property="og:type"  content="text" />
   <meta property="og:image" content="http://example.com/alice/bob-ugly.jpg" />
   ...
 </head>
 <body>
  ...
 </body>
</html>
```

#### 2.2.2 Datatypes

Machine processors may need specific data type information to determine appropriate handling. Alice's copyright year example:

```html
<p>All content on this site is licensed under
   <a property="http://creativecommons.org/ns#license"
      href="http://creativecommons.org/licenses/by/3.0/">
     a Creative Commons License</a>. ©<span property="dc:date">2011</span> Alice Birpemswick.</p>
```

While processors recognizing `http://purl.org/dc/terms/date` infer date semantics, the string "2011" remains ambiguous. The `datatype` attribute clarifies:

```html
<p>All content on this site is licensed under
   <a property="http://creativecommons.org/ns#license"
      href="http://creativecommons.org/licenses/by/3.0/">
     a Creative Commons License</a>. ©<span property="dc:date" datatype="xsd:gYear">2011</span> Alice Birpemswick.</p>
```

The `xsd:gYear` prefix expands to `http://www.w3.org/2001/XMLSchema#gYear`, identifying the value as a year datatype from W3C's XML Schema standard. W3C defines standard datatypes including booleans, integers, dates, and doubles. The `xsd` prefix is included in default contexts.

#### 2.2.3 Alternative for Setting Context: `about`

The `resource` attribute sets "context"—the subject for subsequent statements. For simple markup, this can become verbose:

```html
<ul>
  <li resource="/alice/posts/trouble_with_bob">
    <span property="title">The trouble with Bob</span>
  </li>
  <li resource="/alice/posts/jos_barbecue">
    <span property="title">Jo's Barbecue</span>
  </li>
  ...
</ul>
```

The `about` attribute provides an alternative. Unlike `resource`, `about` _only_ sets context and never combines with `property` on the same element:

```html
<ul>
  <li about="/alice/posts/trouble_with_bob" property="title">The trouble with Bob</li>
  <li about="/alice/posts/jos_barbecue" property="title">Jo's Barbecue</li>
  ...
</ul>
```

In blog item markup, `about` and `resource` are interchangeable for context-setting:

```html
<div about="/alice/posts/trouble_with_bob">
   <h2 property="title">The trouble with Bob</h2>
   <h3 property="creator" resource="#me">Alice</h3>
   ...
</div>
```

#### 2.2.4 Alternative for Setting Property: `rel`

For repeated pattern markup, repeating `property` values is error-prone:

```html
<div vocab="http://xmlns.com/foaf/0.1/" resource="#me">
   <ul>
      <li property="knows" resource="http://example.com/bob/#me" typeof="Person">
        <a property="homepage" href="http://example.com/bob/">
          <span property="name">Bob</span>
        </a>
      </li>
      <li property="knows" resource="http://example.com/eve/#me" typeof="Person">
        <a property="homepage" href="http://example.com/eve/">
          <span property="name">Eve</span>
        </a>
      </li>
      <li property="knows" resource="http://example.com/manu/#me" typeof="Person">
        <a property="homepage" href="http://example.com/manu/">
          <span property="name">Manu</span>
        </a>
      </li>
   </ul>
</div>
```

The `rel` attribute eliminates repetition. Unlike `property`, `rel` never uses textual content. Instead, if no explicit target appears (via `resource`, `href`, etc.), the processor searches child elements for targets:

```html
<div vocab="http://xmlns.com/foaf/0.1/" resource="#me">
   <ul rel="knows">
      <li resource="http://example.com/bob/#me" typeof="Person">
        <a property="homepage" href="http://example.com/bob/">
          <span property="name">Bob</span>
        </a>
      </li>
      <li resource="http://example.com/eve/#me" typeof="Person">
        <a property="homepage" href="http://example.com/eve/">
          <span property="name">Eve</span>
        </a>
      </li>
      <li resource="http://example.com/manu/#me" typeof="Person">
        <a property="homepage" href="http://example.com/manu/">
          <span property="name">Manu</span>
        </a>
      </li>
   </ul>
</div>
```

**Note:** "In many situations, `property` and `rel` are interchangeable for link semantics. Subtle differences involving chaining exist requiring careful usage. The RDFa 1.1 specification addresses this in detail. Generally, using `property` when possible is advised."

---

## 3. You Said Something about RDF?

RDFa benefits from RDF (Resource Description Framework), W3C's standard for machine-readable data interoperability. Though RDF understanding is not required, understanding the relationship between RDFa and RDF provides useful context.

RDF represents data as subject-property-object triples forming "RDF graphs." Arrows in visualizations represent properties connecting nodes (subjects and objects). Triple Sets populate "Triple Stores" or "Graph Stores."

Example triple in Turtle syntax:

```turtle
<http://www.example.com/alice/posts/trouble_with_bob>
    <http://purl.org/dc/terms/title> "The Trouble with Bob" ;
    <http://purl.org/dc/terms/created> "2011-09-10" .
```

RDF's `rdf:type` property (drawn as **TYPE** arrows in diagrams) is another core RDF property located at `http://www.w3.org/1999/02/22-rdf-syntax-ns#`.

"RDF provides a universal language for expressing data and relationships. Any property can carry any number of URL-identified values. These URLs can be reused by any publisher, like linking to any web page. Using SPARQL, one can query across multiple RDF sources for complex patterns like 'friends of Alice who created items whose title contains Bob'."

RDF provides an abstract data model maximizing vocabulary reuse. RDFa is a technique for expressing RDF data within HTML, reusing existing human-readable content.

### 3.1 Custom Vocabularies

Alice may need vocabularies unavailable in existing standards. Creating custom vocabularies involves:

1. **Select vocabulary URL:** e.g., `http://example.com/photos/vocab#`
2. **Publish vocabulary document:** Define classes and properties (e.g., `Photo`, `Camera`, `takenWith`)
3. **Use in HTML:** Apply via `vocab` attribute or prefix declarations

Example:

```html
<div typeof="photo:Camera" prefix="photo: http://example.com/photos/vocab#">
  ...
</div>
```

"Anyone publishing web documents can create vocabulary documents with new terms. RDF and RDFa enable fully distributed vocabulary extensibility."

---

## 4. RDFa Tools

Numerous tools generate or process RDFa data:

- **W3C Semantic Web Wiki:** RDFa tools page (note: some tools relate to RDFa 1.0)
- **RDFa community site:** Implementation page constantly evolving
- **RDFa community site:** General information, examples, and involvement instructions
- **Real-time RDFa 1.1 editor:** Test RDFa fragments with visual structural representation

---

## 5. Acknowledgments

**RDF Web Application Working Group Members (publication time):**

- Stéphane Corlosquet, Massachusetts General Hospital
- Ivan Herman, W3C
- Gregg Kellogg (Invited Expert)
- Niklas Lindström (Invited Expert)
- Shane McCarron, Applied Testing and Technology, Inc. (Invited Expert)
- Steven Pemberton, Centre Mathematics and Computer Science
- Manu Sporny, Digital Bazaar (Chair, Invited Expert)
- Ted Thibodeau, OpenLink Software

**Additional thanks:** Grant Robertson and Guus Schreiber provided useful comments on earlier drafts.

---

## A. References

### A.1 Informative References

- **[cc-about]** Creative Commons: About Licenses. http://creativecommons.org/about/licenses/

- **[dc11]** Dublin Core metadata initiative. Dublin Core metadata element set, version 1.1. July 1999. http://dublincore.org/documents/dcmi-terms/

- **[foaf]** Dan Brickley; Libby Miller. FOAF Vocabulary Specification 0.99 (Paddington Edition). 14 January 2014. http://xmlns.com/foaf/spec

- **[html-rdfa]** Manu Sporny. HTML+RDFa 1.1 - Second Edition. 17 March 2015. W3C Recommendation. http://www.w3.org/TR/html-rdfa/

- **[ogp]** The Open Graph Protocol. December 2010. http://ogp.me

- **[rdf11-primer]** Guus Schreiber; Yves Raimond. RDF 1.1 Primer. 24 June 2014. W3C Note. http://www.w3.org/TR/rdf11-primer/

- **[rdfa-core]** Ben Adida; Mark Birbeck; Shane McCarron; Ivan Herman. RDFa Core 1.1 - Third Edition. 17 March 2015. W3C Recommendation. http://www.w3.org/TR/rdfa-core/

- **[rdfa-lite]** Manu Sporny. RDFa Lite 1.1 - Second Edition. 17 March 2015. W3C Recommendation. http://www.w3.org/TR/rdfa-lite/

- **[rdfa-syntax]** Ben Adida; Mark Birbeck; Shane McCarron; Steven Pemberton et al. RDFa in XHTML: Syntax and Processing. 14 October 2008. W3C Recommendation. http://www.w3.org/TR/rdfa-syntax

- **[schema]** Schemas—schema.org. http://schema.org

- **[sparql11-query]** Steven Harris; Andy Seaborne. SPARQL 1.1 Query Language. 21 March 2013. W3C Recommendation. http://www.w3.org/TR/sparql11-query/

- **[svg11]** Erik Dahlström; Patrick Dengler; Anthony Grasso; Chris Lilley; Cameron McCormack; Doug Schepers; Jonathan Watt; Jon Ferraiolo; Jun Fujisawa; Dean Jackson et al. Scalable Vector Graphics (SVG) 1.1 (Second Edition). 16 August 2011. W3C Recommendation. http://www.w3.org/TR/SVG11/

- **[turtle]** Eric Prud'hommeaux; Gavin Carothers. RDF 1.1 Turtle. 25 February 2014. W3C Recommendation. http://www.w3.org/TR/turtle/

- **[xhtml-rdfa]** Shane McCarron. XHTML+RDFa 1.1 - Third Edition. 17 March 2015. W3C Recommendation. http://www.w3.org/TR/xhtml-rdfa/

- **[xmlschema11-2]** David Peterson; Sandy Gao; Ashok Malhotra; Michael Sperberg-McQueen; Henry Thompson; Paul V. Biron et al. W3C XML Schema Definition Language (XSD) 1.1 Part 2: Datatypes. 5 April 2012. W3C Recommendation. http://www.w3.org/TR/xmlschema11-2/

---

**Document Copyright © 2010-2015 W3C® (MIT, ERCIM, Keio, Beihang)**

W3C liability, trademark, and document use rules apply.
