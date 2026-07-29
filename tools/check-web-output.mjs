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
const decodeAttribute = (value) => value
  .replaceAll('&amp;', '&')
  .replaceAll('&quot;', '"')
  .replaceAll('&#39;', "'");
const parseAttributes = (source) => Object.fromEntries(
  [...source.matchAll(/\b([:\w-]+)="([^"]*)"/g)]
    .map(([, name, value]) => [name, decodeAttribute(value)]),
);
const tags = (html, tagName) => [...html.matchAll(new RegExp(`<${tagName}\\b([^>]*)>`, 'g'))]
  .map((match) => parseAttributes(match[1]));
const metaContent = (html, key) => tags(html, 'meta')
  .find((attributes) => attributes.property === key || attributes.name === key)
  ?.content ?? null;
const canonicalHref = (html) => tags(html, 'link')
  .find((attributes) => attributes.rel === 'canonical')
  ?.href ?? null;
const pictures = (html) => [...html.matchAll(/<picture\b[^>]*>[\s\S]*?<\/picture>/g)].map((match) => match[0]);
const pictureImage = (picture) => tags(picture, 'img')[0] ?? null;
const pictureByAlt = (html, alt) => pictures(html).find((picture) => pictureImage(picture)?.alt === alt) ?? null;
const pictureTypes = (picture) => tags(picture, 'source').map((attributes) => attributes.type);
const pictureWidths = (picture) => [...new Set(
  tags(picture, 'source').flatMap((attributes) => [...(attributes.srcset ?? '').matchAll(/\s(\d+)w(?:,|$)/g)]
    .map((match) => Number(match[1]))),
)].sort((left, right) => left - right);
const assertJpegFallback = (picture, label) => {
  const image = pictureImage(picture);
  assert.match(image.src, /\.jpg$/, `${label} fallback src should be JPEG`);
  const srcsetUrls = image.srcset.split(',').map((candidate) => candidate.trim().split(/\s+/)[0]);
  assert.ok(srcsetUrls.length > 0, `${label} fallback should emit a srcset`);
  assert.ok(srcsetUrls.every((url) => url.endsWith('.jpg')), `${label} fallback srcset should contain only JPEG files`);
};
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
const heroAlt = 'Günün ilk ışıklarında kuzeye ilerleyen otomobil ve Adria karavan';
const galleryAlts = [
  'Karavanla otoyolda yolculuk',
  'Budapeşte yolunda karavan',
  'Sofya şehir içinde karavan',
];
const heroPicture = pictureByAlt(home, heroAlt);
assert.ok(heroPicture, 'the built homepage should render the hero through a picture element');
assert.deepEqual(pictureTypes(heroPicture), ['image/avif', 'image/webp'], 'the hero should offer AVIF before WebP');
const heroWidths = pictureWidths(heroPicture);
for (const width of [640, 960, 1440]) {
  assert.ok(heroWidths.includes(width), `the hero should emit its requested ${width}px source`);
}
assert.equal(Math.max(...heroWidths), 1536, 'the hero should cap its responsive output at the source width');
const heroImageAttributes = pictureImage(heroPicture);
assertJpegFallback(heroPicture, 'hero');
assert.deepEqual(
  {
    width: heroImageAttributes.width,
    height: heroImageAttributes.height,
    sizes: heroImageAttributes.sizes,
    alt: heroImageAttributes.alt,
    loading: heroImageAttributes.loading,
    decoding: heroImageAttributes.decoding,
    fetchpriority: heroImageAttributes.fetchpriority,
    class: heroImageAttributes.class,
  },
  {
    width: '1536',
    height: '1024',
    sizes: '(min-width: 760px) 58vw, 100vw',
    alt: heroAlt,
    loading: 'eager',
    decoding: 'sync',
    fetchpriority: 'high',
    class: 'journey-hero__image',
  },
  'the hero should preserve its intrinsic geometry, class, alt, and high-priority loading contract',
);

