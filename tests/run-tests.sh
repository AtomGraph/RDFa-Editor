#!/usr/bin/env bash
# Headless test suite for the RDFa extractor. For each fixture: extract RDF/XML,
# canonicalize actual and expected output into sorted triple lists (normalize.xsl),
# and compare with diff. Exit code is non-zero if any fixture fails.
set -u
cd "$(dirname "$0")/.."

BASE=http://example.org/dir/doc
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

for fixture in tests/fixtures/*.xhtml; do
    name=$(basename "$fixture" .xhtml)
    if ! npx xslt3-he -xsl:src/RDFa2RDFXML-v3.xsl -s:"$fixture" -it:"Q{https://w3id.org/atomgraph/rdfa-editor/rdfa#}extract-rdfa" -o:"$tmp/$name.rdf" base-uri="$BASE" 2>"$tmp/$name.err"; then
        echo "FAIL $name (extraction error)"
        cat "$tmp/$name.err"
        fail=1
        continue
    fi
    npx xslt3-he -xsl:tests/normalize.xsl -s:"$tmp/$name.rdf" -o:"$tmp/$name.actual"
    npx xslt3-he -xsl:tests/normalize.xsl -s:"tests/expected/$name.rdf" -o:"$tmp/$name.expected"
    if diff -u "$tmp/$name.expected" "$tmp/$name.actual" >"$tmp/$name.diff"; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        cat "$tmp/$name.diff"
        fail=1
    fi
done

for fixture in tests/fixtures/lint/*.xhtml; do
    name=$(basename "$fixture" .xhtml)
    if ! npx xslt3-he -xsl:tests/lint-driver.xsl -s:"$fixture" -it:lint-report -o:"$tmp/l-$name.actual" 2>"$tmp/l-$name.err"; then
        echo "FAIL lint/$name (lint error)"
        cat "$tmp/l-$name.err"
        fail=1
        continue
    fi
    if diff -u "tests/expected/lint/$name.txt" "$tmp/l-$name.actual" >"$tmp/l-$name.diff"; then
        echo "PASS lint/$name"
    else
        echo "FAIL lint/$name"
        cat "$tmp/l-$name.diff"
        fail=1
    fi
done

for fixture in tests/fixtures/canonical/*.xhtml; do
    name=$(basename "$fixture" .xhtml)
    if ! npx xslt3-he -xsl:tests/canonical-driver.xsl -s:"$fixture" -it:"Q{https://w3id.org/atomgraph/rdfa-editor/content-model#}canonical-xhtml" -o:"$tmp/c-$name.xhtml" 2>"$tmp/c-$name.err"; then
        echo "FAIL canonical/$name (transform error)"
        cat "$tmp/c-$name.err"
        fail=1
        continue
    fi
    npx xslt3-he -xsl:tests/normalize-xhtml.xsl -s:"$tmp/c-$name.xhtml" -o:"$tmp/c-$name.actual"
    npx xslt3-he -xsl:tests/normalize-xhtml.xsl -s:"tests/expected/canonical/$name.xhtml" -o:"$tmp/c-$name.expected"
    if diff -u "$tmp/c-$name.expected" "$tmp/c-$name.actual" >"$tmp/c-$name.diff"; then
        echo "PASS canonical/$name"
    else
        echo "FAIL canonical/$name"
        cat "$tmp/c-$name.diff"
        fail=1
    fi
done

exit $fail
