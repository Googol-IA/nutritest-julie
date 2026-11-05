// NutriTest de Julie · navegación y pantallas
import { datos, MODO_LOCAL, calcularRacha } from './datos.js';
import { cargarCatalogo, libroPorId, temaPorId, totalPreguntasLibro, cargarLibro, cargarVarios, preguntasPorIds, disponible, nombreCorto } from './contenido.js';
import { crearSesion, puntuar, esCorrecta } from './test.js';
import { PENALIZACION, MINUTOS_POR_PREGUNTA } from './config.js';

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const principal = $('#principal');
const esc = (t) => String(t ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
const LETRAS = ['A', 'B', 'C', 'D'];
const AVATARES = [
  ['🍎', '#e0524a'], ['🥑', '#5f9a3a'], ['🥕', '#e8822e'], ['🍓', '#d9435e'], ['🍋', '#d9b02a'], ['🥦', '#3f8f4f'],
  ['🍇', '#8a55b5'], ['🍑', '#ec8a5e'], ['🥝', '#7aa83a'], ['🍒', '#c2304a'], ['🍉', '#df5b6c'], ['🍍', '#d6a12a'],
  ['🫐', '#4f63b8'], ['🍊', '#ef8a24'], ['🥥', '#8b6a4e'], ['🌽', '#d9a91f'],
];
const NOMBRE_MODO = { estudio: 'Test del libro', aleatorio: 'Aleatorio de todo el FP', fallos: 'Repaso de fallos', simulacro: 'Simulacro de examen' };

// ---------------------------------------------------------------- estado
const estado = {
  perfil: null,
  sesion: null,
  resultado: null,
  temporizador: null,
  ocultas: new Set(),      // ids de preguntas que este perfil no quiere volver a ver
  ocultasDe: null,
};

// Crea una sesión sin las preguntas ocultas por el perfil
function nuevaSesion(preguntas, ...resto) {
  return crearSesion(preguntas.filter(p => !estado.ocultas.has(p.id)), ...resto);
}

async function alternarOculta(pregunta) {
  const id = pregunta.id;
  if (estado.ocultas.has(id)) {
    estado.ocultas.delete(id);
    await datos.mostrar(estado.perfil.id, id);
    avisar('La pregunta volverá a salir');
  } else {
    estado.ocultas.add(id);
    await datos.ocultar(estado.perfil.id, id);
    avisar('No volverá a salir');
  }
}

const botonOcultar = (p) => {
  const oculta = estado.ocultas.has(p.id);
  return `<button class="boton-ocultar ${oculta ? 'activo' : ''}" type="button" data-ocultar="${esc(p.id)}" aria-pressed="${oculta}">
    ${oculta ? '↩️ Oculta · volver a mostrar' : '🚫 No volver a mostrar esta pregunta'}</button>`;
};

function eventosOcultar(preguntas) {
  $$('[data-ocultar]').forEach(b => b.onclick = async () => {
    const p = preguntas.find(x => x.id === b.dataset.ocultar);
    await alternarOculta(p);
    b.outerHTML = botonOcultar(p);
    eventosOcultar(preguntas);
    $(`[data-ocultar="${CSS.escape(p.id)}"]`)?.focus();
  });
}
const CLAVE_PERFIL = 'nutritest.perfilActual';
function recordarPerfil(id) { try { id ? localStorage.setItem(CLAVE_PERFIL, id) : localStorage.removeItem(CLAVE_PERFIL); } catch {} }
function perfilRecordado() { try { return localStorage.getItem(CLAVE_PERFIL); } catch { return null; } }

// ---------------------------------------------------------------- utilidades de interfaz
let temporizadorAviso;
function avisar(texto, mostrar = true) {
  const a = $('#aviso');
  a.textContent = texto;
  if (!mostrar) return;                 // solo para lectores de pantalla
  a.classList.add('visible');
  clearTimeout(temporizadorAviso);
  temporizadorAviso = setTimeout(() => a.classList.remove('visible'), 2600);
}

function pintar(html, { volver = null, titulo = null } = {}) {
  principal.innerHTML = html;
  const bVolver = $('#volver');
  bVolver.hidden = !volver;
  bVolver.onclick = volver ? () => (typeof volver === 'function' ? volver() : ir(volver)) : null;
  const bPerfil = $('#barra-perfil');
  if (estado.perfil) {
    bPerfil.hidden = false;
    bPerfil.textContent = estado.perfil.avatar;
    bPerfil.style.setProperty('--c', estado.perfil.color);
    bPerfil.setAttribute('aria-label', `Perfil de ${estado.perfil.nombre}. Cambiar de perfil`);
  } else bPerfil.hidden = true;
  document.title = titulo ? `${titulo} · NutriTest de Julie` : 'NutriTest de Julie · FP Superior de Dietética';
  window.scrollTo(0, 0);
  const h1 = $('h1', principal);
  if (h1) { h1.setAttribute('tabindex', '-1'); h1.focus({ preventScroll: true }); }
}

function cargando() { principal.innerHTML = '<div class="cargando" aria-label="Cargando"><span></span><span></span><span></span></div>'; }

function error(e) {
  console.error(e);
  pintar(`<section class="vacio"><div class="vacio-icono" aria-hidden="true">🥴</div>
    <h1>Algo no ha ido bien</h1><p>Revisa la conexión a internet y vuelve a intentarlo.</p>
    <button class="boton" type="button" id="reintentar">Reintentar</button></section>`);
  $('#reintentar').onclick = () => router();
}

const barra = (valor, color) => `<div class="barra-progreso" role="presentation"><span style="width:${Math.min(100, valor)}%;${color ? `background:${color}` : ''}"></span></div>`;

function lanzarConfeti() {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const capa = document.createElement('div');
  capa.className = 'confeti';
  capa.setAttribute('aria-hidden', 'true');
  const piezas = ['🍎', '🥑', '🍓', '🥕', '🍋', '🫐', '✨', '🍇'];
  for (let i = 0; i < 28; i++) {
    const s = document.createElement('span');
    s.textContent = piezas[i % piezas.length];
    s.style.left = `${Math.random() * 100}%`;
    s.style.animationDelay = `${Math.random() * 0.6}s`;
    s.style.animationDuration = `${1.6 + Math.random() * 1.2}s`;
    capa.append(s);
  }
  document.body.append(capa);
  setTimeout(() => capa.remove(), 3600);
}

// ---------------------------------------------------------------- router
function ir(ruta) { if (location.hash === `#/${ruta}`) router(); else location.hash = `#/${ruta}`; }

async function router() {
  clearInterval(estado.temporizador);
  const [ruta, ...args] = location.hash.replace(/^#\/?/, '').split('/');
  try {
    await cargarCatalogo();
    if (!estado.perfil && !['perfiles', 'nuevo'].includes(ruta)) {
      const id = perfilRecordado();
      if (id) estado.perfil = (await datos.listarPerfiles()).find(p => p.id === id) || null;
      if (!estado.perfil) return ir('perfiles');
    }
    if (estado.perfil && estado.ocultasDe !== estado.perfil.id) {
      estado.ocultas = new Set(await datos.listarOcultas(estado.perfil.id));
      estado.ocultasDe = estado.perfil.id;
    }
    switch (ruta) {
      case 'perfiles': return pantallaPerfiles(args[0] === 'gestionar');
      case 'nuevo': return pantallaNuevoPerfil();
      case 'libro': return pantallaLibro(args[0]);
      case 'config': return pantallaConfig(args[0]);
      case 'test': return estado.sesion ? pantallaPregunta() : ir('inicio');
      case 'resultado': return estado.resultado ? pantallaResultado() : ir('inicio');
      case 'estadisticas': return pantallaEstadisticas();
      case 'ranking': return pantallaRanking();
      default: return pantallaInicio();
    }
  } catch (e) { error(e); }
}

window.addEventListener('hashchange', () => {
  // Salir de un test con el botón "atrás" del móvil
  if (estado.sesion && !location.hash.startsWith('#/test')) {
    const hechas = estado.sesion.items.filter(it => it.elegida !== null).length;
    if (hechas > 0 && !estado.sesion.terminada && !confirm('¿Salir del test? Las respuestas ya contestadas quedan guardadas.')) {
      history.pushState(null, '', '#/test');
      return;
    }
    estado.sesion = null;
  }
  router();
});
$('#barra-perfil').onclick = () => ir('perfiles');

// ---------------------------------------------------------------- 1. Perfiles
async function pantallaPerfiles(gestionar = false) {
  cargando();
  const perfiles = await datos.listarPerfiles();
  estado.perfil = null;
  pintar(`
    <section class="portada">
      <div class="portada-dibujo" aria-hidden="true">🥗</div>
      <h1>¿Quién estudia hoy?</h1>
      <p class="lead">Tests del FP Superior de Dietética</p>
    </section>
    ${MODO_LOCAL ? '<p class="nota-local">Modo de prueba: el progreso se guarda solo en este dispositivo.</p>' : ''}
    <ul class="perfiles" role="list">
      ${perfiles.map(p => `
        <li>
          <button class="perfil" type="button" data-id="${p.id}" style="--c:${esc(p.color)}">
            <span class="perfil-avatar" aria-hidden="true">${esc(p.avatar)}</span>
            <span class="perfil-nombre">${esc(p.nombre)}</span>
          </button>
          ${gestionar ? `<button class="perfil-borrar" type="button" data-borrar="${p.id}" aria-label="Borrar el perfil de ${esc(p.nombre)}">Borrar</button>` : ''}
        </li>`).join('')}
      <li><a class="perfil perfil-nuevo" href="#/nuevo"><span class="perfil-avatar" aria-hidden="true">＋</span><span class="perfil-nombre">Nuevo perfil</span></a></li>
    </ul>
    ${perfiles.length ? `<p class="centro"><a class="enlace-suave" href="#/perfiles${gestionar ? '' : '/gestionar'}">${gestionar ? 'Hecho' : 'Gestionar perfiles'}</a></p>` : ''}
  `, { titulo: 'Perfiles' });
  $$('.perfil[data-id]').forEach(b => b.onclick = () => {
    estado.perfil = perfiles.find(p => p.id === b.dataset.id);
    recordarPerfil(estado.perfil.id);
    ir('inicio');
  });
  $$('[data-borrar]').forEach(b => b.onclick = async () => {
    const p = perfiles.find(x => x.id === b.dataset.borrar);
    if (!confirm(`¿Borrar el perfil de ${p.nombre} y todo su progreso? No se puede deshacer.`)) return;
    await datos.borrarPerfil(p.id);
    if (perfilRecordado() === p.id) recordarPerfil(null);
    avisar(`Perfil de ${p.nombre} borrado`);
    pantallaPerfiles(true);
  });
}

function pantallaNuevoPerfil() {
  estado.perfil = null;
  pintar(`
    <form class="tarjeta formulario" id="form-perfil" novalidate>
      <h1>Nuevo perfil</h1>
      <label class="campo">
        <span>¿Cómo te llamas?</span>
        <input id="nombre" name="nombre" type="text" maxlength="40" autocomplete="given-name" autocapitalize="words" required placeholder="Por ejemplo, Julie">
      </label>
      <fieldset class="campo">
        <legend>Elige tu fruta</legend>
        <div class="avatares">
          ${AVATARES.map(([a, c], i) => `
            <label class="avatar-opcion" style="--c:${c}">
              <input type="radio" name="avatar" value="${i}" ${i === 0 ? 'checked' : ''}>
              <span aria-hidden="true">${a}</span><span class="solo-lector">${a}</span>
            </label>`).join('')}
        </div>
      </fieldset>
      <p class="error-campo" id="error-nombre" role="alert"></p>
      <button class="boton boton-grande" type="submit">Crear y empezar</button>
    </form>`, { volver: 'perfiles', titulo: 'Nuevo perfil' });
  $('#nombre').focus();
  $('#form-perfil').onsubmit = async (ev) => {
    ev.preventDefault();
    const nombre = $('#nombre').value.trim();
    if (!nombre) { $('#error-nombre').textContent = 'Escribe un nombre para el perfil.'; $('#nombre').focus(); return; }
    const [avatar, color] = AVATARES[Number(new FormData(ev.target).get('avatar'))];
    const boton = $('button[type=submit]', ev.target);
    boton.disabled = true; boton.textContent = 'Creando…';
    try {
      estado.perfil = await datos.crearPerfil({ nombre, avatar, color });
      recordarPerfil(estado.perfil.id);
      avisar(`¡Bienvenida, ${nombre}!`);
      ir('inicio');
    } catch (e) { boton.disabled = false; boton.textContent = 'Crear y empezar'; error(e); }
  };
}

// ---------------------------------------------------------------- 2. Inicio
async function pantallaInicio() {
  cargando();
  const libros = await cargarCatalogo();
  const [progreso, dias, fallos] = await Promise.all([
    datos.progresoTemas(estado.perfil.id), datos.diasEstudio(estado.perfil.id), datos.fallosPendientes(estado.perfil.id),
  ]);
  const racha = calcularRacha(dias.map(d => d.dia));
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid' }).format(new Date());
  const hoyRespondidas = dias.find(d => d.dia === hoy)?.respondidas || 0;
  const fallosValidos = fallos.filter(f => temaPorId(f.libro, f.tema) && !estado.ocultas.has(f.pregunta_id)).length;
  const hayPreguntas = libros.some(disponible);

  pintar(`
    <section class="saludo">
      <h1>¡Hola, ${esc(estado.perfil.nombre)}! <span aria-hidden="true">👋</span></h1>
      <div class="racha ${racha ? 'activa' : ''}">
        <span class="racha-fuego" aria-hidden="true">🔥</span>
        <div>
          <strong>${racha ? `${racha} ${racha === 1 ? 'día' : 'días'} seguidos` : 'Empieza tu racha hoy'}</strong>
          <span>${hoyRespondidas ? `Hoy llevas ${hoyRespondidas} preguntas` : 'Aún no has respondido nada hoy'}</span>
        </div>
      </div>
    </section>

    <h2 class="seccion">Tus libros</h2>
    <ul class="libros" role="list">
      ${libros.map(l => {
        if (l.estado === 'proximamente') {
          return `<li><div class="libro libro-proximo" style="--c:${l.color}" aria-disabled="true">
            <span class="libro-icono" aria-hidden="true">${l.icono}</span>
            <span class="libro-texto"><strong>${esc(l.nombre)}</strong><span class="etiqueta">Próximamente</span></span>
          </div></li>`;
        }
        const total = totalPreguntasLibro(l);
        const dominadas = progreso.filter(p => p.libro === l.id).reduce((s, p) => s + Number(p.dominadas), 0);
        const v = pct(dominadas, total);
        return `<li><a class="libro" href="#/libro/${l.id}" style="--c:${l.color}">
          <span class="libro-icono" aria-hidden="true">${l.icono}</span>
          <span class="libro-texto">
            <strong>${esc(l.nombre)}</strong>
            <span>${l.temas.length ? `${l.temas.length} ${l.temas.length === 1 ? 'tema' : 'temas'} · ${total} preguntas` : 'Próximamente'}</span>
            ${l.temas.length ? `${barra(v, l.color)}<span class="libro-pct">${v}% dominado</span>` : ''}
          </span>
          <svg class="flecha" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>
        </a></li>`;
      }).join('')}
    </ul>

    <h2 class="seccion">Practica</h2>
    <div class="acciones">
      <a class="accion accion-destacada" href="#/config/aleatorio" ${hayPreguntas ? '' : 'aria-disabled="true"'}>
        <span class="accion-icono" aria-hidden="true">🎲</span><strong>Aleatorio de todo el FP</strong><span>Mezcla de todos los libros</span></a>
      <button class="accion" type="button" id="btn-fallos" ${fallosValidos ? '' : 'disabled'}>
        <span class="accion-icono" aria-hidden="true">🔁</span><strong>Repasar mis fallos</strong>
        <span>${fallosValidos ? `${fallosValidos} pendientes` : 'Sin fallos pendientes'}</span></button>
      <a class="accion" href="#/config/simulacro"><span class="accion-icono" aria-hidden="true">📝</span><strong>Simulacro de examen</strong><span>Con nota y penalización</span></a>
      <a class="accion" href="#/estadisticas"><span class="accion-icono" aria-hidden="true">📊</span><strong>Estadísticas</strong><span>Tus puntos fuertes y flojos</span></a>
      <a class="accion" href="#/ranking"><span class="accion-icono" aria-hidden="true">🏆</span><strong>Ranking</strong><span>Último mes</span></a>
    </div>
  `, { titulo: 'Inicio' });

  $('#btn-fallos').onclick = async () => {
    const preguntas = await preguntasPorIds(fallos);
    if (!preguntas.length) return avisar('No hay fallos pendientes');
    empezar(nuevaSesion(preguntas, 20, 'fallos', { libros: [...new Set(preguntas.map(p => p.libro))] }));
  };
}

// ---------------------------------------------------------------- 3. Libro
async function pantallaLibro(libroId) {
  const libro = libroPorId(libroId);
  if (!libro) return ir('inicio');
  if (!disponible(libro)) {
    return pintar(`<section class="vacio"><div class="vacio-icono" aria-hidden="true">${libro.icono}</div>
      <h1>${esc(libro.nombre)}</h1><p>Todavía no hay temas de este libro. ¡Muy pronto habrá preguntas!</p>
      <a class="boton" href="#/inicio">Volver al inicio</a></section>`, { volver: 'inicio', titulo: libro.nombre });
  }
  cargando();
  const progreso = (await datos.progresoTemas(estado.perfil.id)).filter(p => p.libro === libroId);
  pintar(`
    <section class="cabecera-libro" style="--c:${libro.color}">
      <span class="libro-icono" aria-hidden="true">${libro.icono}</span>
      <h1>${esc(libro.nombre)}</h1>
    </section>
    <form id="form-libro">
      <fieldset class="temas">
        <legend class="seccion">Temas <button type="button" class="enlace-suave" id="todos">Quitar todos</button></legend>
        ${libro.temas.map(t => {
          const p = progreso.find(x => x.tema === t.id);
          const acierto = p ? pct(p.aciertos, p.respondidas) : null;
          return `<label class="tema">
            <input type="checkbox" name="tema" value="${t.id}" checked>
            <span class="tema-check" aria-hidden="true"></span>
            <span class="tema-texto">
              <span class="tema-num">Tema ${t.numero}</span>
              <strong>${esc(t.titulo)}</strong>
              <span class="tema-datos">${t.preguntas} preguntas · ${p ? `${p.dominadas} dominadas · ${acierto}% acierto` : 'sin empezar'}</span>
              ${barra(pct(p?.dominadas || 0, t.preguntas), libro.color)}
            </span>
          </label>`;
        }).join('')}
      </fieldset>
      ${selectorCantidad([10, 20, 40, 0], 20)}
      <div class="pie-fijo"><button class="boton boton-grande" type="submit" id="empezar">Empezar test</button></div>
    </form>
  `, { volver: 'inicio', titulo: libro.nombre });

  const casillas = $$('input[name=tema]');
  const actualizar = () => {
    const n = casillas.filter(c => c.checked).length;
    $('#todos').textContent = n === casillas.length ? 'Quitar todos' : 'Marcar todos';
    $('#empezar').disabled = n === 0;
    $('#empezar').textContent = n ? `Empezar test (${n} ${n === 1 ? 'tema' : 'temas'})` : 'Elige al menos un tema';
  };
  casillas.forEach(c => c.onchange = actualizar);
  $('#todos').onclick = () => { const marcar = casillas.some(c => !c.checked); casillas.forEach(c => (c.checked = marcar)); actualizar(); };
  actualizar();
  $('#form-libro').onsubmit = async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const temas = f.getAll('tema');
    const preguntas = await cargarLibro(libroId, temas);
    empezar(nuevaSesion(preguntas, Number(f.get('cantidad')) || null, 'estudio', { libros: [libroId] }));
  };
}

function selectorCantidad(opciones, porDefecto) {
  return `<fieldset class="cantidad">
    <legend class="seccion">¿Cuántas preguntas?</legend>
    <div class="chips">
      ${opciones.map(n => `<label class="chip"><input type="radio" name="cantidad" value="${n}" ${n === porDefecto ? 'checked' : ''}><span>${n || 'Todas'}</span></label>`).join('')}
    </div>
  </fieldset>`;
}

// ---------------------------------------------------------------- 4. Configurar aleatorio / simulacro
function pantallaConfig(modo) {
  return configurar(modo === 'simulacro' ? 'simulacro' : 'aleatorio');
}

async function configurar(modo) {
  const libros = (await cargarCatalogo()).filter(disponible);
  const sim = modo === 'simulacro';
  if (!libros.length) {
    return pintar(`<section class="vacio"><div class="vacio-icono" aria-hidden="true">📚</div>
      <h1>${NOMBRE_MODO[modo]}</h1><p>Aún no hay temas cargados. En cuanto se añadan, podrás practicar aquí.</p>
      <a class="boton" href="#/inicio">Volver al inicio</a></section>`, { volver: 'inicio', titulo: NOMBRE_MODO[modo] });
  }
  pintar(`
    <section class="cabecera-modo">
      <span class="accion-icono" aria-hidden="true">${sim ? '📝' : '🎲'}</span>
      <h1>${NOMBRE_MODO[modo]}</h1>
      <p>${sim
        ? `Como un examen de verdad: no verás la solución hasta entregar. Cada fallo resta ${PENALIZACION === 1 / 3 ? '1/3 (3 fallos quitan 1 acierto)' : PENALIZACION.toFixed(2)}; en blanco no resta.`
        : 'Preguntas al azar de los libros que elijas, con la explicación al momento.'}</p>
    </section>
    <form id="form-config">
      <fieldset class="cantidad">
        <legend class="seccion">Libros</legend>
        <div class="chips chips-libros">
          ${libros.map(l => `<label class="chip chip-libro" style="--c:${l.color}"><input type="checkbox" name="libro" value="${l.id}" checked><span><span aria-hidden="true">${l.icono}</span> ${esc(nombreCorto(l))}</span></label>`).join('')}
        </div>
      </fieldset>
      ${selectorCantidad(sim ? [20, 40, 60, 100] : [10, 20, 40], sim ? 40 : 20)}
      ${sim ? `<label class="interruptor">
        <input type="checkbox" name="tiempo" checked>
        <span class="interruptor-pista" aria-hidden="true"></span>
        <span>Con tiempo límite <small>(${MINUTOS_POR_PREGUNTA} min por pregunta)</small></span>
      </label>` : ''}
      <p class="error-campo" id="error-config" role="alert"></p>
      <div class="pie-fijo"><button class="boton boton-grande" type="submit">${sim ? 'Empezar simulacro' : 'Empezar'}</button></div>
    </form>
  `, { volver: 'inicio', titulo: NOMBRE_MODO[modo] });

  $('#form-config').onsubmit = async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const ids = f.getAll('libro');
    if (!ids.length) { $('#error-config').textContent = 'Elige al menos un libro.'; return; }
    const preguntas = await cargarVarios(ids);
    const n = Number(f.get('cantidad'));
    const extra = { libros: ids };
    if (sim && f.get('tiempo')) extra.limite = Math.min(n, preguntas.length) * MINUTOS_POR_PREGUNTA * 60;
    empezar(nuevaSesion(preguntas, n, modo, extra));
  };
}

