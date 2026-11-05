// Configuración de NutriTest de Julie
// Si SUPABASE_URL está vacío, la web funciona en "modo local": guarda el progreso
// solo en este navegador (útil para probar). Con Supabase, se comparte entre dispositivos.

export const SUPABASE_URL = '';      // p. ej. 'https://xxxxxxxx.supabase.co'
export const SUPABASE_KEY = '';      // clave anon / publishable (es pública, no pasa nada)
export const ESQUEMA = 'dietetica';

// Simulacro: cuánto resta cada fallo. 1/3 = "3 fallos restan 1 acierto".
export const PENALIZACION = 1 / 3;

// Simulacro con temporizador: minutos por pregunta
export const MINUTOS_POR_PREGUNTA = 1;
