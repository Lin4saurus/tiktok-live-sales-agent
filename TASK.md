# TASK.md — Tablero de milestones

> 📍 **FOCO ACTUAL:** **M0 — Entorno y andamiaje** — Estado: `[~] En curso`

**Leyenda de estados:**
`[ ]` Pendiente · `[~]` En curso · `[x]` Completado · `[!]` Bloqueado · `[?]` En revisión

---

## [~] M0 · Entorno y andamiaje
- **Objetivo:** n8n corriendo, base de datos vacía creada, WhatsApp conectado en prueba, `.env` con secretos, repo con los archivos de docs.
- **DoD:** mando "hola" al WhatsApp y n8n recibe el webhook y responde algo fijo.

## [ ] M1 · Modelo de datos
- **Objetivo:** crear las 9 tablas con campos y relaciones (ver `DATA_MODEL.md`).
- **DoD:** puedo insertar y leer una fila de prueba en cada tabla.

## [ ] M2 · Ingesta de WhatsApp
- **Objetivo:** mensaje entrante → registrar en `mensajes` → identificar o crear cliente por número → descargar la imagen.
- **DoD:** todo mensaje queda en `mensajes`, crea/encuentra el cliente y guarda la imagen.

## [ ] M3 · Visión IA
- **Objetivo:** prompt que devuelve `tipo_imagen` (captura vs comprobante) + campos + confianza.
- **DoD:** con 20 imágenes reales devuelve JSON correcto y marca baja confianza cuando toca.

## [ ] M4 · Gestión de live
- **Objetivo:** botones iniciar/cerrar, generar `live_id`, live activo, asociación de respaldo, fechas operativa/recepción/límite.
- **DoD:** abro un live y las capturas se asocian; si olvido abrirlo, cae la regla de respaldo.

## [ ] M5 · Captura y cuenta diaria
- **Objetivo:** crear captura, agrupar por `cliente_id + live_id`, recalcular totales, mensaje de confirmación.
- **DoD:** tres capturas del mismo cliente/live suman una cuenta con subtotal correcto.

## [ ] M6 · Envío del QR
- **Objetivo:** enviar el QR una vez por cuenta desde `configuracion_pago`; reenviar solo si lo piden.
- **DoD:** se manda una vez; la segunda captura no lo reenvía; "mándame el QR" sí.

## [ ] M7 · Flujo de pago
- **Objetivo:** leer comprobante, comparar contra saldo, resultado exacto/mayor/menor, crear `pagos` + `pagos_capturas`.
- **DoD:** comprobante igual → "exacto"; menor → parcial; mayor → revisión.

## [ ] M8 · Confirmación humana
- **Objetivo:** la vendedora confirma el pago; la cuenta cierra o queda parcial.
- **DoD:** al confirmar, cuenta y capturas pasan a Pagada; si falta, queda Parcial.

## [ ] M9 · Vencimiento automático
- **Objetivo:** schedule trigger que cancela cuentas vencidas, excluyendo "pago en revisión", y notifica a cliente y vendedora.
- **DoD:** cuenta impaga tras el plazo pasa a Vencida; una con comprobante en revisión no se cancela.

## [ ] M10 · Panel de control
- **Objetivo:** indicadores del live, columnas Pagadas/Pendientes/Revisión, drag-and-drop con confirmación, botones de acción.
- **DoD:** veo el estado en vivo y muevo una cuenta entre columnas con confirmación.

## [ ] M11 · Reportes y métricas
- **Objetivo:** ventas por live, totales, pendientes, exportar resumen.
- **DoD:** genero el resumen de un live cerrado con sus cifras.

## [ ] M12 · Endurecimiento
- **Objetivo:** pago duplicado por `referencia_pago`, umbral de confianza, zona horaria, manejo de datos sensibles.
- **DoD:** referencia repetida → revisión; baja confianza → revisión; secretos fuera del repo.