const galleryPictures = galleryAlts.map((alt) => pictureByAlt(home, alt));
assert.ok(galleryPictures.every(Boolean), 'the gallery should preserve all three photos and their exact alt order');
assert.deepEqual(
  pictures(home).map((picture) => pictureImage(picture)?.alt).filter((alt) => galleryAlts.includes(alt)),
  galleryAlts,
  'the gallery should preserve its image order',
);
const naturalGalleryWidths = [1536, 1800, 1448];
for (const [index, picture] of galleryPictures.entries()) {
  assert.deepEqual(pictureTypes(picture), ['image/avif', 'image/webp'], `${galleryAlts[index]} should offer AVIF before WebP`);
  assert.deepEqual(pictureWidths(picture), [420, 720, 1080], `${galleryAlts[index]} should emit the requested gallery widths`);
  assert.ok(Math.max(...pictureWidths(picture)) <= naturalGalleryWidths[index], `${galleryAlts[index]} should never upscale its source`);
  assertJpegFallback(picture, galleryAlts[index]);
  assert.equal(pictureImage(picture).loading, 'lazy', `${galleryAlts[index]} should remain lazy-loaded`);
}
assert.doesNotMatch(
  home,
  /\/assets\/(?:hero\/kuzey-road-motion\.webp|follow-(?:highway\.jpg|budapest\.jpg|sofia\.png))/,
  'the built homepage should not reference the former public journey images',
);

const productionOrigin = 'https://istanbul-letonya-karavan-astro.vercel.app';
const homeCanonical = `${productionOrigin}/`;
const homeTitle = metaContent(home, 'og:title');
const homeDescription = metaContent(home, 'og:description');
const homeImage = metaContent(home, 'og:image');
assert.equal(canonicalHref(home), homeCanonical, 'the homepage should have its exact production canonical');
assert.equal(metaContent(home, 'og:type'), 'website', 'the homepage should identify as a website');
assert.equal(metaContent(home, 'og:url'), homeCanonical, 'the homepage Open Graph URL should match its canonical');
assert.ok(homeTitle && homeDescription && homeImage, 'the homepage should emit complete Open Graph metadata');
assert.doesNotThrow(() => new URL(homeImage), 'the homepage social image should be absolute');
assert.equal(metaContent(home, 'twitter:title'), homeTitle, 'homepage Twitter and Open Graph titles should agree');
assert.equal(metaContent(home, 'twitter:description'), homeDescription, 'homepage Twitter and Open Graph descriptions should agree');
assert.equal(metaContent(home, 'twitter:image'), homeImage, 'homepage Twitter and Open Graph images should agree');
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

  const canonical = `${productionOrigin}/day/${expectation.slug}/`;
  const title = metaContent(html, 'og:title');
  const description = metaContent(html, 'og:description');
  const image = metaContent(html, 'og:image');
  assert.equal(canonicalHref(html), canonical, `${expectation.slug} should have its exact production canonical`);
  assert.equal(metaContent(html, 'og:type'), 'article', `${expectation.slug} should identify as an article`);
  assert.equal(metaContent(html, 'og:url'), canonical, `${expectation.slug} Open Graph URL should match its canonical`);
  assert.notEqual(title, homeTitle, `${expectation.slug} should have a distinct title`);
  assert.notEqual(description, homeDescription, `${expectation.slug} should have a distinct description`);
  assert.notEqual(image, homeImage, `${expectation.slug} should have a distinct social image`);
  assert.doesNotThrow(() => new URL(image), `${expectation.slug} social image should be absolute`);
  assert.equal(metaContent(html, 'twitter:title'), title, `${expectation.slug} Twitter and Open Graph titles should agree`);
  assert.equal(metaContent(html, 'twitter:description'), description, `${expectation.slug} Twitter and Open Graph descriptions should agree`);
  assert.equal(metaContent(html, 'twitter:image'), image, `${expectation.slug} Twitter and Open Graph images should agree`);
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
