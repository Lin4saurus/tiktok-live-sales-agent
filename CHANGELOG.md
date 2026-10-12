# CHANGELOG.md — Bitácora

Una línea por sesión de trabajo, la más reciente arriba. Formato: `AAAA-MM-DD — [Milestone] descripción`.

- 2026-10-12 — [M2] WhatsApp Cloud API oficial (borrador): db/007 configuracion_whatsapp, webhook /webhook/whatsapp-cloud con verificación y descarga de archivos, envío por Graph API con plantilla fuera de 24 h, credencial whatsapp-cloud-token (D-30).
- 2026-10-12 — [M10] "Devolver al agente" → "Reactivar bot", "Atender yo" → "Pausar bot (atiendo yo)"; comprobante repetido → "⚠ Posible estafa" con el pago anterior que usó esa referencia (D-29).
- 2026-10-12 — [M10] El panel sigue solo al live actual (un live de respaldo nuevo dejaba el tablero en el live anterior), avisa de cuentas abiertas en otros lives, descarta respuestas de un live anterior y en segundo plano consulta cada 4 s con aviso en el título (D-28).
- 2026-10-12 — [M7] WA - Pagos ya no responde al recibir un comprobante; el único mensaje es la confirmación de la vendedora (D-27). Borrador, falta publicar.
- 2026-10-11 — [M10] Panel en tiempo real (db/006, sondeo de 3 s con animaciones), un solo "Confirmar pago" en Acciones (confirmar_pago_cuenta), detalle reordenado y conversación ampliable (D-26).
- 2026-10-11 — [M12] aplicar_migraciones.ps1 corrompía tildes al pasar el SQL por PowerShell; ahora copia el archivo al contenedor. Funciones reaplicadas y título del live de respaldo corregido.
- 2026-10-08 — [M5] El cliente puede cancelar su compra por WhatsApp (intención 'cancela', D-25); borrador del adaptador de entrada. Compra de prueba "Koorica" cancelada a mano.
- 2026-10-07 — [M12] Secretos de docker-compose.yml a .env; zona America/La_Paz; Postgres y Evolution solo en 127.0.0.1 (requiere reinicio).
- 2026-10-07 — [M3] Herramienta herramientas/probar_vision.ps1 para medir la visión con imágenes reales.
- 2026-10-07 — [M10/M11] Panel v2: tablero por cuentas con arrastrar y soltar, live, detalle con conversación, reporte y CSV; página servida desde la base (panel/panel.html).
- 2026-10-07 — [M9] Workflow Vencimientos (apagado) y fn_vencer_cuentas.
- 2026-10-07 — [M7/M8] Pagos parciales: fn_registrar_pago, fn_confirmar_pago, pagos_capturas; WA - Pagos en borrador.
- 2026-10-07 — [M2/M6/handoff] Adaptador de entrada (borrador): historial de mensajes, imagen de la captura, silencio con control humano, QR una vez por cuenta y a pedido; salida registra mensajes enviados.
- 2026-10-07 — [M1/M4/M5] Migraciones db/001–005: lives, cuentas diarias, nicknames, pagos_capturas, mensajes, triggers y regla de respaldo.
- 2026-10-07 — [Docs] CLAUDE.md, DATA_MODEL.md, DECISIONS.md (D-13 a D-19) y TASK.md actualizados con lo construido.
- 2026-10-07 — [M5/M6] Borrador: un "SÍ" confirma todas las compras pendientes del cliente y el QR incluye el total a pagar.
- 2026-10-07 — [M10] Panel web servido por n8n en /webhook/panel (lista, filtros, detalle con comprobante, acciones, historial).
- 2026-10-07 — [M8/M10] Panel - API capa 2: marcar pagada (con aviso al cliente), cambiar estado, editar, comprobante; tabla acciones_panel; estado `cancelada`.
- 2026-10-07 — [M10] Workflow Panel - API capa 1: endpoints de lectura protegidos con X-Panel-Key.
- 2026-10-07 — [M7/M12] Conciliación con banderas (referencia duplicada, monto, receptor, sin compra, ilegible) y mensajes neutros; nunca se rechaza ni se acusa.
- 2026-10-06 — [M7] Workflow WA - Pagos: comprobantes en imagen y PDF conciliados contra la suma de compras confirmadas.
- 2026-10-05 — [M6] Tabla configuracion_pago y envío del QR tras confirmar; adaptador de salida con imágenes.
- 2026-10-04 — [M5] Respuesta automática a capturas; confirmación/corrección de nombre con Gemini; idempotencia por message_id.
- 2026-10-03 — [M1/M2] Base `ventas` con clientes y capturas; deduplicación de 30 min; se ignoran grupos.
- 2026-10-01 — [M3] Lectura de capturas con Gemini (nombre y precio manuscritos).
- 2026-09-30 — [M2] Adaptador de entrada (Evolution) y regla D-13: un workflow por fase.
- 2026-09-25 — [M0] Milestones M0–M12 cargados en TASK.md con objetivo y DoD.
- 2026-09-25 — [M0] Estructura de trabajo inicial creada.
