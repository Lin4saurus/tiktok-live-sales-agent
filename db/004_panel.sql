-- 004 · Consultas y acciones del panel de la vendedora (workflow "Panel - API").
-- Base: ventas. Idempotente. Requiere 002 y 003.
--   GET  /webhook/panel/consulta?q=<consulta>&...  -> fn_panel_consulta(q, parametros)
--   POST /webhook/panel/accion  {accion, ...}       -> fn_panel_accion(body)

BEGIN;

-- Columna del tablero para una cuenta:
--   cerradas  -> cancelada o vencida sin pagos
--   pagadas   -> pagada
--   revision  -> la vendedora atiende al cliente, hay algo en revisión o un comprobante sin verificar
--   pendientes-> el resto (abierta o parcial)
CREATE OR REPLACE FUNCTION fn_columna_cuenta(p_cuenta text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN cd.estado IN ('cancelada', 'vencida') THEN 'cerradas'
    WHEN cd.estado = 'pagada' THEN 'pagadas'
    WHEN cl.control = 'humano'
      OR EXISTS (SELECT 1 FROM capturas c WHERE c.cuenta_id = cd.cuenta_id
                   AND c.estado_captura IN ('requiere_revision', 'pago_reportado'))
      OR EXISTS (SELECT 1 FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                 JOIN pagos p ON p.pago_id = pc.pago_id
                 WHERE c.cuenta_id = cd.cuenta_id AND p.estado_pago IN ('reportado', 'requiere_revision'))
      THEN 'revision'
    ELSE 'pendientes'
  END
  FROM cuentas_diarias cd JOIN clientes cl ON cl.cliente_id = cd.cliente_id
  WHERE cd.cuenta_id = p_cuenta
$$;

CREATE OR REPLACE FUNCTION fn_indicadores_live(p_live text) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'live_id', l.live_id, 'titulo', l.titulo, 'fecha_operativa', l.fecha_operativa, 'estado', l.estado,
    'origen', l.origen, 'inicio', l.inicio, 'cierre', l.cierre,
    'clientes', (SELECT count(*) FROM cuentas_diarias cd WHERE cd.live_id = l.live_id AND cd.subtotal > 0),
    'compras', (SELECT count(*) FROM capturas c WHERE c.live_id = l.live_id AND c.estado_captura <> 'cancelada'),
    'vendido', (SELECT COALESCE(sum(subtotal), 0) FROM cuentas_diarias cd WHERE cd.live_id = l.live_id),
    'cobrado', (SELECT COALESCE(sum(monto_confirmado), 0) FROM cuentas_diarias cd WHERE cd.live_id = l.live_id),
    'pendiente', (SELECT COALESCE(sum(saldo), 0) FROM cuentas_diarias cd
                  WHERE cd.live_id = l.live_id AND cd.estado IN ('abierta', 'parcial')),
    'cuentas_pagadas', (SELECT count(*) FROM cuentas_diarias cd WHERE cd.live_id = l.live_id AND cd.estado = 'pagada'),
    'cuentas_en_revision', (SELECT count(*) FROM cuentas_diarias cd
                            WHERE cd.live_id = l.live_id AND fn_columna_cuenta(cd.cuenta_id) = 'revision'))
  FROM lives l WHERE l.live_id = p_live
$$;

-- ─────────────────────────── Consultas ───────────────────────────
CREATE OR REPLACE FUNCTION fn_panel_consulta(p_q text, p jsonb)
RETURNS TABLE (codigo int, respuesta json)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
  v_live text;
  v_id   text := NULLIF(p ->> 'id', '');
