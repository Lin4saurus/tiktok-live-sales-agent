-- 006 · Tiempo real del panel.
-- Cada cambio en las tablas que muestra el panel avanza un contador (secuencia). El panel
-- consulta ese número cada pocos segundos (GET panel/consulta?q=version) y solo recarga los
-- datos cuando cambió. Se usa una secuencia porque no bloquea: 50 clientes escribiendo a la
-- vez no se esperan entre sí (un cambio que se deshace solo provoca una recarga de más).
-- Idempotente. Requiere 002–004.

BEGIN;

CREATE SEQUENCE IF NOT EXISTS panel_cambios;

CREATE OR REPLACE FUNCTION trg_marcar_cambio() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM nextval('panel_cambios');
  RETURN NULL;
END $$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['capturas', 'pagos', 'pagos_capturas', 'cuentas_diarias', 'clientes',
                           'lives', 'mensajes', 'acciones_panel']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_cambio_panel', t);
    EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH STATEMENT EXECUTE FUNCTION trg_marcar_cambio()', t || '_cambio_panel', t);
  END LOOP;
END $$;

COMMIT;
