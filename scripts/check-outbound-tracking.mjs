import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	BLOG_OUTBOUND_EVENT,
	buildOutboundEvent,
	classifyOutboundAction,
} from '../src/scripts/outboundTracking.js';

assert.equal(BLOG_OUTBOUND_EVENT, 'blog_outbound_click');
assert.equal(
	classifyOutboundAction('https://kokugosensei.com/course-diagnosis.html?answer=student#result'),
	'diagnosis',
);
assert.equal(classifyOutboundAction('https://kokugosensei.com/course-private.html'), 'private_lesson');
assert.equal(classifyOutboundAction('https://kokugosensei.com/contact.html'), 'contact');
assert.equal(classifyOutboundAction('https://lin.ee/6IRtEXI?campaign=blog'), 'line');
assert.equal(classifyOutboundAction('https://kokugosensei.com/?campaign=blog'), 'main_site');
assert.equal(classifyOutboundAction('https://example.com/contact.html'), null);
assert.equal(classifyOutboundAction('javascript:alert(1)'), null);

assert.deepEqual(buildOutboundEvent('contact', '/blog/kokugo-jakuten-shindan/?query=secret#cta'), {
	action_name: 'contact',
	source_page: '/blog/kokugo-jakuten-shindan/',
});
assert.equal(buildOutboundEvent('unknown', '/blog/'), null);
assert.equal(buildOutboundEvent('line', 'http://['), null);

const root = fileURLToPath(new URL('../dist/', import.meta.url));
for (const file of ['index.html', 'blog/kokugo-jakuten-shindan/index.html', 'privacy/index.html']) {
	const html = fs.readFileSync(path.join(root, file), 'utf8');
	assert.match(html, /googletagmanager\.com\/gtag\/js\?id=G-ND8MTF4N3J/);
}

const flagship = fs.readFileSync(path.join(root, 'blog/kokugo-jakuten-shindan/index.html'), 'utf8');
assert.match(
	flagship,
	/href="https:\/\/kokugosensei\.com\/course-diagnosis\.html"[^>]*>弱点診断パックの内容・料金を見る<\//,
);

console.log('Outbound tracking check passed: fixed actions, path-only source, GA4, diagnosis CTA');
