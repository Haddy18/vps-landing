/* ═══ Recarga en vivo tras un despliegue ═══════════════════════
 * scripts/deploy.sh escribe un version.txt con la marca del despliegue, y lo
 * hace ANTES del intercambio atómico del directorio: el fichero nuevo y su
 * version.txt entran de golpe, así que nunca se mezclan versiones.
 *
 * Este módulo sondea ese fichero cada pocos segundos y, si ha cambiado,
 * recarga la pestaña: el despliegue se ve al instante, sin tocar F5.
 *
 * En local no hay version.txt (ni en `python -m http.server` ni en el
 * dev-server, que ya tiene su propia recarga por SSE), así que el sondeo no
 * hace nada: es un recurso exclusivo del sitio publicado.
 *
 * Sin dependencias: fetch + setInterval. Cero peticiones cuando la pestaña
 * no está visible.
 */
const INTERVAL_MS = 5000;

// Versión que la pestaña tiene cargada; null hasta el primer sondeo.
let current = null;

function toast() {
  const el = document.createElement('div');
  el.textContent = 'Nueva versión desplegada · recargando…';
  el.setAttribute('role', 'status');
  Object.assign(el.style, {
    position: 'fixed',
    left: '50%',
    bottom: '18px',
    transform: 'translateX(-50%)',
    padding: '8px 14px',
    borderRadius: '999px',
    zIndex: '2147483647',
    font: '12px/1.2 system-ui, -apple-system, sans-serif',
    letterSpacing: '.02em',
    color: '#eaf1ff',
    background: 'rgba(16,22,38,.92)',
    border: '1px solid rgba(255,255,255,.18)',
    boxShadow: '0 6px 24px rgba(0,0,0,.45)',
    pointerEvents: 'none',
    opacity: '0',
    transition: 'opacity .2s ease'
  });
  document.body.appendChild(el);
  requestAnimationFrame(() => { el.style.opacity = '1'; });
}

async function probe() {
  let body;
  try {
    const res = await fetch('version.txt', { cache: 'no-store' });
    if (!res.ok) return;                       // sin version.txt: no hay despliegue
    body = (await res.text()).trim();
  } catch {
    return;                                    // red caída o directorio a medias: reintenta
  }
  if (!body) return;
  if (current === null) { current = body; return; }  // es la versión que ya se ve
  if (body === current) return;
  current = body;
  toast();
  setTimeout(() => location.reload(), 600);    // margen para que se vea el aviso
}

// Solo en pestañas visibles: nada de sondeos en segundo plano.
setInterval(() => { if (document.visibilityState === 'visible') probe(); }, INTERVAL_MS);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') probe();
});
probe();