// ---------------------------------------------------------------- 5. Test
function empezar(sesion) {
  if (!sesion.items.length) return avisar('No quedan preguntas: las has ocultado todas');
  estado.sesion = sesion;
  estado.resultado = null;
  ir('test');
}

function salirTest() {
  if (confirm(estado.sesion.examen ? '¿Abandonar el simulacro? No se guardará la nota.' : '¿Salir del test? Las respuestas ya contestadas quedan guardadas.')) {
    estado.sesion = null;
    ir('inicio');
  }
}

function cabeceraTest(s) {
  const respondidas = s.items.filter(it => it.elegida !== null).length;
  return `<div class="test-cabecera">
    <div class="test-info">
      <span>${NOMBRE_MODO[s.modo]}</span>
      <strong>Pregunta ${s.i + 1} de ${s.items.length}</strong>
      ${s.limite ? '<span class="reloj" id="reloj" role="timer" aria-label="Tiempo restante"></span>' : ''}
    </div>
    ${barra(pct(s.examen ? respondidas : s.i + (s.items[s.i].elegida !== null ? 1 : 0), s.items.length))}
  </div>`;
}

function pantallaPregunta() {
  const s = estado.sesion;
  const it = s.items[s.i];
  const libro = libroPorId(it.p.libro);
  const tema = temaPorId(it.p.libro, it.p.tema);
  const respondida = it.elegida !== null;
  const mostrarSolucion = !s.examen && respondida;

  pintar(`
    ${cabeceraTest(s)}
    <article class="pregunta" aria-labelledby="enunciado">
      <p class="pregunta-origen" style="--c:${libro.color}"><span aria-hidden="true">${libro.icono}</span> ${esc(nombreCorto(libro))} · Tema ${tema?.numero ?? ''}</p>
      <h1 id="enunciado" class="enunciado">${esc(it.p.pregunta)}</h1>
      <div class="opciones" role="group" aria-label="Opciones de respuesta">
        ${it.orden.map((o, k) => {
          let clase = '';
          if (mostrarSolucion) clase = o === it.p.correcta ? 'correcta' : o === it.elegida ? 'incorrecta' : 'apagada';
          else if (s.examen && o === it.elegida) clase = 'elegida';
          return `<button class="opcion ${clase}" type="button" data-o="${o}" ${mostrarSolucion ? 'disabled' : ''} aria-pressed="${o === it.elegida}">
            <span class="opcion-letra" aria-hidden="true">${LETRAS[k]}</span>
            <span class="opcion-texto">${esc(it.p.opciones[o])}</span>
            ${clase === 'correcta' ? '<span class="opcion-marca" aria-label="Respuesta correcta">✓</span>' : ''}
            ${clase === 'incorrecta' ? '<span class="opcion-marca" aria-label="Tu respuesta, incorrecta">✕</span>' : ''}
          </button>`;
        }).join('')}
      </div>
      ${mostrarSolucion ? `
        <div class="explicacion ${esCorrecta(it) ? 'bien' : 'mal'}">
          <strong>${esCorrecta(it) ? '¡Correcto! 🎉' : 'No es correcta'}</strong>
          ${!esCorrecta(it) ? `<p class="explicacion-correcta">La respuesta correcta es la <b>${LETRAS[it.orden.indexOf(it.p.correcta)]}</b>.</p>` : ''}
          <p>${esc(it.p.explicacion)}</p>
        </div>
        ${botonOcultar(it.p)}` : ''}
    </article>
    ${s.examen ? navegacionExamen(s) : `
      <div class="pie-fijo pie-test">
        <button class="boton-texto" type="button" id="salir">Salir</button>
        ${respondida ? `<button class="boton boton-grande" type="button" id="siguiente">${s.i + 1 < s.items.length ? 'Siguiente' : 'Ver resultado'}</button>` : '<span class="pista">Toca una respuesta</span>'}
      </div>`}
  `, { volver: salirTest, titulo: `Pregunta ${s.i + 1}` });

  // Después de responder, llevar el foco a la explicación / siguiente
  if (mostrarSolucion) $('#siguiente')?.focus({ preventScroll: true });

  $$('.opcion').forEach(b => b.onclick = () => responder(Number(b.dataset.o)));
  $('#siguiente')?.addEventListener('click', siguiente);
  $('#salir')?.addEventListener('click', salirTest);
  eventosOcultar([it.p]);
  if (s.examen) eventosExamen(s);
  if (s.limite) iniciarReloj(s);
}

