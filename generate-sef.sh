# expand entities in XSLT stylesheets. Same logic as in pom.xml using net.sf.saxon.Query.

find . -type f -name "*.xsl" -exec sh -c 'xmlstarlet c14n "$1" > "$1".c14n' x {} \;

# compile client.xsl to SEF. The output path is mounted in docker-compose.override.yml

npx xslt3 -t -xsl:index.xsl.c14n -export:index.xsl.sef.json -nogo -ns:##html5 -relocate:on