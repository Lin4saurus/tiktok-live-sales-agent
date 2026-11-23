-- 002 · Lives, cuentas diarias, nicknames, pagos parciales, mensajes y control agente/humano.
-- Base: ventas. Idempotente (se puede volver a ejecutar). Ver DATA_MODEL.md.
--
-- La lógica que debe cumplirse SIEMPRE, venga el cambio de WhatsApp o del panel, vive aquí
-- en funciones y triggers:
--   * al insertar una captura se le asigna live, cuenta diaria y fecha operativa;
--   * cada cambio en capturas / pagos recalcula los totales y el estado de la cuenta;
--   * cuando algo pasa a revisión, el control del cliente pasa a 'humano' (el bot se silencia).
--
-- Zona horaria de operación: America/La_Paz. Las columnas timestamp guardan UTC.

BEGIN;

-- ─────────────────────────── Tablas nuevas ───────────────────────────

CREATE TABLE IF NOT EXISTS lives (
  live_id         text PRIMARY KEY,                       -- LIVE-AAAAMMDD-NNN
  fecha_operativa date NOT NULL,
  titulo          text,
  estado          text NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'cerrado')),
  origen          text NOT NULL DEFAULT 'manual' CHECK (origen IN ('manual', 'respaldo')),
  inicio          timestamp NOT NULL DEFAULT now(),
  cierre          timestamp
);
-- Solo puede haber un live activo a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS lives_un_solo_activo ON lives (estado) WHERE estado = 'activo';

CREATE TABLE IF NOT EXISTS cuentas_diarias (
  cuenta_id         text PRIMARY KEY,                     -- CD-AAAAMMDD-NNN-NNN (live + correlativo)
  cliente_id        text NOT NULL REFERENCES clientes (cliente_id),
  live_id           text NOT NULL REFERENCES lives (live_id),
  fecha_operativa   date NOT NULL,
  fecha_limite_pago timestamp NOT NULL,                   -- fin del día siguiente al live (en UTC)
  subtotal          numeric NOT NULL DEFAULT 0,           -- compras no canceladas
  monto_confirmado  numeric NOT NULL DEFAULT 0,           -- verificado por la vendedora
  saldo             numeric GENERATED ALWAYS AS (subtotal - monto_confirmado) STORED,
  estado            text NOT NULL DEFAULT 'abierta'
                    CHECK (estado IN ('abierta', 'parcial', 'pagada', 'cancelada', 'vencida')),
  qr_enviado_en     timestamp,                            -- D-07: el QR se envía una vez por cuenta
  vencida_en        timestamp,
  fecha_creacion    timestamp NOT NULL DEFAULT now(),
  UNIQUE (cliente_id, live_id)                            -- D-05
);
CREATE INDEX IF NOT EXISTS cuentas_diarias_live_idx ON cuentas_diarias (live_id);

-- D-02: nicknames de TikTok usados por cada cliente (nunca se fusionan automáticamente).
CREATE TABLE IF NOT EXISTS cuentas_tiktok (
  cliente_id  text NOT NULL REFERENCES clientes (cliente_id),
  nickname    text NOT NULL,
  primera_vez timestamp NOT NULL DEFAULT now(),
  ultima_vez  timestamp NOT NULL DEFAULT now(),
  capturas    int NOT NULL DEFAULT 1,
  PRIMARY KEY (cliente_id, nickname)
);

-- Qué compras cubre cada pago y cuánto se aplicó a cada una (se fija al confirmar el pago).
CREATE TABLE IF NOT EXISTS pagos_capturas (
  pago_id        text NOT NULL REFERENCES pagos (pago_id) ON DELETE CASCADE,
  captura_id     text NOT NULL REFERENCES capturas (captura_id) ON DELETE CASCADE,
  monto_aplicado numeric,
  PRIMARY KEY (pago_id, captura_id)
);
CREATE INDEX IF NOT EXISTS pagos_capturas_captura_idx ON pagos_capturas (captura_id);