function responder(o) {
  const s = estado.sesion;
  const it = s.items[s.i];
  if (s.examen) {
    it.elegida = it.elegida === o ? null : o;        // tocar otra vez = dejar en blanco
    return pantallaPregunta();
  }
  if (it.elegida !== null) return;
  it.elegida = o;
  const bien = esCorrecta(it);
  avisar(bien ? '¡Correcto!' : 'Incorrecta', false);
  if (navigator.vibrate && !bien) navigator.vibrate(60);
  datos.guardarRespuesta({ perfil_id: estado.perfil.id, pregunta_id: it.p.id, libro: it.p.libro, tema: it.p.tema, acertada: bien, modo: s.modo });
  const scroll = window.scrollY;
  pantallaPregunta();
  window.scrollTo(0, scroll);
  if (bien) $('.opcion.correcta')?.classList.add('pop');
  const reducido = matchMedia('(prefers-reduced-motion: reduce)').matches;
  $('.explicacion')?.scrollIntoView({ block: 'nearest', behavior: reducido ? 'auto' : 'smooth' });
}

function siguiente() {
  const s = estado.sesion;
  if (s.i + 1 < s.items.length) { s.i++; pantallaPregunta(); }
  else terminar();
}

// ----- Simulacro: navegación libre, mapa y entrega
function navegacionExamen(s) {
  return `
    <details class="mapa">
      <summary>Ver todas las preguntas (${s.items.filter(it => it.elegida !== null).length}/${s.items.length} respondidas)</summary>
      <div class="mapa-rejilla">
        ${s.items.map((it, k) => `<button type="button" class="mapa-n ${it.elegida !== null ? 'hecha' : ''} ${k === s.i ? 'actual' : ''}" data-ir="${k}" aria-label="Pregunta ${k + 1}${it.elegida !== null ? ', respondida' : ', en blanco'}">${k + 1}</button>`).join('')}
      </div>
    </details>
    <div class="pie-fijo pie-examen">
      <button class="boton boton-secundario" type="button" id="anterior" ${s.i === 0 ? 'disabled' : ''} aria-label="Pregunta anterior">‹</button>
      <button class="boton boton-entregar" type="button" id="entregar">Entregar</button>
      <button class="boton boton-secundario" type="button" id="posterior" ${s.i + 1 === s.items.length ? 'disabled' : ''} aria-label="Pregunta siguiente">›</button>
    </div>`;
}

