-- 003 · Funciones de negocio que usan los workflows de n8n.
-- Base: ventas. Idempotente. Requiere 002.
--
-- Convención: las funciones que llama el panel devuelven (codigo, respuesta, avisos):
--   codigo    -> código HTTP para responder al panel
--   respuesta -> JSON para el panel
--   avisos    -> mensajes de WhatsApp a enviar: [{whatsapp, texto}] o [{whatsapp, imagen_base64, caption}]
-- Los mensajes al cliente son siempre neutros: nunca acusan ni hablan de "rechazo" (D-15).

BEGIN;

ALTER TABLE acciones_panel
  ADD COLUMN IF NOT EXISTS cuenta_id text,
  ADD COLUMN IF NOT EXISTS whatsapp  text;

-- ─────────────────────────── Utilidades ───────────────────────────

-- Lo que el cliente debe pagar ahora: saldo de sus compras 'confirmada'.
CREATE OR REPLACE FUNCTION fn_total_a_pagar(p_whatsapp text) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(COALESCE(precio, 0) - fn_confirmado_captura(captura_id)), 0)
  FROM capturas WHERE whatsapp = p_whatsapp AND estado_captura = 'confirmada'
$$;

-- Aviso con el QR activo y el total a pagar como pie de foto.
CREATE OR REPLACE FUNCTION fn_aviso_qr(p_whatsapp text, p_total numeric) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'whatsapp', p_whatsapp,
    'imagen_base64', qr_base64,
    'caption', CASE WHEN p_total > 0 THEN 'Total a pagar: ' || trim_scale(p_total) || ' Bs. ' ELSE '' END
               || COALESCE(instrucciones, 'Escanea este QR para pagar. Cuando pagues, envíame el comprobante.'))
  FROM configuracion_pago WHERE config_id = 'default' AND activo = true
$$;

