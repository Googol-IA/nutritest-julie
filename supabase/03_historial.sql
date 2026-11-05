-- =====================================================================
-- NutriTest de Julie · Historial de exámenes con repaso pregunta a pregunta
-- Ejecutar una vez en Supabase → SQL Editor (después de 01 y 02).
-- Se puede ejecutar varias veces sin romper nada.
-- =====================================================================

-- Detalle de cada test: lista de { "p": id de la pregunta, "e": opción elegida (o null si en blanco) }
alter table dietetica.examenes add column if not exists detalle jsonb;

notify pgrst, 'reload schema';
