const menuButton = document.querySelector('.menu-toggle');
const navigation = document.querySelector('#main-navigation');

function closeMenu() {
  navigation.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
  menuButton.textContent = 'Menu';
}

menuButton.addEventListener('click', () => {
  const open = menuButton.getAttribute('aria-expanded') !== 'true';
  navigation.classList.toggle('is-open', open);
  menuButton.setAttribute('aria-expanded', String(open));
  menuButton.textContent = open ? 'Close' : 'Menu';
});
navigation.addEventListener('click', (event) => {
  if (event.target.closest('a')) closeMenu();
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {
    closeMenu();
    menuButton.focus();
  }
});
document.addEventListener('click', (event) => {
  if (!event.target.closest('.site-nav')) closeMenu();
});
window.matchMedia('(min-width: 701px)').addEventListener('change', closeMenu);

// Calibrated to the existing clip: neutral bookends are outside the scrub range.
// The cat's face is at 71% of the source width, not the centre of the video.
const hero = document.querySelector('#hero');
const video = document.querySelector('.hero-cat-video');
const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');
const catFrames = { left: 1.4, meow: 2.6, right: 3.7, rest: 2.05 };
let targetTime = catFrames.rest;
let seeking = false;
let seekFrame = null;
let requestedTime = catFrames.rest;

function queueCatSeek() {
  if (seekFrame !== null) return;
  seekFrame = requestAnimationFrame(() => {
    seekFrame = null;
    seekCat();
  });
}

function seekCat() {
  if (!Number.isFinite(video.duration) || seeking || video.readyState < 1 || video.seeking) return;
  const time = Math.min(video.duration - 0.05, Math.max(0, targetTime));
  const ranges = video.seekable;
  const canSeek = Array.from({ length: ranges.length }, (_, index) => index)
    .some((index) => time >= ranges.start(index) && time <= ranges.end(index));
  if (!canSeek) return;
  if (Math.abs(video.currentTime - time) < 0.025) return;
  seeking = true;
  requestedTime = time;
  video.currentTime = time;
}

['loadedmetadata', 'loadeddata', 'progress', 'canplaythrough'].forEach((event) => {
  video.addEventListener(event, queueCatSeek);
});
video.addEventListener('seeked', () => {
  seeking = false;
  // Only follow up when the pointer moved during a seek. An unseekable response
  // must not cause an endless seeked -> seek loop.
  if (Math.abs(requestedTime - targetTime) > 0.025) queueCatSeek();
});
hero.addEventListener('pointermove', (event) => {
  if (motionPreference.matches || !finePointer.matches || event.pointerType !== 'mouse') return;
  const bounds = hero.getBoundingClientRect();
  const frame = video.getBoundingClientRect();
  const sourceWidth = video.videoWidth || 1280;
  const sourceHeight = video.videoHeight || 720;
  const scale = Math.max(frame.width / sourceWidth, frame.height / sourceHeight);
  // Match object-fit: cover and object-position: 100% center in landing.css.
  const catX = frame.left + frame.width - sourceWidth * scale * (1 - 0.71);
  const side = event.clientX < catX ? 'left' : 'right';
  const distance = side === 'left' ? catX - bounds.left : bounds.right - catX;
  const position = Math.min(1, Math.max(0, Math.abs(event.clientX - catX) / Math.max(1, distance)));
  targetTime = catFrames.meow + position * (catFrames[side] - catFrames.meow);
  queueCatSeek();
});
hero.addEventListener('pointerleave', () => {
  targetTime = catFrames.rest;
  queueCatSeek();
});
motionPreference.addEventListener('change', () => {
  targetTime = catFrames.rest;
  queueCatSeek();
});
if (video.readyState >= 1) queueCatSeek();

// Native details and anchor links keep the rest of the page usable without scripts.
