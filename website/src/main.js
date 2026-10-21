import '@fontsource/ibm-plex-mono/latin-400.css';
import '@fontsource/ibm-plex-mono/latin-500.css';
import './styles.css';
import { mountDither } from './dither.js';

const root = document.documentElement;
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let manuallyPaused = false;

function motionPaused() { return manuallyPaused || reduceMotion.matches; }
function updateMotion() {
  root.dataset.motion = motionPaused() ? 'paused' : 'running';
  const toggle = document.querySelector('#motion-toggle');
  if (toggle) {
    toggle.setAttribute('aria-pressed', String(motionPaused()));
    toggle.disabled = reduceMotion.matches;
    toggle.querySelector('span').textContent = reduceMotion.matches ? 'Reduced motion' : manuallyPaused ? 'Resume motion' : 'Pause motion';
    toggle.querySelector('img').src = motionPaused() ? '/icons/play.svg' : '/icons/pause.svg';
  }
  document.dispatchEvent(new Event('dsmn:motion'));
}
reduceMotion.addEventListener('change', updateMotion);
document.querySelector('#motion-toggle')?.addEventListener('click', () => {
  manuallyPaused = !manuallyPaused;
  updateMotion();
});
updateMotion();

function track(event, data = {}) {
  if (!import.meta.env.PROD) return;
  const payload = JSON.stringify({
    event, path: window.location.pathname + window.location.search,
    referrer: document.referrer, ...data,
  });
  if (navigator.sendBeacon && navigator.sendBeacon('/api/events', new Blob([payload], { type: 'application/json' }))) return;
  fetch('/api/events', { body: payload, headers: { 'content-type': 'application/json' }, keepalive: true, method: 'POST' }).catch(() => {});
}
document.addEventListener('click', (event) => {
  const anchor = event.target?.closest?.('a[href]');
  if (!anchor) return;
  const url = new URL(anchor.href);
  if (url.origin !== window.location.origin || !url.pathname.startsWith('/download/')) return;
  track('download_click', { asset: decodeURIComponent(url.pathname.split('/').pop() ?? ''), path: url.pathname + url.search });
}, { capture: true });
track('page_view');

const downloadMenuButton = document.querySelector('#download-menu-button');
const downloadMenu = document.querySelector('#download-menu');
const omarchyDialog = document.querySelector('#omarchy-dialog');

function setDownloadMenu(open) {
  if (!downloadMenu || !downloadMenuButton) return;
  downloadMenu.hidden = !open;
  downloadMenuButton.setAttribute('aria-expanded', String(open));
}

downloadMenuButton?.addEventListener('click', (event) => {
  event.stopPropagation();
  setDownloadMenu(downloadMenu.hidden);
});
document.addEventListener('click', (event) => {
  if (!downloadMenu || downloadMenu.hidden) return;
  if (event.target instanceof Node && downloadMenu.parentElement?.contains(event.target)) return;
  setDownloadMenu(false);
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') setDownloadMenu(false);
});

function openOmarchy() {
  setDownloadMenu(false);
  omarchyDialog?.showModal();
}

if (location.hash === '#omarchy') openOmarchy();

document.querySelectorAll('[data-open-omarchy]').forEach((button) => {
  button.addEventListener('click', openOmarchy);
});
document.querySelector('[data-close-omarchy]')?.addEventListener('click', () => omarchyDialog?.close());
omarchyDialog?.addEventListener('click', (event) => {
  if (event.target !== omarchyDialog) return;
  const rect = omarchyDialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right ||
      event.clientY < rect.top || event.clientY > rect.bottom) omarchyDialog.close();
});

async function copyFrom(selector, button) {
  const node = document.querySelector(selector);
  if (!node) return;
  const label = button.querySelector('span');
  const original = label ? label.textContent : button.textContent;
  try {
    await navigator.clipboard.writeText(node.textContent.trim());
    if (label) label.textContent = 'Copied';
    else button.textContent = 'Copied';
  } catch {
    if (label) label.textContent = 'Copy failed';
    else button.textContent = 'Copy failed';
  }
  window.setTimeout(() => {
    if (label) label.textContent = original;
    else button.textContent = original;
  }, 1600);
}
document.querySelector('#copy-prompt')?.addEventListener('click', (event) => copyFrom('#agent-prompt', event.currentTarget));
document.querySelector('#copy-command')?.addEventListener('click', (event) => copyFrom('#install-command', event.currentTarget));

