// Serves the repo root and runs the browser suites sequentially.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.json': 'application/json', '.css': 'text/css', '.rdf': 'application/rdf+xml',
    '.xml': 'application/xml', '.xsl': 'application/xslt+xml', '.png': 'image/png' };

// Linked Data conneg for document (trailing-slash) URIs — mirrors serve.mjs:
// object-block fixtures are fetched extension-free with an Accept header
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
            res.writeHead(406); res.end();
            return;
        }
        const body = await readFile(join(root, path));
        res.writeHead(200, { 'Content-Type': mime[extname(path)] ?? 'application/octet-stream' });
        res.end(body);
    } catch {
        res.writeHead(404); res.end();
    }
});
await new Promise(resolve => server.listen(0, resolve));
const base = `http://localhost:${server.address().port}`;
console.log(`serving ${root} at ${base}`);

let failed = 0;
for (const suite of ['editor', 'features', 'fixes', 'hardening', 'multiinstance', 'tables', 'datatype', 'inspector', 'nesting', 'authoring', 'invariants', 'select', 'notion', 'typeahead', 'blocks']) {
    console.log(`\n=== ${suite} ===`);
    const code = await new Promise(resolve => {
        const child = spawn(process.execPath, [fileURLToPath(new URL(`${suite}.mjs`, import.meta.url))],
            { stdio: 'inherit', env: { ...process.env, BASE_URL: base } });
        child.on('exit', resolve);
    });
    if (code !== 0) failed++;
}
server.close();
process.exit(failed ? 1 : 0);
