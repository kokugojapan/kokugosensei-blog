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

const articleDirs = fs
	.readdirSync(path.join(root, 'blog'), { withFileTypes: true })
	.filter((entry) => entry.isDirectory());
for (const { name } of articleDirs) {
	const html = fs.readFileSync(path.join(root, 'blog', name, 'index.html'), 'utf8');
	assert.equal((html.match(/data-ad-slot=/g) ?? []).length, 1, `${name}: article ad count`);
	assert.match(html, /data-ad-layout="in-article"/);
	assert.match(html, /data-ad-slot="8421877463"/);
	assert.match(html, />広告<\/span>/);
}

const home = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
assert.doesNotMatch(home, /data-ad-slot=/);
assert.match(home, /href="\/privacy\/"/);

const privacy = fs.readFileSync(path.join(root, 'privacy/index.html'), 'utf8');
assert.doesNotMatch(privacy, /pagead2\.googlesyndication\.com|google-adsense-account|data-ad-slot=/);
assert.match(privacy, /Google AdSense/);
assert.match(privacy, /第三者配信事業者/);
assert.match(privacy, /policies\.google\.com\/technologies\/partner-sites/);

const ads = fs.readFileSync(path.join(root, 'ads.txt'), 'utf8').trim();
assert.equal(ads, 'google.com, pub-8888044549970419, DIRECT, f08c47fec0942fa0');

console.log(
	`Site check passed: AIO, ${articleDirs.length} article ads, privacy disclosure, ads.txt`,
);
