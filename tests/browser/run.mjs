// Serves the repo root and runs the browser suites sequentially.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.json': 'application/json', '.css': 'text/css', '.rdf': 'application/rdf+xml',
    '.xsl': 'application/xslt+xml', '.png': 'image/png' };

const server = createServer(async (req, res) => {
    try {
        const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^([/\\])+/, '');
        const body = await readFile(join(root, path === '' ? 'index.html' : path));
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
for (const suite of ['editor', 'features', 'fixes', 'hardening', 'multiinstance', 'tables', 'datatype', 'inspector', 'nesting', 'authoring', 'invariants']) {
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
