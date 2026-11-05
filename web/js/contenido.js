// Carga del catálogo de libros y de las preguntas de cada tema (archivos JSON).
let catalogo = null;
let oficiales = null;   // «libro» virtual con los exámenes oficiales: cada examen es un tema
const cacheTemas = new Map();
export const ID_OFICIALES = 'oficiales';

export async function cargarCatalogo() {
  if (catalogo) return catalogo;
  const r = await fetch('contenido/libros.json', { cache: 'no-cache' });
  catalogo = (await r.json()).libros
    .map((l, i) => ({ estado: 'activo', numero: i + 1, temas: [], ...l }))
    .sort((a, b) => a.numero - b.numero);
  try {
    const ind = await (await fetch('contenido/oficiales/indice.json', { cache: 'no-cache' })).json();
    oficiales = {
      id: ID_OFICIALES, nombre: 'Exámenes oficiales', corto: 'Oficiales', icono: '🏛️', color: '#7a5bc4', estado: 'activo',
      temas: ind.examenes.map((e, i) => ({ ...e, nombre: e.titulo, numero: i + 1 })),
    };
  } catch { oficiales = null; }
  return catalogo;
}

export const libroOficiales = () => oficiales;

// Libro con preguntas disponibles (los "proximamente" no entran en tests ni simulacros)
export const disponible = (l) => l.estado !== 'proximamente' && l.temas.length > 0;
export const nombreCorto = (l) => l.corto || l.nombre;
export const libroPorId = (id) => (id === ID_OFICIALES ? oficiales : catalogo.find(l => l.id === id));
export const temaPorId = (libroId, temaId) => libroPorId(libroId)?.temas.find(t => t.id === temaId);
export const totalPreguntasLibro = (libro) => libro.temas.reduce((s, t) => s + (t.preguntas || 0), 0);

export async function cargarTema(libroId, temaId) {
  const clave = `${libroId}/${temaId}`;
  if (cacheTemas.has(clave)) return cacheTemas.get(clave);
  const tema = temaPorId(libroId, temaId);
  const promesa = fetch(`contenido/${libroId}/${tema.archivo}`)
    .then(r => r.json())
    .then(j => j.preguntas.map(p => ({ ...p, libro: libroId, tema: temaId })));
  cacheTemas.set(clave, promesa);
  return promesa;
}

export async function cargarLibro(libroId, temaIds = null) {
  const libro = libroPorId(libroId);
  const temas = libro.temas.filter(t => !temaIds || temaIds.includes(t.id));
  return (await Promise.all(temas.map(t => cargarTema(libroId, t.id)))).flat();
}

export async function cargarVarios(libroIds) {
  return (await Promise.all(libroIds.map(id => cargarLibro(id)))).flat();
}

// Devuelve las preguntas cuyo id está en la lista (para "Repasar mis fallos")
export async function preguntasPorIds(refs) {
  const porTema = new Map();
  for (const r of refs) {
    if (!temaPorId(r.libro, r.tema)) continue;          // tema retirado
    const k = `${r.libro}|${r.tema}`;
    if (!porTema.has(k)) porTema.set(k, new Set());
    porTema.get(k).add(r.pregunta_id);
  }
  const listas = await Promise.all([...porTema].map(async ([k, ids]) => {
    const [libro, tema] = k.split('|');
    return (await cargarTema(libro, tema)).filter(p => ids.has(p.id));
  }));
  return listas.flat();
}
