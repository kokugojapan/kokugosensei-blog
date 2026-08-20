import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const flagship = fs.readFileSync(
	path.join(root, 'blog/kokugo-jakuten-shindan/index.html'),
	'utf8',
);
const schemas = [...flagship.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/gs)].map(
	(match) => JSON.parse(match[1]),
);

assert.deepEqual(
	schemas.map((schema) => schema['@type']),
	['BlogPosting', 'BreadcrumbList'],
);
assert.equal(schemas[0].author.name, '水上先生');
assert.match(flagship, /2026年8月20日/);

const sitemap = fs.readFileSync(path.join(root, 'sitemap-0.xml'), 'utf8');
assert.match(sitemap, /https:\/\/blog\.kokugosensei\.com\/blog\/kokugo-jakuten-shindan\//);

const robots = fs.readFileSync(path.join(root, 'robots.txt'), 'utf8');
assert.match(robots, /Sitemap: https:\/\/blog\.kokugosensei\.com\/sitemap-index\.xml/);

console.log('AIO check passed: schema, author, Japanese date, sitemap, robots');
