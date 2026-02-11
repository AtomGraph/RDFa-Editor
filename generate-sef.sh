# expand entities in XSLT stylesheets. Same logic as in pom.xml using net.sf.saxon.Query.

mkdir -p build
find src -maxdepth 1 -type f -name "*.xsl" -exec sh -c 'xmlstarlet c14n "$1" > "build/$(basename "$1")"' x {} \;

# compile client.xsl to SEF. The output path is mounted in docker-compose.override.yml

echo "Generating SEF file from src/graph-client.xsl..."

mkdir -p dist
npx xslt3-he -t -xsl:./build/index.xsl -export:./dist/index.xsl.sef.json -nogo -ns:##html5 -relocate:on

if [ $? -eq 0 ]; then
    echo "✓ SEF file generated successfully: dist/index.xsl.sef.json"
else
    echo "✗ Error generating SEF file"
    exit 1
fi
