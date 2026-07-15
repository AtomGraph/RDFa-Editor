// Static dev server with Linked Data content negotiation (LDH-style):
// a trailing-slash URL is a *document URI* whose representation is chosen by
// the Accept header — application/rdf+xml serves the directory's index.rdf,
// application/sparql-results+xml its results.xml, text/html its index.html.
// URLs never carry file extensions; the file layout stays server-private.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.argv[2] ?? process.env.PORT ?? 8000);

const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.json': 'application/json', '.css': 'text/css', '.rdf': 'application/rdf+xml',
    '.xml': 'application/xml', '.xsl': 'application/xslt+xml', '.png': 'image/png' };

// negotiable representations of a document URI, matched against Accept in order
const representations = [
    { type: 'application/rdf+xml', file: 'index.rdf' },
    { type: 'application/sparql-results+xml', file: 'results.xml' },
    { type: 'text/html; charset=utf-8', match: 'text/html', file: 'index.html' },
];

const server = createServer(async (req, res) => {
    try {
        const pathname = decodeURIComponent(new URL(req.url, 'http://x').pathname);
        const path = normalize(pathname).replace(/^([/\\])+/, '');
        if (pathname.endsWith('/')) {
            const accept = req.headers.accept ?? '';
            const candidates = representations.filter(rep => accept.includes(rep.match ?? rep.type));
            for (const rep of candidates.length ? candidates
                    : representations.filter(rep => rep.file === 'index.html')) {
                try {
                    const body = await readFile(join(root, path, rep.file));
                    res.writeHead(200, { 'Content-Type': rep.type });
                    res.end(body);
                    return;
                } catch { /* try the next representation */ }
            }
            res.writeHead(406);
            res.end();
            return;
        }
        const body = await readFile(join(root, path));
        res.writeHead(200, { 'Content-Type': mime[extname(path)] ?? 'application/octet-stream' });
        res.end(body);
    } catch {
        res.writeHead(404);
        res.end();
    }
});
server.listen(port, () => console.log(`Serving ${root} at http://localhost:${server.address().port}/ — Ctrl-C to stop`));