-- Registro de mensajes entrantes y salientes (sin archivos adjuntos).
CREATE TABLE IF NOT EXISTS mensajes (
  mensaje_id bigserial PRIMARY KEY,
  message_id text,
  whatsapp   text NOT NULL,
  direccion  text NOT NULL CHECK (direccion IN ('entrante', 'saliente')),
  tipo       text,
  texto      text,
  fecha      timestamp NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS mensajes_entrante_uk ON mensajes (message_id) WHERE direccion = 'entrante';
CREATE INDEX IF NOT EXISTS mensajes_whatsapp_idx ON mensajes (whatsapp, fecha DESC);

-- ─────────────────────────── Columnas nuevas ───────────────────────────

ALTER TABLE capturas
  ADD COLUMN IF NOT EXISTS live_id         text REFERENCES lives (live_id),
  ADD COLUMN IF NOT EXISTS cuenta_id       text REFERENCES cuentas_diarias (cuenta_id),
  ADD COLUMN IF NOT EXISTS fecha_operativa date,
  ADD COLUMN IF NOT EXISTS imagen_base64   text;
CREATE INDEX IF NOT EXISTS capturas_cuenta_idx ON capturas (cuenta_id);

-- Handoff agente↔vendedora: con 'humano' el bot no responde a ese cliente.
ALTER TABLE clientes
  ADD COLUMN IF NOT EXISTS control       text NOT NULL DEFAULT 'agente' CHECK (control IN ('agente', 'humano')),
  ADD COLUMN IF NOT EXISTS control_desde timestamp;

ALTER TABLE pagos
  ADD COLUMN IF NOT EXISTS monto_confirmado numeric,      -- lo que la vendedora vio en su banco
  ADD COLUMN IF NOT EXISTS excedente        numeric;      -- pagado de más (queda a favor del cliente)

-- Número de la vendedora para avisos del sistema (vencimientos).
ALTER TABLE configuracion_pago ADD COLUMN IF NOT EXISTS whatsapp_vendedora text;

-- ─────────────────────────── Funciones de fechas e IDs ───────────────────────────

CREATE OR REPLACE FUNCTION hoy_operativo() RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'America/La_Paz')::date
$$;

-- Fin del día siguiente al live, hora de Bolivia, expresado en UTC (como el resto de columnas).
CREATE OR REPLACE FUNCTION fn_limite_pago(p_fecha date) RETURNS timestamp LANGUAGE sql IMMUTABLE AS $$
  SELECT ((p_fecha + 2)::timestamp AT TIME ZONE 'America/La_Paz') AT TIME ZONE 'UTC'
$$;

CREATE OR REPLACE FUNCTION fn_nuevo_live_id(p_fecha date) RETURNS text LANGUAGE sql AS $$
  SELECT 'LIVE-' || to_char(p_fecha, 'YYYYMMDD') || '-'
         || lpad((COALESCE(max(substring(live_id FROM 15)::int), 0) + 1)::text, 3, '0')
  FROM lives WHERE fecha_operativa = p_fecha
$$;

-- Live al que pertenece una captura que llega ahora:
--   1) el live activo;
--   2) respaldo: el último live de hoy, o uno cerrado hace menos de 12 h
--      (las capturas suelen llegar al terminar el live, incluso pasada la medianoche);
--   3) si no hubo live, se crea uno de respaldo para hoy (cerrado, origen 'respaldo').
CREATE OR REPLACE FUNCTION fn_live_para_captura() RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_live text;
  v_hoy  date := hoy_operativo();
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('lives'));

  SELECT live_id INTO v_live FROM lives WHERE estado = 'activo' LIMIT 1;
  IF v_live IS NOT NULL THEN RETURN v_live; END IF;

  SELECT live_id INTO v_live FROM lives
  WHERE fecha_operativa = v_hoy OR cierre > now() - interval '12 hours'
  ORDER BY inicio DESC LIMIT 1;
  IF v_live IS NOT NULL THEN RETURN v_live; END IF;

  v_live := fn_nuevo_live_id(v_hoy);
  INSERT INTO lives (live_id, fecha_operativa, titulo, estado, origen, inicio, cierre)
  VALUES (v_live, v_hoy, 'Live de respaldo (no se abrió en el panel)', 'cerrado', 'respaldo', now(), now());
  RETURN v_live;
END $$;

-- Cuenta diaria del cliente en ese live; la crea si no existe (D-05).
CREATE OR REPLACE FUNCTION fn_cuenta_para(p_cliente text, p_live text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_cuenta text;
  v_fecha  date;
  v_n      int;
BEGIN
  SELECT cuenta_id INTO v_cuenta FROM cuentas_diarias WHERE cliente_id = p_cliente AND live_id = p_live;
  IF v_cuenta IS NOT NULL THEN RETURN v_cuenta; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('cuenta:' || p_live));
  SELECT cuenta_id INTO v_cuenta FROM cuentas_diarias WHERE cliente_id = p_cliente AND live_id = p_live;
  IF v_cuenta IS NOT NULL THEN RETURN v_cuenta; END IF;

  SELECT fecha_operativa INTO v_fecha FROM lives WHERE live_id = p_live;
  SELECT count(*) + 1 INTO v_n FROM cuentas_diarias WHERE live_id = p_live;
  v_cuenta := 'CD-' || substring(p_live FROM 6) || '-' || lpad(v_n::text, 3, '0');

  INSERT INTO cuentas_diarias (cuenta_id, cliente_id, live_id, fecha_operativa, fecha_limite_pago)
  VALUES (v_cuenta, p_cliente, p_live, v_fecha, fn_limite_pago(v_fecha));
  RETURN v_cuenta;