function eventosExamen(s) {
  $('#anterior').onclick = () => { s.i--; pantallaPregunta(); };
  $('#posterior').onclick = () => { s.i++; pantallaPregunta(); };
  $$('[data-ir]').forEach(b => b.onclick = () => { s.i = Number(b.dataset.ir); pantallaPregunta(); });
  $('#entregar').onclick = () => {
    const blancos = s.items.filter(it => it.elegida === null).length;
    if (confirm(blancos ? `Tienes ${blancos} en blanco. ¿Entregar el simulacro?` : '¿Entregar el simulacro?')) terminar();
  };
}

function iniciarReloj(s) {
  const pintarReloj = () => {
    const quedan = Math.max(0, s.limite - Math.round((Date.now() - s.inicio) / 1000));
    const r = $('#reloj');
    if (r) {
      r.textContent = `⏱ ${Math.floor(quedan / 60)}:${String(quedan % 60).padStart(2, '0')}`;
      r.classList.toggle('poco', quedan < 120);
    }
    if (quedan === 0) { clearInterval(estado.temporizador); alert('¡Se acabó el tiempo! Vamos a corregir.'); terminar(); }
  };
  clearInterval(estado.temporizador);
  pintarReloj();
  estado.temporizador = setInterval(pintarReloj, 1000);
}

