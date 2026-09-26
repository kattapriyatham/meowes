import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const html = await readFile(new URL('./index.html', import.meta.url), 'utf8');
const css = await readFile(new URL('./landing.css', import.meta.url), 'utf8');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);

// The previous tests asserted the retired pinned animation's CSS. These check
// that the redesigned static site can ship with working assets and navigation.
test('navigation targets exist and IDs are unique', () => {
  assert.equal(new Set(ids).size, ids.length, 'duplicate IDs break anchor navigation');
  for (const [, target] of html.matchAll(/href="#([^"]*)"/g)) {
    assert.ok(target && ids.includes(target), `missing anchor: #${target}`);
  }
});

test('every referenced local asset and legal page is present', async () => {
  const attributes = [...html.matchAll(/(?:src|href|poster)="([^"]+)"/g)].map((match) => match[1]);
  const fonts = [...css.matchAll(/url\('([^']+)'\)/g)].map((match) => match[1]);
  for (const path of new Set([...attributes, ...fonts])) {
    if (/^(#|https?:|mailto:)/.test(path)) continue;
    await access(new URL(path.replace(/^\//, './'), import.meta.url));
  }
});

test('accessible labels point to existing elements and images have alternatives', () => {
  for (const [, references] of html.matchAll(/aria-(?:labelledby|controls)="([^"]+)"/g)) {
    for (const id of references.split(' ')) assert.ok(ids.includes(id), `missing accessible reference: ${id}`);
  }
  for (const [image] of html.matchAll(/<img\b[^>]*>/g)) {
    assert.match(image, /\balt="[^"]+"/, 'content images need descriptive alternatives');
    assert.match(image, /\bwidth="\d+"/);
    assert.match(image, /\bheight="\d+"/);
  }
  assert.equal([...html.matchAll(/<h1\b/g)].length, 1);
});

test('the original hero cat has a static fallback and inline playback', () => {
  const video = html.match(/<video\b[^>]*>/)?.[0];
  assert.ok(video);
  assert.match(video, /src="landing_assets\/cat-right-left-video\.mp4"/);
  assert.match(video, /poster="[^"]+"/);
  assert.match(video, /\bmuted\b/);
  assert.match(video, /\bplaysinline\b/);
  assert.doesNotMatch(video, /\bautoplay\b/);
});

test('page enhancement JavaScript parses', async () => {
  const script = await readFile(new URL('./landing.js', import.meta.url), 'utf8');
  assert.doesNotThrow(() => new vm.Script(script));
});

function catHarness({ heroLeft = 0, heroWidth = 1440, videoLeft = 744, videoWidth = 568, videoHeight = 492, reducedMotion = false } = {}) {
  const targets = new Map();
  const element = (selector) => {
    if (!targets.has(selector)) {
      const target = new EventTarget();
      Object.assign(target, {
        classList: { add() {}, remove() {}, toggle() {} },
        setAttribute() {}, getAttribute() { return 'false'; },
        getBoundingClientRect() { return selector === '#hero' ? { left: heroLeft, width: heroWidth, right: heroLeft + heroWidth } : { left: videoLeft, width: videoWidth, height: videoHeight }; },
      });
      targets.set(selector, target);
    }
    return targets.get(selector);
  };
  const video = element('.hero-cat-video');
  Object.assign(video, { duration: 6, readyState: 2, videoWidth: 1280, videoHeight: 720, currentTime: 2.05, seeking: false, seekable: { length: 1, start() { return 0; }, end() { return 6; } } });
  const media = (query) => Object.assign(new EventTarget(), { matches: query.includes('reduced-motion') ? reducedMotion : query.includes('pointer: fine') });
  const document = Object.assign(new EventTarget(), { querySelector: element });
  const frames = [];
  const context = vm.createContext({ document, window: { matchMedia: media }, requestAnimationFrame: (fn) => { frames.push(fn); return frames.length; }, cancelAnimationFrame() {} });
  return { context, video, move(x) {
    const event = new Event('pointermove');
    Object.assign(event, { clientX: x, pointerType: 'mouse' });
    element('#hero').dispatchEvent(event);
    for (let i = 0; i < 100 && frames.length; i++) { frames.shift()(i * 16); video.dispatchEvent(new Event('seeked')); }
    return video.currentTime;
  } };
}

const landingScript = await readFile(new URL('./landing.js', import.meta.url), 'utf8');

test('the meow follows the rendered cat, including right-aligned cover cropping', () => {
  const scene = catHarness();
  vm.runInContext(landingScript, scene.context);
  // Source face at 71% of 1280px, scaled to a 492px-tall right-aligned video.
  const catX = 744 + 568 - (1 - 0.71) * 1280 * (492 / 720);
  assert.ok(Math.abs(scene.move(catX) - 2.6) < 0.06, 'meow must coincide with the visible cat, not the hero midpoint');
});

test('pointer extremes hold left and right looks instead of the neutral bookends', () => {
  const left = catHarness();
  vm.runInContext(landingScript, left.context);
  assert.ok(Math.abs(left.move(0) - 1.4) < 0.06, 'far left should look left');
  const right = catHarness();
  vm.runInContext(landingScript, right.context);
  assert.ok(Math.abs(right.move(1440) - 3.7) < 0.06, 'far right should look right');
});

test('cat alignment survives a different layout and reduced motion stays still', () => {
  const scene = catHarness({ heroWidth: 768, videoLeft: 392, videoWidth: 344, videoHeight: 412 });
  vm.runInContext(landingScript, scene.context);
  const catX = 392 + 344 - (1 - 0.71) * 1280 * (412 / 720);
  assert.ok(Math.abs(scene.move(catX) - 2.6) < 0.06);
  const still = catHarness({ reducedMotion: true });
  vm.runInContext(landingScript, still.context);
  assert.equal(still.move(1400), 2.05);
});

test('unseekable media waits for data instead of repeatedly seeking to zero', () => {
  const scene = catHarness();
  scene.video.currentTime = 0;
  scene.video.seekable = { length: 1, start() { return 0; }, end() { return 0; } };
  vm.runInContext(landingScript, scene.context);
  assert.equal(scene.move(1440), 0);
  scene.video.seekable = { length: 1, start() { return 0; }, end() { return 6; } };
  scene.video.dispatchEvent(new Event('progress'));
  assert.ok(Math.abs(scene.move(1440) - 3.7) < 0.06);
});
