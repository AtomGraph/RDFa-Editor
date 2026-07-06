# expand entities in XSLT stylesheets (xslt3 does not expand DTD entity references)

mkdir -p build
find src -maxdepth 1 -type f -name "*.xsl" -exec sh -c 'xmlstarlet c14n "$1" > "build/$(basename "$1")"' x {} \;

# compile the client stylesheet to SEF. -relocate:on means relative document() hrefs
# resolve against the SEF load location, i.e. dist/ — hence the vocabs/ copy below.

echo "Generating SEF file from src/index.xsl..."

mkdir -p dist
npx xslt3-he -t -xsl:./build/index.xsl -export:./dist/index.xsl.sef.json -nogo -ns:##html5 -relocate:on

if [ $? -eq 0 ]; then
    echo "✓ SEF file generated successfully: dist/index.xsl.sef.json"
else
    echo "✗ Error generating SEF file"
    exit 1
fi

mkdir -p dist/vocabs
cp vocabs/*.rdf dist/vocabs/
echo "✓ Vocabularies copied to dist/vocabs/"
