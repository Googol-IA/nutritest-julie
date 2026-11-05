// Capa de datos: Supabase (API REST) o, si no hay configuración, localStorage.
import { SUPABASE_URL, SUPABASE_KEY, ESQUEMA } from './config.js';

export const MODO_LOCAL = !SUPABASE_URL || !SUPABASE_KEY;

// ---------------------------------------------------------------- utilidades
const hoyMadrid = (fecha = new Date()) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid' }).format(fecha); // AAAA-MM-DD

function leer(clave, porDefecto) {
  try { const v = localStorage.getItem(clave); return v ? JSON.parse(v) : porDefecto; }
  catch { return porDefecto; }
}
function escribir(clave, valor) {
  try { localStorage.setItem(clave, JSON.stringify(valor)); } catch { /* sin espacio o bloqueado */ }
}

export function calcularRacha(dias) {
  // dias: array de 'AAAA-MM-DD'
  const set = new Set(dias);
  const d = new Date();
  let actual = hoyMadrid(d);
  if (!set.has(actual)) {
    d.setDate(d.getDate() - 1);
    actual = hoyMadrid(d);
    if (!set.has(actual)) return 0;
  }
  let racha = 0;
  while (set.has(hoyMadrid(d))) { racha++; d.setDate(d.getDate() - 1); }
  return racha;
}