function terminar() {
  clearInterval(estado.temporizador);
  const s = estado.sesion;
  s.terminada = true;
  const r = puntuar(s);
  if (s.examen) {
    s.items.filter(it => it.elegida !== null).forEach(it => datos.guardarRespuesta({
      perfil_id: estado.perfil.id, pregunta_id: it.p.id, libro: it.p.libro, tema: it.p.tema, acertada: esCorrecta(it), modo: 'simulacro',
    }));
  }
  datos.guardarExamen({
    perfil_id: estado.perfil.id, tipo: s.modo, libros: (s.libros || []).join(','), n_preguntas: r.total,
    aciertos: r.aciertos, fallos: r.fallos, blancos: r.blancos, nota: r.nota, segundos: r.segundos,
  });
  estado.resultado = { sesion: s, ...r };
  estado.sesion = null;
  ir('resultado');
}

// ---------------------------------------------------------------- 6. Resultado
function pantallaResultado() {
  const r = estado.resultado;
  const s = r.sesion;
  const mensaje = r.nota >= 9 ? ['🏆', '¡Espectacular!'] : r.nota >= 7 ? ['🌟', '¡Muy bien!'] : r.nota >= 5 ? ['👍', '¡Aprobado!'] : ['💪', 'A seguir practicando'];
  const falladas = s.items.filter(it => it.elegida !== null && !esCorrecta(it));
  const min = Math.floor(r.segundos / 60), seg = r.segundos % 60;

  pintar(`
    <section class="resultado">
      <div class="resultado-emoji" aria-hidden="true">${mensaje[0]}</div>
      <h1>${mensaje[1]}</h1>
      <div class="nota ${r.nota >= 5 ? 'aprobada' : 'suspensa'}" style="--v:${r.nota * 10}">
        <span class="nota-num">${r.nota.toLocaleString('es-ES', { maximumFractionDigits: 2 })}</span><span class="nota-de">sobre 10</span>
      </div>
      <dl class="cifras">
        <div class="bien"><dt>Aciertos</dt><dd>${r.aciertos}</dd></div>
        <div class="mal"><dt>Fallos</dt><dd>${r.fallos}</dd></div>
        ${s.examen ? `<div><dt>En blanco</dt><dd>${r.blancos}</dd></div>` : ''}
        <div><dt>Tiempo</dt><dd>${min}:${String(seg).padStart(2, '0')}</dd></div>
      </dl>
      ${s.examen ? `<p class="formula">Nota = (${r.aciertos} − ${r.fallos} ÷ 3) ÷ ${r.total} × 10. Sin penalización habrías sacado un ${r.notaSinPenalizacion.toLocaleString('es-ES')}.</p>` : ''}
    </section>
    <div class="botones-columna">
      ${falladas.length ? '<button class="boton boton-grande" type="button" id="repasar">Repasar los fallos de este test</button>' : ''}
      <a class="boton boton-secundario boton-grande" href="#/inicio">Volver al inicio</a>
    </div>
    <details class="revision" ${s.examen ? 'open' : ''}>
      <summary>Ver todas las respuestas</summary>
      <ol>
        ${s.items.map(it => {
          const est = it.elegida === null ? 'blanco' : esCorrecta(it) ? 'bien' : 'mal';
          return `<li class="rev ${est}">
            <p class="rev-pregunta">${esc(it.p.pregunta)}</p>
            ${est !== 'bien' && it.elegida !== null ? `<p class="rev-tuya">✕ Tu respuesta: ${esc(it.p.opciones[it.elegida])}</p>` : ''}
            ${est === 'blanco' ? '<p class="rev-tuya">— En blanco</p>' : ''}
            <p class="rev-correcta">✓ ${esc(it.p.opciones[it.p.correcta])}</p>
            <p class="rev-explicacion">${esc(it.p.explicacion)}</p>
            ${botonOcultar(it.p)}
          </li>`;
        }).join('')}
      </ol>
    </details>
  `, { volver: 'inicio', titulo: 'Resultado' });

  eventosOcultar(s.items.map(it => it.p));
  if (r.nota >= 5) lanzarConfeti();
  $('#repasar')?.addEventListener('click', () => empezar(nuevaSesion(falladas.map(it => it.p), null, 'fallos', { libros: s.libros })));
}