END $$;

-- ─────────────────────────── Totales de la cuenta ───────────────────────────

-- Cuánto de una captura ya está confirmado: su precio si está 'pagada'; si no, lo aplicado
-- por pagos verificados (pagos parciales), sin pasar del precio.
CREATE OR REPLACE FUNCTION fn_confirmado_captura(p_captura text) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN c.estado_captura = 'pagada' THEN COALESCE(c.precio, 0)
              ELSE LEAST(COALESCE(c.precio, 0), COALESCE((
                     SELECT sum(pc.monto_aplicado) FROM pagos_capturas pc
                     JOIN pagos p ON p.pago_id = pc.pago_id
                     WHERE pc.captura_id = c.captura_id AND p.estado_pago = 'verificado'), 0))
         END
  FROM capturas c WHERE c.captura_id = p_captura
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_cuenta(p_cuenta text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  r record;
BEGIN
  SELECT count(*) AS n,
         count(*) FILTER (WHERE estado_captura <> 'cancelada') AS activas,
         COALESCE(sum(precio) FILTER (WHERE estado_captura <> 'cancelada'), 0) AS subtotal,
         COALESCE(sum(fn_confirmado_captura(captura_id)) FILTER (WHERE estado_captura <> 'cancelada'), 0) AS confirmado
  INTO r
  FROM capturas WHERE cuenta_id = p_cuenta;

  UPDATE cuentas_diarias
  SET subtotal = r.subtotal,
      monto_confirmado = r.confirmado,
      estado = CASE
                 WHEN r.n = 0 THEN 'abierta'
                 WHEN r.activas = 0 THEN CASE WHEN vencida_en IS NOT NULL THEN 'vencida' ELSE 'cancelada' END
                 WHEN r.confirmado >= r.subtotal THEN 'pagada'
                 WHEN r.confirmado > 0 THEN 'parcial'
                 ELSE 'abierta'
               END
  WHERE cuenta_id = p_cuenta;
END $$;

-- ─────────────────────────── Triggers ───────────────────────────

-- Antes de insertar una captura: cliente, live, cuenta y fecha operativa.
CREATE OR REPLACE FUNCTION trg_capturas_antes_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO clientes (cliente_id, whatsapp) VALUES (NEW.whatsapp, NEW.whatsapp) ON CONFLICT DO NOTHING;
  IF NEW.live_id IS NULL THEN NEW.live_id := fn_live_para_captura(); END IF;
  IF NEW.cuenta_id IS NULL THEN NEW.cuenta_id := fn_cuenta_para(NEW.whatsapp, NEW.live_id); END IF;
  SELECT fecha_operativa INTO NEW.fecha_operativa FROM lives WHERE live_id = NEW.live_id;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS capturas_antes_insert ON capturas;
CREATE TRIGGER capturas_antes_insert BEFORE INSERT ON capturas
  FOR EACH ROW EXECUTE FUNCTION trg_capturas_antes_insert();

-- Después de cada cambio en capturas: totales de la cuenta, nicknames y control humano.
CREATE OR REPLACE FUNCTION trg_capturas_despues() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.cuenta_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR OLD.cuenta_id IS DISTINCT FROM NEW.cuenta_id) THEN
    PERFORM fn_recalcular_cuenta(OLD.cuenta_id);
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  IF NEW.cuenta_id IS NOT NULL THEN PERFORM fn_recalcular_cuenta(NEW.cuenta_id); END IF;

  IF NEW.nickname IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.nickname IS DISTINCT FROM OLD.nickname) THEN
    INSERT INTO cuentas_tiktok (cliente_id, nickname) VALUES (NEW.whatsapp, NEW.nickname)
    ON CONFLICT (cliente_id, nickname)
    DO UPDATE SET ultima_vez = now(), capturas = cuentas_tiktok.capturas + 1;
  END IF;

  -- Algo pasó a revisión: la vendedora toma la conversación y el bot se silencia.
  IF NEW.estado_captura = 'requiere_revision'
     AND (TG_OP = 'INSERT' OR OLD.estado_captura IS DISTINCT FROM 'requiere_revision') THEN
    UPDATE clientes SET control = 'humano', control_desde = now()
    WHERE whatsapp = NEW.whatsapp AND control = 'agente';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS capturas_despues ON capturas;