// ---------------------------------------------------------------- Supabase REST
async function api(ruta, { metodo = 'GET', cuerpo, prefer } = {}) {
  const cabeceras = {
    apikey: SUPABASE_KEY,
    'Accept-Profile': ESQUEMA,
    'Content-Profile': ESQUEMA,
  };
  // Clave antigua «anon» (JWT, empieza por eyJ): va también en Authorization.
  // Clave nueva «publishable» (sb_publishable_…): solo en apikey.
  if (SUPABASE_KEY.startsWith('eyJ')) cabeceras.Authorization = `Bearer ${SUPABASE_KEY}`;
  if (cuerpo) cabeceras['Content-Type'] = 'application/json';
  if (prefer) cabeceras.Prefer = prefer;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${ruta}`, {
    method: metodo, headers: cabeceras, body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  if (!r.ok) throw new Error(`Supabase ${r.status}: ${await r.text()}`);
  return r.status === 204 ? null : r.json();
}

// Cola para respuestas guardadas sin conexión
const COLA = 'nutritest.cola';
async function vaciarCola() {
  const cola = leer(COLA, []);
  if (!cola.length) return;
  try {
    const respuestas = cola.filter(x => x.t === 'r').map(x => x.d);
    const examenes = cola.filter(x => x.t === 'e').map(x => x.d);
    if (respuestas.length) await api('respuestas', { metodo: 'POST', cuerpo: respuestas, prefer: 'return=minimal' });
    if (examenes.length) await api('examenes', { metodo: 'POST', cuerpo: examenes, prefer: 'return=minimal' });
    escribir(COLA, []);
  } catch { /* se reintentará */ }
}
async function insertarConCola(tabla, fila, tipo) {
  try {
    await vaciarCola();
    await api(tabla, { metodo: 'POST', cuerpo: fila, prefer: 'return=minimal' });
  } catch {
    const cola = leer(COLA, []);
    cola.push({ t: tipo, d: fila });
    escribir(COLA, cola);
  }
}
if (!MODO_LOCAL) window.addEventListener('online', vaciarCola);

const remoto = {
  listarPerfiles: () => api('perfiles?select=*&order=nombre.asc'),
  crearPerfil: async (p) => (await api('perfiles', { metodo: 'POST', cuerpo: p, prefer: 'return=representation' }))[0],
  borrarPerfil: (id) => api(`perfiles?id=eq.${id}`, { metodo: 'DELETE' }),
  guardarRespuesta: (r) => insertarConCola('respuestas', r, 'r'),
  guardarExamen: (e) => insertarConCola('examenes', e, 'e'),
  progresoTemas: (id) => api(`progreso_temas?perfil_id=eq.${id}&select=libro,tema,respondidas,aciertos,vistas,dominadas`),
  fallosPendientes: (id) => api(`fallos_pendientes?perfil_id=eq.${id}&select=pregunta_id,libro,tema&limit=5000`),
  diasEstudio: async (id) => (await api(`dias_estudio?perfil_id=eq.${id}&select=dia,respondidas&order=dia.desc&limit=400`)),
  examenes: (id) => api(`examenes?perfil_id=eq.${id}&select=*&order=fecha.desc&limit=10`),
  ranking: () => api('ranking?select=*'),
  // Preguntas ocultas: se guardan también en el dispositivo, por si la tabla aún no existe o no hay red
  async listarOcultas(id) {
    try {
      const filas = await api(`ocultas?perfil_id=eq.${id}&select=pregunta_id&limit=10000`);
      const ids = filas.map(f => f.pregunta_id);
      escribir(claveOcultas(id), ids);
      return ids;
    } catch { return leer(claveOcultas(id), []); }
  },
  async ocultar(id, preguntaId) {
    local.ocultar(id, preguntaId);
    try { await api('ocultas', { metodo: 'POST', cuerpo: { perfil_id: id, pregunta_id: preguntaId }, prefer: 'resolution=ignore-duplicates,return=minimal' }); } catch {}
  },
  async mostrar(id, preguntaId) {
    local.mostrar(id, preguntaId);
    try { await api(`ocultas?perfil_id=eq.${id}&pregunta_id=eq.${encodeURIComponent(preguntaId)}`, { metodo: 'DELETE' }); } catch {}
  },
};

const claveOcultas = (id) => `nutritest.ocultas.${id}`;

// ---------------------------------------------------------------- modo local
const L = { perfiles: 'nutritest.perfiles', resp: 'nutritest.respuestas', exa: 'nutritest.examenes' };

function estadoLocal(id) {
  const ultimo = new Map();
  for (const r of leer(L.resp, []).filter(r => r.perfil_id === id)) ultimo.set(r.pregunta_id, r); // orden cronológico
  return [...ultimo.values()];
}

const local = {
  async listarPerfiles() { return leer(L.perfiles, []).sort((a, b) => a.nombre.localeCompare(b.nombre)); },
  async crearPerfil(p) {
    const nuevo = { ...p, id: crypto.randomUUID(), creado_en: new Date().toISOString() };
    escribir(L.perfiles, [...leer(L.perfiles, []), nuevo]);
    return nuevo;
  },
  async borrarPerfil(id) {
    escribir(L.perfiles, leer(L.perfiles, []).filter(p => p.id !== id));
    escribir(L.resp, leer(L.resp, []).filter(r => r.perfil_id !== id));
    escribir(L.exa, leer(L.exa, []).filter(r => r.perfil_id !== id));
  },
  async guardarRespuesta(r) { escribir(L.resp, [...leer(L.resp, []), { ...r, fecha: new Date().toISOString() }]); },
  async guardarExamen(e) { escribir(L.exa, [...leer(L.exa, []), { ...e, fecha: new Date().toISOString() }]); },
  async progresoTemas(id) {
    const grupos = new Map();
    for (const r of leer(L.resp, []).filter(r => r.perfil_id === id)) {
      const k = `${r.libro}|${r.tema}`;
      const g = grupos.get(k) || { libro: r.libro, tema: r.tema, respondidas: 0, aciertos: 0, vistas: 0, dominadas: 0 };
      g.respondidas++; if (r.acertada) g.aciertos++;
      grupos.set(k, g);
    }
    for (const e of estadoLocal(id)) {
      const g = grupos.get(`${e.libro}|${e.tema}`);
      g.vistas++; if (e.acertada) g.dominadas++;
    }
    return [...grupos.values()];
  },
  async fallosPendientes(id) {
    return estadoLocal(id).filter(e => !e.acertada).map(({ pregunta_id, libro, tema }) => ({ pregunta_id, libro, tema }));
  },
  async diasEstudio(id) {
    const m = new Map();
    for (const r of leer(L.resp, []).filter(r => r.perfil_id === id)) {
      const d = hoyMadrid(new Date(r.fecha)); m.set(d, (m.get(d) || 0) + 1);
    }
    return [...m].map(([dia, respondidas]) => ({ dia, respondidas })).sort((a, b) => b.dia.localeCompare(a.dia));
  },
  async examenes(id) {
    return leer(L.exa, []).filter(e => e.perfil_id === id).reverse().slice(0, 10);
  },
  async ranking() {
    const hace30 = Date.now() - 30 * 864e5;
    const resp = leer(L.resp, []);
    return Promise.all(leer(L.perfiles, []).map(async p => {
      const mias = resp.filter(r => r.perfil_id === p.id && new Date(r.fecha) >= hace30);
      const dias = (await local.diasEstudio(p.id)).map(d => d.dia);
      return { perfil_id: p.id, nombre: p.nombre, avatar: p.avatar, color: p.color,
        respondidas: mias.length, aciertos: mias.filter(r => r.acertada).length, racha: calcularRacha(dias) };
    }));
  },
  async listarOcultas(id) { return leer(claveOcultas(id), []); },
  async ocultar(id, preguntaId) {
    const ids = new Set(leer(claveOcultas(id), [])); ids.add(preguntaId); escribir(claveOcultas(id), [...ids]);
  },
  async mostrar(id, preguntaId) {
    escribir(claveOcultas(id), leer(claveOcultas(id), []).filter(x => x !== preguntaId));
  },
};

export const datos = MODO_LOCAL ? local : remoto;
