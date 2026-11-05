// Service worker: la web funciona sin conexión con lo último que se haya cargado.
// Estrategia "red primero": si hay internet, siempre se ve la versión más nueva.
const CACHE = 'nutritest-v6';
const BASE = ['./', 'index.html', 'css/estilos.css', 'js/app.js', 'js/datos.js', 'js/contenido.js', 'js/test.js', 'js/config.js',
  'contenido/libros.json', 'manifest.webmanifest', 'iconos/icono.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(BASE.map(u => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return; // Supabase y fuentes: directo
  // cache: 'no-cache' → el navegador siempre pregunta a GitHub si hay versión nueva
  // (GitHub Pages guarda los archivos 10 min; sin esto se veían versiones antiguas)
  const aRed = e.request.mode === 'navigate' ? fetch(url.href, { cache: 'no-cache' }) : fetch(e.request, { cache: 'no-cache' });
  e.respondWith(
    aRed
      .then(r => { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); return r; })
      .catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
