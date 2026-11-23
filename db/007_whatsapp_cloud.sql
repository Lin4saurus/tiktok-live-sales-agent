-- 007 · Configuración de WhatsApp: proveedor Evolution (no oficial) o Cloud API (oficial de Meta).
-- Los workflows de entrada y salida leen esta tabla. Para cambiar de proveedor:
--   UPDATE configuracion_whatsapp SET valor = 'cloud' WHERE clave = 'proveedor';
-- El token de acceso de Meta NO va aquí: vive en la credencial de n8n "whatsapp-cloud-token".
-- El verify_token se genera al instalar y no se versiona (ver CLAUDE.md §5).
-- Idempotente.

BEGIN;

CREATE TABLE IF NOT EXISTS configuracion_whatsapp (
  clave       text PRIMARY KEY,
  valor       text,
  descripcion text,
  actualizado timestamp NOT NULL DEFAULT now()
);

INSERT INTO configuracion_whatsapp (clave, valor, descripcion) VALUES
  ('proveedor',        'evolution', 'Por dónde se envían los mensajes: evolution | cloud'),
  ('graph_version',    'v25.0',     'Versión de la Graph API de Meta'),
  ('phone_number_id',  NULL,        'Phone number ID del número de WhatsApp (App de Meta → WhatsApp → API Setup)'),
  ('waba_id',          NULL,        'WhatsApp Business Account ID'),
  ('verify_token',     NULL,        'Token que Meta envía al verificar el webhook (se genera al instalar)'),
  ('plantilla_aviso',  'aviso_compra', 'Plantilla utility aprobada para mensajes fuera de las 24 h ({{1}} = texto del aviso)'),
  ('plantilla_idioma', 'es',        'Idioma de la plantilla')
ON CONFLICT (clave) DO NOTHING;

-- Toda la configuración como un objeto JSON (la usan los workflows).
CREATE OR REPLACE FUNCTION fn_config_whatsapp() RETURNS json LANGUAGE sql STABLE AS $$
  SELECT COALESCE(json_object_agg(clave, valor), '{}'::json) FROM configuracion_whatsapp
$$;

COMMIT;