CREATE OR REPLACE FUNCTION fn_bs(p numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT trim_scale(round(COALESCE(p, 0), 2))::text || ' Bs'
$$;

-- ─────────────────────────── M7 · Registrar un comprobante ───────────────────────────
-- Concilia el comprobante con lo que el cliente debe (saldo de sus compras 'confirmada',
-- menos pagos parciales ya reportados y aún sin verificar).
--   igual  -> resultado 'coincide', pago 'reportado', compras 'pago_reportado'
--   menor  -> resultado 'parcial',  pago 'reportado', compras siguen 'confirmada'
--   mayor o cualquier bandera -> 'revision', pago 'requiere_revision'
-- Banderas: referencia_duplicada, monto_mayor, receptor_distinto, sin_compra_confirmada,
-- comprobante_ilegible. NADA se rechaza (D-15). Mismo message_id -> no se registra (pago_id NULL).
CREATE OR REPLACE FUNCTION fn_registrar_pago(
  p_whatsapp text, p_message_id text, p_monto numeric, p_confianza numeric, p_comprobante text,
  p_referencia text, p_receptor text, p_fecha text, p_banco text, p_enviado_por text)
RETURNS TABLE (resultado text, motivo_revision text, monto_esperado numeric, compras int,
               pago_id text, estado_pago text, faltante numeric, capturas_actualizadas int)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_ids       text[];
  v_compras   int;
  v_esperado  numeric;
  v_ref       text := NULLIF(regexp_replace(upper(COALESCE(p_referencia, '')), '[^A-Z0-9]', '', 'g'), '');
  v_receptor  text := trim(regexp_replace(lower(unaccent(COALESCE(p_receptor, ''))), '[^a-z]+', ' ', 'g'));
  v_titular   text;
  v_motivo    text;
  v_resultado text;
  v_estado    text;
  v_pago      text;
  v_upd       int := 0;
BEGIN
  IF p_message_id IS NOT NULL AND EXISTS (SELECT 1 FROM pagos WHERE message_id = p_message_id) THEN
    RETURN QUERY SELECT NULL::text, NULL::text, NULL::numeric, 0, NULL::text, NULL::text, NULL::numeric, 0;
    RETURN;
  END IF;

  PERFORM 1 FROM capturas WHERE whatsapp = p_whatsapp AND estado_captura = 'confirmada' FOR UPDATE;

  SELECT array_agg(captura_id ORDER BY fecha_recepcion), count(*),
         COALESCE(sum(COALESCE(precio, 0) - fn_confirmado_captura(captura_id)), 0)
  INTO v_ids, v_compras, v_esperado
  FROM capturas WHERE whatsapp = p_whatsapp AND estado_captura = 'confirmada';

  v_esperado := GREATEST(v_esperado - COALESCE((
    SELECT sum(p.monto_pagado) FROM pagos p
    WHERE p.estado_pago = 'reportado'
      AND EXISTS (SELECT 1 FROM pagos_capturas pc WHERE pc.pago_id = p.pago_id AND pc.captura_id = ANY (v_ids))), 0), 0);

  SELECT trim(regexp_replace(lower(unaccent(nombre_receptor)), '[^a-z]+', ' ', 'g')) INTO v_titular
  FROM configuracion_pago WHERE config_id = 'default' AND activo = true LIMIT 1;

  v_motivo := NULLIF(concat_ws(', ',
    CASE WHEN v_ref IS NOT NULL AND EXISTS (
           SELECT 1 FROM pagos p WHERE p.referencia_normalizada = v_ref
             AND p.message_id IS DISTINCT FROM p_message_id) THEN 'referencia_duplicada' END,
    CASE WHEN v_compras > 0 AND v_esperado > 0 AND p_monto IS NOT NULL
              AND p_monto - v_esperado >= 0.01 THEN 'monto_mayor' END,
    -- Flexible: basta con que el nombre o el primer apellido del titular aparezca en el
    -- destinatario, tolerando 1-2 letras de diferencia. Destinatario vacío: no se marca.
    CASE WHEN v_receptor <> '' AND v_titular IS NOT NULL AND NOT EXISTS (
           SELECT 1
           FROM unnest(string_to_array(v_receptor, ' ')) AS r(tok),
                unnest((string_to_array(v_titular, ' '))[1:2]) AS e(tok)
           WHERE length(r.tok) >= 3
             AND levenshtein(r.tok, e.tok) <= CASE WHEN length(e.tok) >= 6 THEN 2 ELSE 1 END)
         THEN 'receptor_distinto' END,
    CASE WHEN v_compras = 0 OR v_esperado <= 0 THEN 'sin_compra_confirmada' END,
    CASE WHEN p_monto IS NULL OR COALESCE(p_confianza, 0) < 0.6 THEN 'comprobante_ilegible' END
  ), '');

  v_resultado := CASE WHEN v_motivo IS NOT NULL THEN 'revision'
                      WHEN v_esperado - p_monto >= 0.01 THEN 'parcial'
                      ELSE 'coincide' END;
  v_estado := CASE WHEN v_motivo IS NULL THEN 'reportado' ELSE 'requiere_revision' END;

  INSERT INTO pagos (whatsapp, message_id, monto_pagado, monto_esperado, confianza, comprobante_base64,
                     capturas_ids, resultado, estado_pago, motivo_revision, referencia_pago,
                     referencia_normalizada, receptor_comprobante, fecha_comprobante, banco_app, enviado_por)
  VALUES (p_whatsapp, p_message_id, p_monto, v_esperado, p_confianza, p_comprobante, v_ids, v_resultado,
          v_estado, v_motivo, p_referencia, v_ref, p_receptor, p_fecha, p_banco, p_enviado_por)
  ON CONFLICT (message_id) DO NOTHING
  RETURNING pagos.pago_id INTO v_pago;

  IF v_pago IS NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::text, NULL::numeric, 0, NULL::text, NULL::text, NULL::numeric, 0;
    RETURN;
  END IF;

  IF v_ids IS NOT NULL THEN
    INSERT INTO pagos_capturas (pago_id, captura_id) SELECT v_pago, unnest(v_ids) ON CONFLICT DO NOTHING;
  END IF;

  IF v_resultado = 'coincide' THEN
    UPDATE capturas SET estado_captura = 'pago_reportado' WHERE captura_id = ANY (v_ids);
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  END IF;

  RETURN QUERY SELECT v_resultado, v_motivo, v_esperado, v_compras, v_pago, v_estado,
                      CASE WHEN v_resultado = 'parcial' THEN v_esperado - p_monto END, v_upd;
END $$;

-- ─────────────────────────── M8 · La vendedora confirma un pago ───────────────────────────
-- p_monto: lo que vio en su banco (por defecto, el monto del comprobante). Se reparte entre las
-- compras del pago en orden de llegada: las cubiertas pasan a 'pagada'; las demás vuelven a
-- 'confirmada' con su saldo pendiente (pago parcial). Lo que sobra queda como excedente.
CREATE OR REPLACE FUNCTION fn_confirmar_pago(p_pago text, p_monto numeric, p_nota text, p_notificar boolean)
RETURNS TABLE (codigo int, respuesta json, avisos json)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_p       pagos%ROWTYPE;
  v_resto   numeric;
  v_aplica  numeric;
  v_pagadas text[] := '{}';
  v_saldo   numeric;
  c         record;
BEGIN
  SELECT * INTO v_p FROM pagos WHERE pago_id = p_pago FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 404, json_build_object('ok', false, 'error', 'pago_no_encontrado'), '[]'::json; RETURN;
  END IF;
  IF v_p.estado_pago = 'verificado' THEN
    RETURN QUERY SELECT 409, json_build_object('ok', false, 'error', 'pago_ya_verificado'), '[]'::json; RETURN;
  END IF;
  v_resto := COALESCE(p_monto, v_p.monto_pagado);
  IF v_resto IS NULL OR v_resto <= 0 THEN
    RETURN QUERY SELECT 400, json_build_object('ok', false, 'error', 'monto_requerido'), '[]'::json; RETURN;
  END IF;

  -- Un comprobante que llegó sin compras confirmadas se asocia ahora a las compras abiertas del cliente.
  IF NOT EXISTS (SELECT 1 FROM pagos_capturas WHERE pago_id = p_pago) THEN
    INSERT INTO pagos_capturas (pago_id, captura_id)
    SELECT p_pago, captura_id FROM capturas
    WHERE whatsapp = v_p.whatsapp AND estado_captura IN ('confirmada', 'pago_reportado', 'requiere_revision');
  END IF;

  FOR c IN
    SELECT cap.captura_id, COALESCE(cap.precio, 0) AS precio, fn_confirmado_captura(cap.captura_id) AS ya
    FROM pagos_capturas pc JOIN capturas cap ON cap.captura_id = pc.captura_id
    WHERE pc.pago_id = p_pago AND cap.estado_captura NOT IN ('cancelada', 'pagada')
    ORDER BY cap.fecha_recepcion
  LOOP
    v_aplica := LEAST(v_resto, GREATEST(c.precio - c.ya, 0));
    UPDATE pagos_capturas SET monto_aplicado = v_aplica WHERE pago_id = p_pago AND captura_id = c.captura_id;
    v_resto := v_resto - v_aplica;
    IF c.ya + v_aplica >= c.precio THEN v_pagadas := v_pagadas || c.captura_id; END IF;
  END LOOP;

  UPDATE pagos
  SET estado_pago = 'verificado', monto_confirmado = COALESCE(p_monto, v_p.monto_pagado),
      excedente = NULLIF(v_resto, 0), fecha_verificacion = now(),
      notas = COALESCE(NULLIF(p_nota, ''), notas)
  WHERE pago_id = p_pago;

  UPDATE capturas SET estado_captura = 'pagada' WHERE captura_id = ANY (v_pagadas);
  UPDATE capturas SET estado_captura = 'confirmada'
  WHERE captura_id IN (SELECT captura_id FROM pagos_capturas WHERE pago_id = p_pago)
    AND NOT (captura_id = ANY (v_pagadas))
    AND estado_captura IN ('pago_reportado', 'requiere_revision');

  v_saldo := fn_total_a_pagar(v_p.whatsapp);

  INSERT INTO acciones_panel (accion, pago_id, whatsapp, estado_anterior, estado_nuevo, detalle)
  VALUES ('confirmar_pago', p_pago, v_p.whatsapp, v_p.estado_pago, 'verificado',
          jsonb_build_object('nota', NULLIF(p_nota, ''), 'monto_confirmado', COALESCE(p_monto, v_p.monto_pagado),
                             'compras_pagadas', to_jsonb(v_pagadas), 'excedente', NULLIF(v_resto, 0),
                             'saldo_pendiente', v_saldo));

  RETURN QUERY SELECT 200,
    json_build_object('ok', true, 'pago_id', p_pago, 'monto_confirmado', COALESCE(p_monto, v_p.monto_pagado),
                      'compras_pagadas', to_json(v_pagadas), 'excedente', NULLIF(v_resto, 0),
                      'saldo_pendiente', v_saldo),
    CASE WHEN COALESCE(p_notificar, true) THEN json_build_array(json_build_object(
      'whatsapp', v_p.whatsapp,
      'texto', '¡Hola! La vendedora verificó tu pago de ' || fn_bs(COALESCE(p_monto, v_p.monto_pagado)) || '. '
               || CASE WHEN v_saldo > 0
                       THEN 'Te falta pagar ' || fn_bs(v_saldo) || '; puedes usar el mismo QR. ¡Gracias!'
                       ELSE 'Tu compra quedó registrada como pagada. ¡Gracias por tu compra!' END))
    ELSE '[]'::json END;
END $$;

-- ─────────────────────────── M9 · Vencimiento de cuentas ───────────────────────────
-- Cuentas con el plazo vencido (fin del día siguiente al live) y sin nada pagado se cancelan,
-- salvo que tengan un comprobante pendiente o algo en revisión, o que la vendedora esté
-- atendiendo al cliente. Las cuentas con pago parcial NO se cancelan: se avisan a la vendedora.
CREATE OR REPLACE FUNCTION fn_vencer_cuentas()
RETURNS TABLE (codigo int, respuesta json, avisos json)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_vencidas  json;
  v_parciales json;
  v_avisos    json := '[]'::json;
  v_vendedora text;
  r           record;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _vencer (cuenta_id text, whatsapp text, live_id text, fecha date, subtotal numeric) ON COMMIT DROP;
  TRUNCATE _vencer;

  INSERT INTO _vencer
  SELECT cd.cuenta_id, cd.cliente_id, cd.live_id, cd.fecha_operativa, cd.subtotal
  FROM cuentas_diarias cd
  JOIN clientes cl ON cl.cliente_id = cd.cliente_id
  WHERE now() > cd.fecha_limite_pago
    AND cd.estado = 'abierta' AND cd.subtotal > 0
    AND cl.control = 'agente'
    AND NOT EXISTS (SELECT 1 FROM capturas c WHERE c.cuenta_id = cd.cuenta_id
                      AND c.estado_captura IN ('requiere_revision', 'pago_reportado'))
    AND NOT EXISTS (SELECT 1 FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                    JOIN pagos p ON p.pago_id = pc.pago_id
                    WHERE c.cuenta_id = cd.cuenta_id AND p.estado_pago IN ('reportado', 'requiere_revision'))
  FOR UPDATE OF cd;

  UPDATE cuentas_diarias SET vencida_en = now() WHERE cuenta_id IN (SELECT cuenta_id FROM _vencer);

  INSERT INTO acciones_panel (accion, captura_id, cuenta_id, whatsapp, estado_anterior, estado_nuevo, detalle)
  SELECT 'vencimiento', c.captura_id, c.cuenta_id, c.whatsapp, c.estado_captura, 'cancelada',
         jsonb_build_object('motivo', 'plazo de pago vencido')
  FROM capturas c WHERE c.cuenta_id IN (SELECT cuenta_id FROM _vencer)
    AND c.estado_captura NOT IN ('pagada', 'cancelada');

  UPDATE capturas SET estado_captura = 'cancelada'
  WHERE cuenta_id IN (SELECT cuenta_id FROM _vencer) AND estado_captura NOT IN ('pagada', 'cancelada');

  SELECT COALESCE(json_agg(json_build_object('cuenta_id', cuenta_id, 'whatsapp', whatsapp, 'subtotal', subtotal)), '[]'::json)
  INTO v_vencidas FROM _vencer;

  -- Vencidas con pago parcial: no se cancelan; se marcan una sola vez (vencida_en) para avisar
  -- a la vendedora sin repetir el aviso en cada ejecución.
  WITH marcadas AS (
    UPDATE cuentas_diarias SET vencida_en = now()
    WHERE now() > fecha_limite_pago AND estado = 'parcial' AND saldo > 0 AND vencida_en IS NULL
    RETURNING cuenta_id, cliente_id, saldo
  )
  SELECT COALESCE(json_agg(json_build_object('cuenta_id', cuenta_id, 'whatsapp', cliente_id, 'saldo', saldo)), '[]'::json)
  INTO v_parciales FROM marcadas;

  SELECT COALESCE(json_agg(json_build_object(
           'whatsapp', whatsapp,
           'texto', 'Hola. El plazo para pagar tu compra del live del ' || to_char(fecha, 'DD/MM') || ' ('
                    || fn_bs(subtotal) || ') terminó y no recibimos el pago, así que la compra quedó cancelada. '
                    || 'Si ya pagaste o crees que es un error, respóndeme y lo reviso con la vendedora.')), '[]'::json)
  INTO v_avisos FROM _vencer;

  SELECT NULLIF(regexp_replace(COALESCE(whatsapp_vendedora, ''), '\D', '', 'g'), '') INTO v_vendedora
  FROM configuracion_pago WHERE config_id = 'default';

  IF v_vendedora IS NOT NULL AND (json_array_length(v_vencidas) > 0 OR json_array_length(v_parciales) > 0) THEN
    v_avisos := (v_avisos::jsonb || jsonb_build_array(jsonb_build_object(
      'whatsapp', v_vendedora,
      'texto', 'Resumen de vencimientos: ' || json_array_length(v_vencidas) || ' cuenta(s) cancelada(s) por falta de pago'
               || CASE WHEN json_array_length(v_parciales) > 0
                       THEN ' y ' || json_array_length(v_parciales) || ' cuenta(s) vencida(s) con pago parcial para revisar'
                       ELSE '' END
               || '. Detalle en el panel.')))::json;
  END IF;

  RETURN QUERY SELECT 200,
    json_build_object('ok', true, 'canceladas', v_vencidas, 'parciales_vencidas', v_parciales),
    v_avisos;
END $$;

COMMIT;