BEGIN
  IF p_q = 'lives' THEN
    RETURN QUERY SELECT 200, json_build_object('ok', true,
      'activo', (SELECT live_id FROM lives WHERE estado = 'activo'),
      'lives', COALESCE((SELECT json_agg(fn_indicadores_live(live_id) ORDER BY inicio DESC)
                         FROM (SELECT live_id, inicio FROM lives ORDER BY inicio DESC LIMIT 30) x), '[]'::json));
    RETURN;
  END IF;

  IF p_q = 'cuentas' OR p_q = 'reporte' THEN
    v_live := COALESCE(NULLIF(p ->> 'live_id', ''),
                       (SELECT live_id FROM lives WHERE estado = 'activo'),
                       (SELECT live_id FROM lives ORDER BY inicio DESC LIMIT 1));
    IF v_live IS NULL OR NOT EXISTS (SELECT 1 FROM lives WHERE live_id = v_live) THEN
      RETURN QUERY SELECT CASE WHEN v_live IS NULL THEN 200 ELSE 404 END,
        json_build_object('ok', v_live IS NULL, 'live', NULL, 'cuentas', '[]'::json,
                          'error', CASE WHEN v_live IS NOT NULL THEN 'live_no_encontrado' END);
      RETURN;
    END IF;
    RETURN QUERY SELECT 200, json_build_object('ok', true,
      'live', fn_indicadores_live(v_live),
      'cuentas', COALESCE((
        SELECT json_agg(json_build_object(
          'cuenta_id', cd.cuenta_id, 'whatsapp', cd.cliente_id,
          'cliente', COALESCE(cl.nombre_real, cl.push_name),
          'nicknames', (SELECT string_agg(DISTINCT c.nickname, ', ') FROM capturas c WHERE c.cuenta_id = cd.cuenta_id),
          'compras', (SELECT count(*) FROM capturas c WHERE c.cuenta_id = cd.cuenta_id AND c.estado_captura <> 'cancelada'),
          'subtotal', cd.subtotal, 'monto_confirmado', cd.monto_confirmado, 'saldo', cd.saldo,
          'estado', cd.estado, 'columna', fn_columna_cuenta(cd.cuenta_id), 'control', cl.control,
          'qr_enviado_en', cd.qr_enviado_en, 'fecha_limite_pago', cd.fecha_limite_pago,
          'motivos', (SELECT string_agg(DISTINCT p2.motivo_revision, ', ')
                      FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                      JOIN pagos p2 ON p2.pago_id = pc.pago_id
                      WHERE c.cuenta_id = cd.cuenta_id AND p2.estado_pago = 'requiere_revision'),
          'en_revision', (SELECT count(*) FROM capturas c WHERE c.cuenta_id = cd.cuenta_id AND c.estado_captura = 'requiere_revision'),
          'pago_por_verificar', EXISTS (SELECT 1 FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                      JOIN pagos p2 ON p2.pago_id = pc.pago_id
                      WHERE c.cuenta_id = cd.cuenta_id AND p2.estado_pago IN ('reportado', 'requiere_revision')),
          'ultima_actividad', (SELECT max(c.fecha_recepcion) FROM capturas c WHERE c.cuenta_id = cd.cuenta_id))
          ORDER BY cd.fecha_creacion)
        FROM cuentas_diarias cd JOIN clientes cl ON cl.cliente_id = cd.cliente_id
        WHERE cd.live_id = v_live
          AND EXISTS (SELECT 1 FROM capturas c WHERE c.cuenta_id = cd.cuenta_id)), '[]'::json));
    RETURN;
  END IF;

  IF p_q = 'cuenta' THEN
    IF NOT EXISTS (SELECT 1 FROM cuentas_diarias WHERE cuenta_id = v_id) THEN
      RETURN QUERY SELECT 404, json_build_object('ok', false, 'error', 'cuenta_no_encontrada'); RETURN;
    END IF;
    RETURN QUERY
    SELECT 200, json_build_object('ok', true,
      'cuenta', json_build_object('cuenta_id', cd.cuenta_id, 'live_id', cd.live_id, 'fecha_operativa', cd.fecha_operativa,
                  'fecha_limite_pago', cd.fecha_limite_pago, 'subtotal', cd.subtotal,
                  'monto_confirmado', cd.monto_confirmado, 'saldo', cd.saldo, 'estado', cd.estado,
                  'columna', fn_columna_cuenta(cd.cuenta_id), 'qr_enviado_en', cd.qr_enviado_en,
                  'vencida_en', cd.vencida_en),
      'cliente', json_build_object('whatsapp', cl.whatsapp, 'push_name', cl.push_name, 'nombre_real', cl.nombre_real,
                  'provisional', cl.nombre_real IS NULL, 'control', cl.control, 'control_desde', cl.control_desde,
                  'nicknames', (SELECT COALESCE(json_agg(json_build_object('nickname', nickname, 'capturas', capturas)
                                                ORDER BY ultima_vez DESC), '[]'::json)
                                FROM cuentas_tiktok WHERE cliente_id = cl.cliente_id),
                  'total_a_pagar', fn_total_a_pagar(cl.whatsapp)),
      'capturas', COALESCE((SELECT json_agg(json_build_object(
                    'captura_id', c.captura_id, 'nickname', c.nickname, 'precio', c.precio,
                    'estado_captura', c.estado_captura, 'confianza', c.confianza,
                    'confirmado', fn_confirmado_captura(c.captura_id), 'fecha_recepcion', c.fecha_recepcion,
                    'tiene_imagen', c.imagen_base64 IS NOT NULL) ORDER BY c.fecha_recepcion)
                  FROM capturas c WHERE c.cuenta_id = cd.cuenta_id), '[]'::json),
      'pagos', COALESCE((SELECT json_agg(json_build_object(
                    'pago_id', p2.pago_id, 'estado_pago', p2.estado_pago, 'resultado', p2.resultado,
                    'monto_pagado', p2.monto_pagado, 'monto_esperado', p2.monto_esperado,
                    'monto_confirmado', p2.monto_confirmado, 'excedente', p2.excedente,
                    'referencia_pago', p2.referencia_pago, 'enviado_por', p2.enviado_por,
                    'receptor_comprobante', p2.receptor_comprobante, 'fecha_comprobante', p2.fecha_comprobante,
                    'banco_app', p2.banco_app, 'confianza', p2.confianza, 'motivo_revision', p2.motivo_revision,
                    'fecha_recepcion', p2.fecha_recepcion, 'fecha_verificacion', p2.fecha_verificacion,
                    'tiene_comprobante', p2.comprobante_base64 IS NOT NULL) ORDER BY p2.fecha_recepcion DESC)
                  FROM pagos p2 WHERE p2.pago_id IN (
                    SELECT pc.pago_id FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                    WHERE c.cuenta_id = cd.cuenta_id)), '[]'::json),
      'mensajes', COALESCE((SELECT json_agg(m ORDER BY m.fecha) FROM (
                    SELECT direccion, tipo, texto, fecha FROM mensajes
                    WHERE whatsapp = cl.whatsapp ORDER BY fecha DESC LIMIT 40) m), '[]'::json),
      'historial', COALESCE((SELECT json_agg(json_build_object('fecha', a.fecha, 'accion', a.accion,
                    'captura_id', a.captura_id, 'estado_anterior', a.estado_anterior, 'estado_nuevo', a.estado_nuevo,
                    'detalle', a.detalle) ORDER BY a.fecha DESC, a.accion_id DESC)
                  FROM acciones_panel a
                  WHERE a.cuenta_id = cd.cuenta_id
                     OR a.captura_id IN (SELECT captura_id FROM capturas WHERE cuenta_id = cd.cuenta_id)
                     OR (a.whatsapp = cl.whatsapp AND a.accion IN ('devolver_agente', 'cliente_editar', 'reenviar_qr'))), '[]'::json))
    FROM cuentas_diarias cd JOIN clientes cl ON cl.cliente_id = cd.cliente_id
    WHERE cd.cuenta_id = v_id;
    RETURN;
  END IF;

  IF p_q = 'captura_imagen' THEN
    RETURN QUERY
    SELECT CASE WHEN x.b64 IS NULL THEN 404 ELSE 200 END,
           CASE WHEN x.b64 IS NULL THEN json_build_object('ok', false, 'error', 'sin_imagen')
                ELSE json_build_object('ok', true, 'captura_id', v_id,
                       'mime_type', CASE WHEN x.b64 LIKE 'iVBOR%' THEN 'image/png'
                                         WHEN x.b64 LIKE 'UklGR%' THEN 'image/webp' ELSE 'image/jpeg' END,
                       'imagen_base64', x.b64) END
    FROM (SELECT (SELECT regexp_replace(imagen_base64, '^data:[^,]*,', '') FROM capturas WHERE captura_id = v_id) AS b64) x;
    RETURN;
  END IF;

  RETURN QUERY SELECT 400, json_build_object('ok', false, 'error', 'consulta_desconocida',
    'consultas', json_build_array('lives', 'cuentas', 'cuenta', 'captura_imagen', 'reporte'));