function mountPreview() {
  const stage = document.querySelector('#demo');
  if (!stage) return;
  const preview = document.querySelector('#app-preview');
  const menuToggle = document.querySelector('#menu-toggle');
  const clock = document.querySelector('#countdown');
  const barClock = document.querySelector('#bar-countdown');
  const status = document.querySelector('#awake-status');
  const requester = document.querySelector('#last-activity');
  const stop = document.querySelector('#stop-preview');
  const note = document.querySelector('#sleep-note');
  const announcement = document.querySelector('#preview-announcement');
  const dialog = document.querySelector('#duration-dialog');
  const input = document.querySelector('#duration-input');
  const error = document.querySelector('#duration-error');
  let deadline = Date.now() + 984_000;
  let lastAgent = 'Codex';
  let active = true;
  let timerId;
  let previousSeconds;

  function announce(message) { announcement.textContent = message; }
  function setOpen(open) {
    preview.hidden = !open;
    menuToggle.setAttribute('aria-expanded', String(open));
  }
  function render() {
    const seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
    const expired = seconds === 0 && active;
    if (expired) {
      active = false;
      announce('Preview timer ended. Sleep is allowed.');
    }
    stage.dataset.active = String(active);
    if (expired) document.dispatchEvent(new Event('dsmn:activity'));
    if (seconds !== previousSeconds) {
      clock.textContent = String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
      previousSeconds = seconds;
    }
    barClock.textContent = active ? (seconds < 60 ? '<1m' : Math.floor(seconds / 60) + 'm') : 'Off';
    status.textContent = active ? 'Keeping Mac awake' : 'Sleep is allowed';
    requester.textContent = 'Last activity: ' + lastAgent;
    stop.textContent = active ? 'Stop keeping awake' : 'Start a 20-minute timer';
    note.textContent = active ? 'Sleep allowed when the timer expires.' : 'Timer stopped. A little rest is allowed.';
    clearTimeout(timerId);
    if (active && !document.hidden) timerId = setTimeout(render, 1000);
  }
  function start(minutes, source, selectedDuration = null) {
    deadline = Date.now() + minutes * 60_000;
    active = true;
    lastAgent = source;
    document.querySelectorAll('[data-minutes]').forEach((button) => button.setAttribute('aria-pressed', String(Number(button.dataset.minutes) === selectedDuration)));
    render();
    setOpen(true);
    document.dispatchEvent(new Event('dsmn:activity'));
    announce('Preview keeping awake for ' + minutes + ' minutes. Last activity: ' + source + '.');
  }
  menuToggle.addEventListener('click', () => setOpen(preview.hidden));
  preview.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !dialog.open) {
      setOpen(false);
      menuToggle.focus();
    }
  });
  document.querySelectorAll('[data-minutes]').forEach((button) => {
    button.setAttribute('aria-pressed', 'false');
    button.addEventListener('click', () => start(Number(button.dataset.minutes), 'Manual timer', Number(button.dataset.minutes)));
  });
  stop.addEventListener('click', () => {
    if (!active) { start(20, 'Manual timer'); return; }
    deadline = 0;
    active = false;
    document.querySelectorAll('[data-minutes]').forEach((button) => button.setAttribute('aria-pressed', 'false'));
    render();
    document.dispatchEvent(new Event('dsmn:activity'));
    announce('Preview stopped. Sleep is allowed.');
  });
  document.querySelectorAll('[data-agent]').forEach((button) => {
    button.addEventListener('click', () => {
      document.querySelectorAll('[data-agent]').forEach((other) => other.setAttribute('aria-pressed', String(other === button)));
      start(20, button.dataset.agent);
    });
  });
  document.querySelector('#custom-duration').addEventListener('click', () => {
    error.textContent = '';
    input.removeAttribute('aria-invalid');
    dialog.showModal();
    input.focus();
    input.select();
  });
  dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', (event) => {
    if (event.target !== dialog) return;
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close();
  });
  document.querySelector('#duration-form').addEventListener('submit', (event) => {
    event.preventDefault();
    const minutes = input.valueAsNumber;
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 720) {
      error.textContent = 'Enter a whole number from 1 to 720.';
      input.setAttribute('aria-invalid', 'true');
      input.focus();
      return;
    }
    start(minutes, 'Manual timer');
    dialog.close();
  });
  input.addEventListener('input', () => { error.textContent = ''; input.removeAttribute('aria-invalid'); });
  document.addEventListener('visibilitychange', render);
  render();
}
mountPreview();
mountDither({ motionPaused });

