// Motor de test: barajar, crear sesiones y puntuar.
import { PENALIZACION } from './config.js';

export function barajar(lista) {
  const a = [...lista];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * Crea una sesión de test.
 * @param {object[]} preguntas  preguntas disponibles
 * @param {number|null} n       cuántas (null = todas)
 * @param {string} modo         estudio | aleatorio | fallos | simulacro
 */
export function crearSesion(preguntas, n, modo, extra = {}) {
  // enOrden: los exámenes oficiales se hacen en el orden original
  const elegidas = (extra.enOrden ? preguntas : barajar(preguntas)).slice(0, n || preguntas.length);
  return {
    modo,
    examen: modo === 'simulacro',
    // Las preguntas con «Todas son correctas», «a y c»… llevan orden_fijo: no se barajan sus opciones
    items: elegidas.map(p => {
      const pos = p.opciones.map((_, i) => i);   // 2, 3 o 4 opciones
      return { p, orden: p.orden_fijo ? pos : barajar(pos), elegida: null };
    }),
    i: 0,
    inicio: Date.now(),
    ...extra,
  };
}

export const esCorrecta = (item) => item.elegida !== null && item.elegida === item.p.correcta;

export function puntuar(sesion) {
  const total = sesion.items.length;
  const aciertos = sesion.items.filter(esCorrecta).length;
  const blancos = sesion.items.filter(it => it.elegida === null).length;
  const fallos = total - aciertos - blancos;
  const base = total ? (aciertos / total) * 10 : 0;
  const conPenalizacion = total ? Math.max(0, ((aciertos - fallos * PENALIZACION) / total) * 10) : 0;
  return {
    total, aciertos, fallos, blancos,
    nota: Math.round((sesion.examen ? conPenalizacion : base) * 100) / 100,
    notaSinPenalizacion: Math.round(base * 100) / 100,
    segundos: Math.round((Date.now() - sesion.inicio) / 1000),
  };
}
