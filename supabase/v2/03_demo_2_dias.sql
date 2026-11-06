-- Demo automática de 2 días para las cuentas nuevas (antes 7).
-- Más adelante se podrá cambiar desde el panel de Administrador.
update dietetica.ajustes set dias_demo = 2, actualizado_en = now();

select limite_diario, dias_demo, saldo_bienvenida, registro_abierto from dietetica.ajustes;