END $$;

-- ─────────────────────────── Acciones ───────────────────────────
CREATE OR REPLACE FUNCTION fn_panel_accion(b jsonb)
RETURNS TABLE (codigo int, respuesta json, avisos json)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_accion    text := b ->> 'accion';
  v_nota      text := NULLIF(b ->> 'nota', '');
  v_notificar boolean := COALESCE((b ->> 'notificar_cliente')::boolean, true);
  v_cuenta    cuentas_diarias%ROWTYPE;
  v_whatsapp  text;
  v_live      text;
  v_total     numeric;
  v_ids       text[];
  v_aviso     json;
BEGIN
  -- Las acciones sobre una cuenta la identifican por cuenta_id; las de cliente aceptan whatsapp.
  IF b ? 'cuenta_id' THEN
    SELECT * INTO v_cuenta FROM cuentas_diarias WHERE cuenta_id = b ->> 'cuenta_id';
    IF NOT FOUND THEN
      RETURN QUERY SELECT 404, json_build_object('ok', false, 'error', 'cuenta_no_encontrada'), '[]'::json; RETURN;
    END IF;
    v_whatsapp := v_cuenta.cliente_id;
  ELSE
    v_whatsapp := NULLIF(regexp_replace(COALESCE(b ->> 'whatsapp', ''), '\D', '', 'g'), '');
  END IF;

  -- M4 · Iniciar live
  IF v_accion = 'iniciar_live' THEN
    IF EXISTS (SELECT 1 FROM lives WHERE estado = 'activo') THEN
      RETURN QUERY SELECT 409, json_build_object('ok', false, 'error', 'ya_hay_un_live_activo',
        'live_id', (SELECT live_id FROM lives WHERE estado = 'activo')), '[]'::json; RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('lives'));
    v_live := fn_nuevo_live_id(hoy_operativo());
    INSERT INTO lives (live_id, fecha_operativa, titulo) VALUES (v_live, hoy_operativo(), NULLIF(b ->> 'titulo', ''));
    INSERT INTO acciones_panel (accion, estado_nuevo, detalle)
    VALUES ('iniciar_live', 'activo', jsonb_build_object('live_id', v_live, 'nota', v_nota));
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'live', fn_indicadores_live(v_live)), '[]'::json; RETURN;
  END IF;

  -- M4 · Cerrar live
  IF v_accion = 'cerrar_live' THEN
    UPDATE lives SET estado = 'cerrado', cierre = now() WHERE estado = 'activo' RETURNING live_id INTO v_live;
    IF v_live IS NULL THEN
      RETURN QUERY SELECT 409, json_build_object('ok', false, 'error', 'no_hay_live_activo'), '[]'::json; RETURN;
    END IF;
    INSERT INTO acciones_panel (accion, estado_anterior, estado_nuevo, detalle)
    VALUES ('cerrar_live', 'activo', 'cerrado', jsonb_build_object('live_id', v_live, 'nota', v_nota));
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'live', fn_indicadores_live(v_live)), '[]'::json; RETURN;
  END IF;

  -- M8 · Confirmar un pago (total o parcial) con el monto que la vendedora vio en su banco
  IF v_accion = 'confirmar_pago' THEN
    RETURN QUERY SELECT * FROM fn_confirmar_pago(b ->> 'pago_id', NULLIF(b ->> 'monto', '')::numeric, v_nota, v_notificar);
    RETURN;
  END IF;

  -- M10 · Arrastrar a "Pagadas": todas las compras abiertas de la cuenta quedan pagadas
  IF v_accion = 'cuenta_pagada' THEN
    IF v_cuenta.cuenta_id IS NULL THEN
      RETURN QUERY SELECT 400, json_build_object('ok', false, 'error', 'cuenta_id_requerido'), '[]'::json; RETURN;
    END IF;
    v_total := v_cuenta.saldo;
    INSERT INTO acciones_panel (accion, captura_id, cuenta_id, whatsapp, estado_anterior, estado_nuevo, detalle)
    SELECT 'marcar_pagada', captura_id, cuenta_id, whatsapp, estado_captura, 'pagada', jsonb_build_object('nota', v_nota)
    FROM capturas WHERE cuenta_id = v_cuenta.cuenta_id AND estado_captura NOT IN ('pagada', 'cancelada');
    WITH upd AS (
      UPDATE capturas SET estado_captura = 'pagada'
      WHERE cuenta_id = v_cuenta.cuenta_id AND estado_captura NOT IN ('pagada', 'cancelada')
      RETURNING captura_id)
    SELECT array_agg(captura_id) INTO v_ids FROM upd;
    -- Comprobantes de esas compras que quedan totalmente cubiertos pasan a 'verificado'.
    UPDATE pagos p SET estado_pago = 'verificado', fecha_verificacion = now()
    WHERE p.estado_pago IN ('reportado', 'requiere_revision')
      AND EXISTS (SELECT 1 FROM pagos_capturas pc WHERE pc.pago_id = p.pago_id AND pc.captura_id = ANY (v_ids))
      AND NOT EXISTS (SELECT 1 FROM pagos_capturas pc JOIN capturas c ON c.captura_id = pc.captura_id
                      WHERE pc.pago_id = p.pago_id AND c.estado_captura NOT IN ('pagada', 'cancelada'));
    RETURN QUERY SELECT 200,
      json_build_object('ok', true, 'cuenta_id', v_cuenta.cuenta_id, 'compras_pagadas', to_json(COALESCE(v_ids, '{}'))),
      CASE WHEN v_notificar AND v_ids IS NOT NULL THEN json_build_array(json_build_object('whatsapp', v_whatsapp,
        'texto', '¡Hola! La vendedora verificó tu pago' || CASE WHEN v_total > 0 THEN ' de ' || fn_bs(v_total) ELSE '' END
                 || '. Tu compra quedó registrada como pagada. ¡Gracias por tu compra!'))
      ELSE '[]'::json END;
    RETURN;
  END IF;

  -- Handoff · Arrastrar a "Por revisar": la vendedora toma la conversación (el bot se silencia)
  IF v_accion = 'cuenta_revision' THEN
    IF v_whatsapp IS NULL THEN
      RETURN QUERY SELECT 400, json_build_object('ok', false, 'error', 'cliente_requerido'), '[]'::json; RETURN;
    END IF;
    UPDATE clientes SET control = 'humano', control_desde = now() WHERE whatsapp = v_whatsapp;
    INSERT INTO acciones_panel (accion, cuenta_id, whatsapp, estado_nuevo, detalle)
    VALUES ('tomar_conversacion', v_cuenta.cuenta_id, v_whatsapp, 'humano', jsonb_build_object('nota', v_nota));
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'whatsapp', v_whatsapp, 'control', 'humano'), '[]'::json;
    RETURN;
  END IF;

  -- Handoff · Devolver al agente: lo que estaba en revisión vuelve a 'confirmada' y se envía el QR
  IF v_accion = 'devolver_agente' THEN
    IF v_whatsapp IS NULL OR NOT EXISTS (SELECT 1 FROM clientes WHERE whatsapp = v_whatsapp) THEN
      RETURN QUERY SELECT 404, json_build_object('ok', false, 'error', 'cliente_no_encontrado'), '[]'::json; RETURN;
    END IF;
    INSERT INTO acciones_panel (accion, captura_id, cuenta_id, whatsapp, estado_anterior, estado_nuevo, detalle)
    SELECT 'devolver_agente', captura_id, cuenta_id, whatsapp, estado_captura, 'confirmada', jsonb_build_object('nota', v_nota)
    FROM capturas WHERE whatsapp = v_whatsapp AND estado_captura = 'requiere_revision';
    UPDATE capturas SET estado_captura = 'confirmada' WHERE whatsapp = v_whatsapp AND estado_captura = 'requiere_revision';
    UPDATE clientes SET control = 'agente', control_desde = now() WHERE whatsapp = v_whatsapp;
    INSERT INTO acciones_panel (accion, cuenta_id, whatsapp, estado_anterior, estado_nuevo, detalle)
    VALUES ('devolver_agente', v_cuenta.cuenta_id, v_whatsapp, 'humano', 'agente', jsonb_build_object('nota', v_nota));
    v_total := fn_total_a_pagar(v_whatsapp);
    IF v_total > 0 AND COALESCE((b ->> 'enviar_qr')::boolean, true) THEN
      v_aviso := fn_aviso_qr(v_whatsapp, v_total);
      UPDATE cuentas_diarias cd SET qr_enviado_en = now()
      WHERE cd.qr_enviado_en IS NULL AND EXISTS (
        SELECT 1 FROM capturas c WHERE c.cuenta_id = cd.cuenta_id AND c.estado_captura = 'confirmada' AND c.whatsapp = v_whatsapp);
    END IF;
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'whatsapp', v_whatsapp, 'control', 'agente',
                                               'total_a_pagar', v_total, 'qr_enviado', v_aviso IS NOT NULL),
      CASE WHEN v_aviso IS NOT NULL THEN json_build_array(v_aviso) ELSE '[]'::json END;
    RETURN;
  END IF;

  -- Reenviar el QR con el total pendiente
  IF v_accion = 'reenviar_qr' THEN
    v_total := fn_total_a_pagar(v_whatsapp);
    IF v_whatsapp IS NULL OR v_total <= 0 THEN
      RETURN QUERY SELECT 409, json_build_object('ok', false, 'error', 'sin_saldo_pendiente'), '[]'::json; RETURN;
    END IF;
    INSERT INTO acciones_panel (accion, cuenta_id, whatsapp, detalle)
    VALUES ('reenviar_qr', v_cuenta.cuenta_id, v_whatsapp, jsonb_build_object('total', v_total, 'nota', v_nota));
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'total_a_pagar', v_total),
                        json_build_array(fn_aviso_qr(v_whatsapp, v_total));
    RETURN;
  END IF;

  -- D-03 · Completar el nombre real del cliente
  IF v_accion = 'cliente_editar' THEN
    UPDATE clientes SET nombre_real = NULLIF(trim(b ->> 'nombre_real'), '') WHERE whatsapp = v_whatsapp;
    IF NOT FOUND THEN
      RETURN QUERY SELECT 404, json_build_object('ok', false, 'error', 'cliente_no_encontrado'), '[]'::json; RETURN;
    END IF;
    INSERT INTO acciones_panel (accion, whatsapp, detalle)
    VALUES ('cliente_editar', v_whatsapp, jsonb_build_object('nombre_real', b ->> 'nombre_real'));
    RETURN QUERY SELECT 200, json_build_object('ok', true, 'whatsapp', v_whatsapp, 'nombre_real', NULLIF(trim(b ->> 'nombre_real'), '')), '[]'::json;
    RETURN;
  END IF;

  RETURN QUERY SELECT 400, json_build_object('ok', false, 'error', 'accion_desconocida',
    'acciones', json_build_array('iniciar_live', 'cerrar_live', 'confirmar_pago', 'cuenta_pagada',
                                 'cuenta_revision', 'devolver_agente', 'reenviar_qr', 'cliente_editar')), '[]'::json;
END $$;

COMMIT;