CREATE TRIGGER capturas_despues AFTER INSERT OR UPDATE OR DELETE ON capturas
  FOR EACH ROW EXECUTE FUNCTION trg_capturas_despues();

-- Pagos: un comprobante en revisión pasa el control a la vendedora; al verificarlo
-- se recalculan las cuentas de sus compras.
CREATE OR REPLACE FUNCTION trg_pagos_despues() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cuenta text;
BEGIN
  IF NEW.estado_pago = 'requiere_revision'
     AND (TG_OP = 'INSERT' OR OLD.estado_pago IS DISTINCT FROM 'requiere_revision') THEN
    UPDATE clientes SET control = 'humano', control_desde = now()
    WHERE whatsapp = NEW.whatsapp AND control = 'agente';
  END IF;
  IF TG_OP = 'UPDATE' AND (OLD.estado_pago IS DISTINCT FROM NEW.estado_pago
                           OR OLD.monto_confirmado IS DISTINCT FROM NEW.monto_confirmado) THEN
    FOR v_cuenta IN
      SELECT DISTINCT c.cuenta_id FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
      WHERE pc.pago_id = NEW.pago_id AND c.cuenta_id IS NOT NULL
    LOOP
      PERFORM fn_recalcular_cuenta(v_cuenta);
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pagos_despues ON pagos;
CREATE TRIGGER pagos_despues AFTER INSERT OR UPDATE ON pagos
  FOR EACH ROW EXECUTE FUNCTION trg_pagos_despues();

CREATE OR REPLACE FUNCTION trg_pagos_capturas_despues() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cuenta text;
BEGIN
  SELECT cuenta_id INTO v_cuenta FROM capturas
  WHERE captura_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.captura_id ELSE NEW.captura_id END;
  IF v_cuenta IS NOT NULL THEN PERFORM fn_recalcular_cuenta(v_cuenta); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS pagos_capturas_despues ON pagos_capturas;
CREATE TRIGGER pagos_capturas_despues AFTER INSERT OR UPDATE OR DELETE ON pagos_capturas
  FOR EACH ROW EXECUTE FUNCTION trg_pagos_capturas_despues();

-- ─────────────────────────── Datos existentes ───────────────────────────

-- Capturas anteriores a esta migración: un live de respaldo por día operativo y su cuenta.
DO $$
DECLARE
  r record;
  v_live text;
BEGIN
  FOR r IN
    SELECT DISTINCT (fecha_recepcion AT TIME ZONE 'UTC' AT TIME ZONE 'America/La_Paz')::date AS dia
    FROM capturas WHERE live_id IS NULL ORDER BY 1
  LOOP
    SELECT live_id INTO v_live FROM lives WHERE fecha_operativa = r.dia ORDER BY inicio LIMIT 1;
    IF v_live IS NULL THEN
      v_live := fn_nuevo_live_id(r.dia);
      INSERT INTO lives (live_id, fecha_operativa, titulo, estado, origen, inicio, cierre)
      VALUES (v_live, r.dia, 'Live de respaldo (datos anteriores)', 'cerrado', 'respaldo', now(), now());
    END IF;
    UPDATE capturas c
    SET live_id = v_live, fecha_operativa = r.dia, cuenta_id = fn_cuenta_para(c.whatsapp, v_live)
    WHERE c.live_id IS NULL
      AND (c.fecha_recepcion AT TIME ZONE 'UTC' AT TIME ZONE 'America/La_Paz')::date = r.dia;
  END LOOP;
END $$;

INSERT INTO pagos_capturas (pago_id, captura_id, monto_aplicado)
SELECT p.pago_id, x.captura_id,
       CASE WHEN p.estado_pago = 'verificado' THEN c.precio END
FROM pagos p
CROSS JOIN LATERAL unnest(p.capturas_ids) AS x(captura_id)
JOIN capturas c ON c.captura_id = x.captura_id
ON CONFLICT DO NOTHING;

INSERT INTO cuentas_tiktok (cliente_id, nickname, primera_vez, ultima_vez, capturas)
SELECT whatsapp, nickname, min(fecha_recepcion), max(fecha_recepcion), count(*)
FROM capturas WHERE nickname IS NOT NULL
GROUP BY whatsapp, nickname
ON CONFLICT (cliente_id, nickname) DO NOTHING;

SELECT fn_recalcular_cuenta(cuenta_id) FROM cuentas_diarias;

COMMIT;
