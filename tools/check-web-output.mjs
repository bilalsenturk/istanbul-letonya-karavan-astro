import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputRoot = path.join(root, 'dist/client');
const { buildCampLinks } = await import(pathToFileURL(path.join(root, 'src/scripts/journeyExperience.ts')).href);
const dayExpectations = [
  { slug: 'istanbul-sofya', destination: '42.63252,23.57471', website: null },
  { slug: 'sofya-novi-sad', destination: '45.2410861,20.0255373', website: 'https://campuccino.org/' },
  { slug: 'novi-sad-budapest', destination: '47.504162,19.1561948', website: 'https://arenacamping.eu/en' },
  { slug: 'budapest-krakow', destination: '50.0467778,19.9031667', website: 'https://campingadam.pl/' },
  { slug: 'krakow-varsova', destination: '52.17798,21.14727', website: 'https://campingwok.warszawa.pl/' },
  { slug: 'varsova-riga', destination: '56.96117,24.09431', website: 'https://campingyachts.lv/' },
];

const readOutput = (relativePath) => readFile(path.join(outputRoot, relativePath), 'utf8');
const decodeAttribute = (value) => value.replaceAll('&amp;', '&');
const linkByText = (html, text) => {
  const match = [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)]
    .find(([, , body]) => body.replace(/<[^>]*>/g, '').trim() === text);
  if (!match) return null;
  const href = match[1].match(/\bhref="([^"]+)"/)?.[1];
  return href ? decodeAttribute(href) : null;
};
const headingLevels = (html) => [...html.matchAll(/<h([1-6])\b/g)].map((match) => Number(match[1]));
const assertDayHeadingOrder = (html, slug) => {
  const headings = headingLevels(html);
  assert.equal(headings[0], 1, `${slug} should start with h1`);
  assert.equal(headings.slice(1).includes(1), false, `${slug} should contain only one h1`);
  assert.equal(headings.some((level) => level > 3), false, `${slug} should not skip below h3`);

  let hasSectionHeading = false;
  for (const level of headings.slice(1)) {
    if (level === 2) hasSectionHeading = true;
    if (level === 3) assert.equal(hasSectionHeading, true, `${slug} child h3 should follow a section h2`);
  }
};

const home = await readOutput('index.html');
const homeRuntimeHref = [...home.matchAll(/<script\b[^>]*type="module"[^>]*src="([^"]+)"/g)]
  .map((match) => match[1])
  .find((href) => href.includes('index.astro_astro_type_script'));
assert.ok(homeRuntimeHref, 'the built homepage should load its orchestration from a generated module asset');
const homeRuntimeBundle = await readOutput(homeRuntimeHref.replace(/^\//, ''));
assert.match(homeRuntimeBundle, /\/api\/v2\/public\/trips\/kuzey-2026/);
assert.match(homeRuntimeBundle, /\/live-location/);
assert.match(homeRuntimeBundle, /\/expense-summary/);
assert.match(homeRuntimeBundle, /\/published-plan/);
assert.match(homeRuntimeBundle, /\/api\/roadfeed/);
assert.doesNotMatch(homeRuntimeBundle, /setInterval\s*\(/, 'the built homepage runtime should not contain overlapping interval polls');
assert.match(homeRuntimeBundle, /visibilitychange/, 'the built homepage runtime should pause while hidden');
assert.match(homeRuntimeBundle, /pagehide/, 'the built homepage runtime should stop during page teardown');
assert.match(homeRuntimeBundle, /pageshow/, 'the built homepage runtime should resume after bfcache restoration');
const expectedDayHrefs = dayExpectations.map(({ slug }) => `/day/${slug}`);
const actualDayHrefs = [...home.matchAll(/<a\b[^>]*href="([^"]+)"[^>]*>Gün planını aç<\/a>/g)]
  .map((match) => decodeAttribute(match[1]));
assert.deepEqual(actualDayHrefs, expectedDayHrefs, 'built home should link every timeline leg to its exact day slug');

assert.match(home, /role="timer"[^>]*aria-live="off"/, 'the built countdown should be a quiet timer');
assert.match(
  home,
  /role="progressbar"[^>]*aria-valuemin="0"[^>]*aria-valuemax="100"[^>]*aria-valuenow="0"/,
  'the built route progress should expose its complete range and value',
);
assert.equal((home.match(/role="status"/g) ?? []).length, 1, 'the built home should have one polite status');
assert.match(home, /class="sr-only"[^>]*role="status"[^>]*aria-live="polite"/, 'route status should be visually hidden and polite');
assert.match(home, /data-route-codes="[^"]*&quot;RS&quot;/, 'built route metadata should include Serbia as RS');

const dayPages = await Promise.all(dayExpectations.map(async (expectation) => ({
  expectation,
  html: await readOutput(path.join('day', expectation.slug, 'index.html')),
})));

for (const { expectation, html } of dayPages) {
  const directionHref = linkByText(html, 'Kesin kamp rotasını aç');
  assert.ok(directionHref, `${expectation.slug} should render its camp direction action`);
  assert.equal(
    new URL(directionHref).searchParams.get('destination'),
    expectation.destination,
    `${expectation.slug} should use its exact arrival coordinates`,
  );
  assert.equal(linkByText(html, 'Kamp web sitesi'), expectation.website, `${expectation.slug} should apply its camp-site policy`);
  assert.match(html, /aria-current="step"/, `${expectation.slug} should expose its current route step`);
  assert.match(html, /style="--route-stop-count: 7;"/, `${expectation.slug} should expose the dynamic stop count`);
  assertDayHeadingOrder(html, expectation.slug);
  assert.doesNotMatch(html, />Şehir Kameraları<\/h2>/, `${expectation.slug} should omit its empty camera section`);
}

assert.match(dayPages[1].html, />🇷🇸<\//, 'built route steps should include Serbia metadata');

const fallbackLinks = buildCampLinks({
  camp: { place: 'Fallback Camping, Riga, Letonya', link: 'https://fallback-camping.test/' },
});
assert.equal(
  new URL(fallbackLinks.directionsURL).searchParams.get('destination'),
  'Fallback Camping, Riga, Letonya',
  'camp directions should fall back to the camp place when coordinates are absent',
);
for (const googleLink of [
  'https://maps.app.goo.gl/AbCdEf',
  'https://goo.gl/maps/AbCdEf',
  'https://maps.google.com/?q=camp',
]) {
  assert.equal(buildCampLinks({ camp: { place: 'Camp', link: googleLink } }).websiteURL, null);
}

const stylesheetHrefs = new Set(
  dayPages.flatMap(({ html }) => [...html.matchAll(/<link\b[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)].map((match) => match[1])),
);
const builtCss = (await Promise.all([...stylesheetHrefs].map((href) => readOutput(href.replace(/^\//, ''))))).join('\n');
assert.match(builtCss, /\.accordion[^}]*summary\{[^}]*min-height:44px/, 'country-guide summaries should have a 44px target');
assert.match(builtCss, /\.open-link[^}]*\{[^}]*min-height:44px/, 'camera actions should have a 44px target');

console.log('Built web output checks passed.');
