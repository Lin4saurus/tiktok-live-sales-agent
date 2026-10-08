# TASK.md — Tablero de milestones

> 📍 **FOCO ACTUAL:** que la vendedora **publique y pruebe** lo construido el 2026-10-07
> (ver "Pasos manuales pendientes" al final). El código de M1–M12 está hecho; lo que queda
> requiere intervención humana: publicar, activar, reiniciar Docker, cambiar contraseñas y
> aportar imágenes reales.

**Leyenda de estados:**
`[ ]` Pendiente · `[~]` En curso · `[x]` Completado · `[!]` Bloqueado · `[?]` En revisión

---

## [x] M0 · Entorno y andamiaje
- **Objetivo:** n8n corriendo, base de datos vacía creada, WhatsApp conectado en prueba, `.env` con secretos, repo con los archivos de docs.
- **DoD:** mando "hola" al WhatsApp y n8n recibe el webhook y responde algo fijo.
- **Hecho:** n8n + Evolution API v2.3.4 + PostgreSQL 16 en Docker; secretos en `.env`; `init-db.sh` crea las bases.

## [x] M1 · Modelo de datos
- **Objetivo:** crear las 9 tablas con campos y relaciones (ver `DATA_MODEL.md`).
- **DoD:** puedo insertar y leer una fila de prueba en cada tabla.
- **Hecho:** `lives`, `clientes`, `cuentas_tiktok`, `cuentas_diarias`, `capturas`, `pagos`, `pagos_capturas`, `mensajes`, `configuracion_pago` (+ `mensajes_procesados`, `acciones_panel`, `panel_recursos`). Migraciones en `db/`, probadas con inserciones de prueba en transacción.

## [?] M2 · Ingesta de WhatsApp
- **Objetivo:** mensaje entrante → registrar en `mensajes` → identificar o crear cliente por número → descargar la imagen.
- **DoD:** todo mensaje queda en `mensajes`, crea/encuentra el cliente y guarda la imagen.
- **Hecho:** historial de entrantes y salientes en `mensajes`; cliente creado por número; imagen de la captura guardada en `capturas.imagen_base64`.
- **Revisión:** cambios en borrador del adaptador de entrada y de salida → publicar y probar.

## [?] M3 · Visión IA
- **Objetivo:** prompt que devuelve `tipo_imagen` (captura vs comprobante) + campos + confianza.
- **DoD:** con 20 imágenes reales devuelve JSON correcto y marca baja confianza cuando toca.
- **Hecho:** prompts de captura y comprobante (imagen y PDF); herramienta `herramientas\probar_vision.ps1` que mide aciertos.
- **Revisión:** la vendedora debe aportar las 20 imágenes reales y ejecutar la herramienta.

## [x] M4 · Gestión de live
- **Objetivo:** botones iniciar/cerrar, generar `live_id`, live activo, asociación de respaldo, fechas operativa/recepción/límite.
- **DoD:** abro un live y las capturas se asocian; si olvido abrirlo, cae la regla de respaldo.
- **Hecho:** botones en el panel; `LIVE-AAAAMMDD-NNN`; un solo live activo; regla de respaldo (D-21); fecha operativa y límite en hora de Bolivia.

## [x] M5 · Captura y cuenta diaria
- **Objetivo:** crear captura, agrupar por `cliente_id + live_id`, recalcular totales, mensaje de confirmación.
- **DoD:** tres capturas del mismo cliente/live suman una cuenta con subtotal correcto.
- **Hecho:** trigger que asigna live y cuenta y recalcula totales; un "SÍ" confirma todas las pendientes (D-24, falta validarlo en WhatsApp).

## [?] M6 · Envío del QR
- **Objetivo:** enviar el QR una vez por cuenta desde `configuracion_pago`; reenviar solo si lo piden.
- **DoD:** se manda una vez; la segunda captura no lo reenvía; "mándame el QR" sí.
- **Hecho:** `cuentas_diarias.qr_enviado_en`; recordatorio del total si ya lo tiene; "QR" lo reenvía; botón "Reenviar QR" en el panel.
- **Revisión:** publicar el adaptador de entrada y probar.

