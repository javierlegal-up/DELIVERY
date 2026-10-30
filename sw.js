/* Service worker de LUNK: permite instalar la app y abrirla rápido, incluso sin conexión.
   Si cambias la lista de archivos o quieres forzar una limpieza, sube la versión. */
const CACHE = 'lunk-v1';
const TAILWIND = 'https://cdn.tailwindcss.com/3.4.17';
const ARCHIVOS = ['./index.html', './manifest.webmanifest', './icon.svg'];

// Instalación: guarda los archivos propios y, si se puede, Tailwind
self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches.open(CACHE).then(async (cache) => {
      await cache.addAll(ARCHIVOS);
      try {
        // addAll no acepta respuestas "opacas" de otro dominio, por eso se guarda aparte
        const respuesta = await fetch(TAILWIND, { mode: 'no-cors' });
        await cache.put(TAILWIND, respuesta);
      } catch {
        // Sin Tailwind en caché la app se instala igual; se guardará en la próxima visita
      }
      await self.skipWaiting();
    })
  );
});

// Activación: elimina cachés de versiones anteriores
self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches.keys()
      .then((claves) => Promise.all(claves.filter((c) => c !== CACHE).map((c) => caches.delete(c))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (evento) => {
  const { request } = evento;
  if (request.method !== 'GET') return;

  // La página va primero a la red: así un cambio en el número del delivery llega de inmediato.
  // La copia guardada solo se usa si no hay conexión.
  if (request.mode === 'navigate') {
    evento.respondWith(
      fetch(request)
        .then((respuesta) => {
          if (respuesta.ok) {
            const copia = respuesta.clone();
            caches.open(CACHE).then((cache) => cache.put('./index.html', copia));
          }
          return respuesta;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Resto de archivos: responde con la copia guardada y la actualiza en segundo plano
  const url = new URL(request.url);
  if (url.origin === self.location.origin || request.url === TAILWIND) {
    evento.respondWith(
      caches.open(CACHE).then(async (cache) => {
        const guardada = await cache.match(request);
        const actualizada = fetch(request)
          .then((respuesta) => {
            if (respuesta.ok || respuesta.type === 'opaque') cache.put(request, respuesta.clone());
            return respuesta;
          })
          .catch(() => guardada);
        return guardada || actualizada;
      })
    );
  }
});