// ---------------------------------------------------------------- 7. Estadísticas
async function pantallaEstadisticas() {
  cargando();
  const libros = await cargarCatalogo();
  const [progreso, dias, examenes] = await Promise.all([
    datos.progresoTemas(estado.perfil.id), datos.diasEstudio(estado.perfil.id), datos.examenes(estado.perfil.id),
  ]);
  // Preguntas ocultas: el id empieza por el prefijo del libro y el tema (p. ej. "ca-t01-017")
  const refsOcultas = [...estado.ocultas].map(id => {
    const [pre, tema] = id.split('-');
    const l = libros.find(x => x.prefijo === pre);
    return l ? { pregunta_id: id, libro: l.id, tema } : null;
  }).filter(Boolean);
  const ocultas = await preguntasPorIds(refsOcultas);
  const respondidas = progreso.reduce((s, p) => s + Number(p.respondidas), 0);
  const aciertos = progreso.reduce((s, p) => s + Number(p.aciertos), 0);
  const racha = calcularRacha(dias.map(d => d.dia));

  // Calendario de las últimas 12 semanas (lunes a domingo)
  const porDia = new Map(dias.map(d => [d.dia, Number(d.respondidas)]));
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid' });
  const hoy = new Date();
  const inicio = new Date(hoy);
  inicio.setDate(hoy.getDate() - ((hoy.getDay() + 6) % 7) - 7 * 11);
  const celdas = [];
  for (let d = new Date(inicio); d <= hoy; d.setDate(d.getDate() + 1)) {
    const k = fmt.format(d), n = porDia.get(k) || 0;
    const nivel = n === 0 ? 0 : n < 10 ? 1 : n < 25 ? 2 : n < 50 ? 3 : 4;
    celdas.push(`<span class="dia n${nivel}" title="${k}: ${n} preguntas"></span>`);
  }

  const flojos = progreso
    .filter(p => Number(p.respondidas) >= 5 && temaPorId(p.libro, p.tema))
    .map(p => ({ ...p, v: pct(p.aciertos, p.respondidas) }))
    .sort((a, b) => a.v - b.v).slice(0, 3);

  pintar(`
    <h1>Tus estadísticas</h1>
    <dl class="cifras cifras-grandes">
      <div><dt>Respondidas</dt><dd>${respondidas}</dd></div>
      <div><dt>Acierto</dt><dd>${pct(aciertos, respondidas)}%</dd></div>
      <div><dt>Racha</dt><dd>${racha} 🔥</dd></div>
      <div><dt>Días estudiados</dt><dd>${dias.length}</dd></div>
    </dl>

    <h2 class="seccion">Últimas 12 semanas</h2>
    <div class="tarjeta"><div class="calendario" role="img" aria-label="Calendario de actividad: ${dias.length} días con estudio">${celdas.join('')}</div>
      <p class="leyenda"><span>Menos</span><span class="dia n0"></span><span class="dia n1"></span><span class="dia n2"></span><span class="dia n3"></span><span class="dia n4"></span><span>Más</span></p></div>

    ${flojos.length ? `<h2 class="seccion">Temas para reforzar</h2>
      <ul class="lista-tarjetas" role="list">${flojos.map(f => {
        const l = libroPorId(f.libro), t = temaPorId(f.libro, f.tema);
        return `<li><a class="fila" href="#/libro/${l.id}" style="--c:${l.color}"><span aria-hidden="true">${l.icono}</span>
          <span class="fila-texto"><strong>Tema ${t.numero}: ${esc(t.titulo)}</strong><span>${esc(l.nombre)}</span></span>
          <span class="fila-valor mal">${f.v}%</span></a></li>`;
      }).join('')}</ul>` : ''}

    <h2 class="seccion">Por libro y tema</h2>
    ${libros.filter(disponible).map(l => `
      <section class="tarjeta stats-libro" style="--c:${l.color}">
        <h3><span aria-hidden="true">${l.icono}</span> ${esc(l.nombre)}</h3>
        <ul role="list">${l.temas.map(t => {
          const p = progreso.find(x => x.libro === l.id && x.tema === t.id);
          return `<li><div class="stats-fila"><span>Tema ${t.numero}. ${esc(t.titulo)}</span>
            <span class="stats-valor">${p ? `${pct(p.aciertos, p.respondidas)}%` : '—'}</span></div>
            ${barra(p ? pct(p.aciertos, p.respondidas) : 0, l.color)}
            <span class="stats-sub">${p ? `${p.dominadas}/${t.preguntas} dominadas · ${p.respondidas} respuestas` : 'Sin empezar'}</span></li>`;
        }).join('')}</ul>
      </section>`).join('') || '<p class="tarjeta">Aún no hay temas cargados.</p>'}

    ${examenes.length ? `<h2 class="seccion">Últimos tests</h2>
      <ul class="lista-tarjetas" role="list">${examenes.map(e => `
        <li class="fila"><span aria-hidden="true">${e.tipo === 'simulacro' ? '📝' : e.tipo === 'fallos' ? '🔁' : e.tipo === 'aleatorio' ? '🎲' : '📖'}</span>
          <span class="fila-texto"><strong>${NOMBRE_MODO[e.tipo] || e.tipo}</strong>
          <span>${new Date(e.fecha).toLocaleDateString('es-ES', { day: 'numeric', month: 'short' })} · ${e.aciertos}/${e.n_preguntas} aciertos</span></span>
          <span class="fila-valor ${Number(e.nota) >= 5 ? 'bien' : 'mal'}">${Number(e.nota).toLocaleString('es-ES', { maximumFractionDigits: 1 })}</span></li>`).join('')}</ul>` : ''}

    ${ocultas.length ? `<h2 class="seccion">Preguntas ocultas</h2>
      <details class="revision">
        <summary>${ocultas.length} ${ocultas.length === 1 ? 'pregunta oculta' : 'preguntas ocultas'} (no salen en los tests)</summary>
        <ol>${ocultas.map(p => `<li class="rev">
          <p class="rev-pregunta">${esc(p.pregunta)}</p>
          <p class="rev-explicacion">${esc(nombreCorto(libroPorId(p.libro)))} · Tema ${temaPorId(p.libro, p.tema)?.numero ?? ''}</p>
          ${botonOcultar(p)}
        </li>`).join('')}</ol>
      </details>` : ''}
  `, { volver: 'inicio', titulo: 'Estadísticas' });
  eventosOcultar(ocultas);
}