function mountButtonDither() {
  // DitherButton from tripwire.sh/dither-kit: Bayer gradient, dense at the
  // bottom, denser again on hover and press. The button's ink ground is the
  // dark surface that kit assumes. Omarchy uses the aura bloom preset.
  const bayer = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ].map((row) => row.map((value) => (value + 0.5) / 16));
  const clamp = (value) => (value < 0 ? 0 : value > 1 ? 1 : value);
  document.querySelectorAll('.download-button').forEach((button) => {
    const canvas = button.querySelector('canvas.button-dither');
    const context = canvas?.getContext('2d');
    if (!canvas || !context) return;
    const spark = button.classList.contains('spark');
    const fill = spark ? [216, 90, 56] : [98, 107, 85];
    let bloom = button.querySelector('canvas.button-bloom');
    if (spark && !bloom) {
      bloom = document.createElement('canvas');
      bloom.className = 'button-bloom';
      bloom.setAttribute('aria-hidden', 'true');
      button.insertBefore(bloom, canvas.nextSibling);
    }
    const bloomContext = bloom?.getContext('2d') ?? null;
    let cols = 0;
    let rows = 0;
    let intensity = 0;
    let target = 0;
    let hovered = false;
    let frame = 0;
    const paint = () => {
      context.clearRect(0, 0, cols, rows);
      for (let y = 0; y < rows; y++) {
        const density = 0.25 + 0.75 * ((y + 0.5) / rows);
        for (let x = 0; x < cols; x++) {
          const lit = density > bayer[y & 3][x & 3] - 0.1 * intensity;
          const k = (0.3 + density * 0.7) * (1 + 0.22 * intensity);
          const alpha = clamp(lit ? k : k * 0.4);
          context.fillStyle = `rgba(${fill[0]},${fill[1]},${fill[2]},${alpha})`;
          context.fillRect(x, y, 1, 1);
        }
      }
      context.fillStyle = `rgba(${fill[0]},${fill[1]},${fill[2]},${clamp(0.5 + 0.25 * intensity)})`;
      context.fillRect(0, 0, cols, 1);
      context.fillRect(0, rows - 1, cols, 1);
      context.fillRect(0, 0, 1, rows);
      context.fillRect(cols - 1, 0, 1, rows);
      if (bloomContext) {
        bloomContext.clearRect(0, 0, cols, rows);
        bloomContext.drawImage(canvas, 0, 0);
      }
    };
    const tick = () => {
      const delta = target - intensity;
      if (Math.abs(delta) < 0.01) {
        intensity = target;
        paint();
        frame = 0;
        return;
      }
      intensity += delta * 0.16;
      paint();
      frame = requestAnimationFrame(tick);
    };
    const setTarget = (value) => {
      target = value;
      if (motionPaused()) {
        intensity = value;
        paint();
        return;
      }
      if (!frame) frame = requestAnimationFrame(tick);
    };
    const resize = () => {
      const box = button.getBoundingClientRect();
      cols = Math.max(4, Math.round(box.width / 2));
      rows = Math.max(4, Math.round(box.height / 2));
      canvas.width = cols;
      canvas.height = rows;
      if (bloom) {
        bloom.width = cols;
        bloom.height = rows;
      }
      paint();
    };
    resize();
    new ResizeObserver(resize).observe(button);
    button.addEventListener('pointerenter', () => { hovered = true; setTarget(1); });
    button.addEventListener('pointerleave', () => { hovered = false; setTarget(0); });
    button.addEventListener('pointerdown', () => setTarget(1.5));
    button.addEventListener('pointerup', () => setTarget(hovered ? 1 : 0));
    button.addEventListener('pointercancel', () => setTarget(hovered ? 1 : 0));
  });
}
mountButtonDither();

async function mountAgentation() {
  if (!import.meta.env.DEV) return;
  const [{ default: React }, { createRoot }, { Agentation }] = await Promise.all([
    import('react'), import('react-dom/client'), import('agentation'),
  ]);
  const mount = document.createElement('div');
  mount.id = 'agentation-root';
  document.body.appendChild(mount);
  createRoot(mount).render(React.createElement(Agentation, { copyToClipboard: true, endpoint: import.meta.env.VITE_AGENTATION_ENDPOINT }));
}
mountAgentation();
