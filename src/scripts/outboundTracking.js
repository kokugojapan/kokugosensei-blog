const BLOG_ORIGIN = 'https://blog.kokugosensei.com';
const MAIN_SITE_ORIGIN = 'https://kokugosensei.com';

export const BLOG_OUTBOUND_EVENT = 'blog_outbound_click';

const actionsByMainSitePath = new Map([
	['/', 'main_site'],
	['/course-diagnosis.html', 'diagnosis'],
	['/course-private.html', 'private_lesson'],
	['/contact.html', 'contact'],
]);

const knownActions = new Set([...actionsByMainSitePath.values(), 'line']);

/**
 * Returns a fixed action name for conversion links. Query strings and fragments
 * are intentionally ignored so they cannot become analytics event data.
 */
export function classifyOutboundAction(href) {
	let url;
	try {
		url = new URL(href, BLOG_ORIGIN);
	} catch {
		return null;
	}

	if (url.origin === MAIN_SITE_ORIGIN) {
		return actionsByMainSitePath.get(url.pathname) ?? null;
	}

	if (url.protocol === 'https:' && url.hostname === 'lin.ee') {
		return 'line';
	}

	return null;
}

/**
 * Produces the only event parameters sent for an outbound conversion click.
 */
export function buildOutboundEvent(actionName, source) {
	if (!knownActions.has(actionName)) return null;

	let sourcePage;
	try {
		sourcePage = new URL(source, BLOG_ORIGIN).pathname;
	} catch {
		return null;
	}

	return { action_name: actionName, source_page: sourcePage };
}
