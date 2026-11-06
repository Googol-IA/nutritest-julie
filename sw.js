// La web se ha mudado a https://nutritest-julie.netlify.app/
// Este service worker borra la caché de la versión antigua, se da de baja y recarga las pestañas abiertas.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) await caches.delete(k);
    await self.registration.unregister();
    for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url);
  })());
});