## [?] M7 · Flujo de pago
- **Objetivo:** leer comprobante, comparar contra saldo, resultado exacto/mayor/menor, crear `pagos` + `pagos_capturas`.
- **DoD:** comprobante igual → "exacto"; menor → parcial; mayor → revisión.
- **Hecho:** `fn_registrar_pago`: igual → `coincide`, menor → `parcial`, mayor → revisión (D-20); `pagos_capturas`.
- **Revisión:** publicar `WA - Pagos` y probar.

## [x] M8 · Confirmación humana
- **Objetivo:** la vendedora confirma el pago; la cuenta cierra o queda parcial.
- **DoD:** al confirmar, cuenta y capturas pasan a Pagada; si falta, queda Parcial.
- **Hecho:** "Confirmar pago…" en el panel con monto editable (`fn_confirmar_pago`); cuenta `pagada` o `parcial`; aviso al cliente.

## [?] M9 · Vencimiento automático
- **Objetivo:** schedule trigger que cancela cuentas vencidas, excluyendo "pago en revisión", y notifica a cliente y vendedora.
- **DoD:** cuenta impaga tras el plazo pasa a Vencida; una con comprobante en revisión no se cancela.
- **Hecho:** workflow `Vencimientos` (cada hora) + `fn_vencer_cuentas` (D-22), probado en transacción.
- **Revisión:** cargar el número de la vendedora y activar el workflow.

## [x] M10 · Panel de control
- **Objetivo:** indicadores del live, columnas Pagadas/Pendientes/Revisión, drag-and-drop con confirmación, botones de acción.
- **DoD:** veo el estado en vivo y muevo una cuenta entre columnas con confirmación.
- **Hecho:** tablero por cuentas con arrastrar y soltar, indicadores del live, detalle con comprobantes, compras, conversación e historial; refresco cada 30 s.
- **Pendiente aparte:** acceso desde el celular (exponer n8n en la red).

## [x] M11 · Reportes y métricas
- **Objetivo:** ventas por live, totales, pendientes, exportar resumen.
- **DoD:** genero el resumen de un live cerrado con sus cifras.
- **Hecho:** pestaña Reporte (vendido, cobrado, por cobrar, clientes, compras, cuentas) y descarga CSV.

## [?] M12 · Endurecimiento
- **Objetivo:** pago duplicado por `referencia_pago`, umbral de confianza, zona horaria, manejo de datos sensibles.
- **DoD:** referencia repetida → revisión; baja confianza → revisión; secretos fuera del repo.
- **Hecho:** referencia repetida → revisión; confianza < 0.6 → revisión; idempotencia; zona `America/La_Paz`; secretos movidos a `.env`; Postgres y Evolution solo en 127.0.0.1.
- **Revisión:** reiniciar Docker para aplicar `docker-compose.yml`; **cambiar las contraseñas** (las anteriores quedaron en el historial de git, repo en GitHub).

---

## Pasos manuales pendientes (vendedora)

1. Publicar `WA - Adaptador de entrada`, `WA - Adaptador de salida` y `WA - Pagos` en n8n.
2. Probar por WhatsApp: 2 capturas → "sí" → QR con total → comprobante parcial → confirmar en el panel.
3. Cargar `whatsapp_vendedora` en `configuracion_pago` y activar el workflow `Vencimientos`.
4. Reiniciar Docker (`docker compose up -d`) para aplicar zona horaria y `.env`.
5. Cambiar la contraseña de Postgres y la API key de Evolution (y actualizar las credenciales de n8n).
6. Poner 20 imágenes reales en `pruebas_vision/` y ejecutar `herramientas\probar_vision.ps1`.