// ---------------------------------------------------------------- 8. Ranking
async function pantallaRanking() {
  cargando();
  const filas = (await datos.ranking())
    .map(f => ({ ...f, respondidas: Number(f.respondidas), aciertos: Number(f.aciertos), racha: Number(f.racha) }))
    .sort((a, b) => b.respondidas - a.respondidas || b.aciertos - a.aciertos);
  const medallas = ['🥇', '🥈', '🥉'];
  pintar(`
    <h1>Ranking</h1>
    <p class="lead">Preguntas respondidas en los últimos 30 días. ¡Ánimo a todas!</p>
    <ol class="ranking">
      ${filas.map((f, i) => `
        <li class="ranking-fila ${f.perfil_id === estado.perfil.id ? 'yo' : ''}" style="--c:${esc(f.color)}">
          <span class="ranking-pos">${f.respondidas && i < 3 ? `<span aria-label="Puesto ${i + 1}">${medallas[i]}</span>` : i + 1}</span>
          <span class="perfil-avatar mini" aria-hidden="true">${esc(f.avatar)}</span>
          <span class="fila-texto"><strong>${esc(f.nombre)}${f.perfil_id === estado.perfil.id ? ' (tú)' : ''}</strong>
            <span>${pct(f.aciertos, f.respondidas)}% acierto · ${f.racha} 🔥</span></span>
          <span class="fila-valor">${f.respondidas}</span>
        </li>`).join('')}
    </ol>
  `, { volver: 'inicio', titulo: 'Ranking' });
}

// ---------------------------------------------------------------- arranque
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
router();
