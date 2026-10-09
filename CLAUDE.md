# CLAUDE.md — Contexto permanente del proyecto

> **Instrucción fija:** Antes de trabajar, lee siempre `TASK.md` y este archivo.
> Al terminar, actualiza `TASK.md` y añade una línea a `CHANGELOG.md`.

Idioma de trabajo: **español** (documentos, comentarios, mensajes de commit).

Documentos relacionados:
- `TASK.md` — tablero de milestones y foco actual.
- `DECISIONS.md` — decisiones de diseño ya cerradas (no se reabren sin nueva entrada).
- `DATA_MODEL.md` — esquema de datos y lógica de la base.
- `CHANGELOG.md` — bitácora de cambios.

Carpetas: `db/` (migraciones SQL y scripts de carga), `panel/` (página web del panel),
`herramientas/` (scripts de prueba).

---

## 1. Descripción del proyecto

Sistema de gestión de ventas para una vendedora que vende en vivo por TikTok (lives).
Durante el live, el cliente compra un producto y luego escribe por WhatsApp enviando una
captura de pantalla del live donde aparecen su nickname de TikTok y el precio. Una IA de
visión lee la imagen, extrae los datos y se registra la venta. Las ventas del mismo
cliente en el mismo live se agrupan en una cuenta de cobro (cuenta_diaria), a la cual se
le envía un QR de pago.

El cliente paga y envía su comprobante por WhatsApp; la IA lo lee y precarga los datos
del pago, pero es la vendedora quien confirma que el dinero llegó. Todo el flujo está
orquestado con n8n y lógica en JavaScript, con un panel de control que se comunica con
los flujos mediante webhooks. El objetivo es eliminar el registro manual de ventas y
el seguimiento de cobros, sin gestionar inventario ni envíos. El diseño funcional ya
está cerrado (ver `DECISIONS.md`).

> Lo que ya está construido y lo poco que falta respecto a este diseño está en §9.

## 2. Stack y por qué

| Componente | Elección | Por qué |
|---|---|---|
| Orquestación | **n8n** (self-hosted en Docker, ver `docker-compose.yml`) — http://127.0.0.1:5678 | Flujos visuales fáciles de mostrar y mantener; nodos nativos para HTTP, webhooks, BD y LLMs; nodos Code en JavaScript para la lógica propia. |
| Lógica | **JavaScript** (nodos Code de n8n) + **SQL** (nodos Postgres) | Lenguaje nativo de n8n. Las reglas que tocan varias filas van en una sola sentencia o función SQL para que sean atómicas. |
| Reglas de datos | **Funciones y triggers de PostgreSQL** (`db/002`–`005`) | Lo que debe cumplirse siempre (live y cuenta de cada captura, totales, control agente/humano, conciliación) vive en la base, venga el cambio de WhatsApp o del panel. |
| Mensajería | **Evolution API v2.3.4** (instancia `ventas_tiktok`) — elegida para la fase actual | Rápida de montar para pruebas. WhatsApp Cloud API queda como opción para producción (sin decidir). |
| Visión / texto | **Google Gemini** (`gemini-3.1-flash-lite`) con el nodo nativo de n8n | Lee capturas del live y comprobantes (imagen y PDF) y clasifica la intención de las respuestas de texto; devuelve JSON. |
| Base de datos | **PostgreSQL 16**, base `ventas` (extensiones `unaccent` y `fuzzystrmatch`) | El dominio es relacional y requiere integridad y consultas por fecha/estado. Ver `DATA_MODEL.md`. |
| Panel de control | **Página web servida por n8n** (`panel/panel.html`, guardada en la base) + API de webhooks en el workflow `Panel - API` | Sin servidor extra: la vendedora abre http://127.0.0.1:5678/webhook/panel. |

## 3. Glosario del dominio

- **live** — Transmisión en vivo de TikTok donde se venden productos. Tiene una fecha (su día) que define la `fecha_operativa` de todo lo que se vende en él.
- **captura** — Imagen (screenshot del live) que envía el cliente por WhatsApp con su nickname y el precio. **Una captura = un producto = una venta.** La venta se crea al llegar la captura. En la captura, la vendedora escribe **a mano** sobre la bolsa/etiqueta el nombre del comprador y el precio (p. ej. "Fricosi 10"): eso es lo único que lee la IA.
- **cuenta_diaria** — Cuenta de cobro que agrupa todas las capturas de un mismo cliente en un mismo live. Clave: `cliente_id + live_id` (no la fecha). Recibe un único QR de pago.
- **comprobante** — Imagen o PDF del pago (transferencia/QR/Yape) que el cliente envía. La IA la lee y precarga los datos; la vendedora confirma.
- **cliente provisional** — Cliente creado automáticamente al llegar su primer mensaje, identificado solo por su número de WhatsApp. Su nombre real se completa después, dentro de una conversación iniciada por el cliente.
- **fecha_operativa** — Día del live al que pertenece una venta/cuenta, independientemente de cuándo llegue la captura o el pago.
- **fecha_limite_pago** — Fin del día siguiente a la `fecha_operativa` (fin del día siguiente al live).
- **live de respaldo** — Live creado automáticamente cuando llegan capturas y la vendedora no abrió ninguno.
- **revisión** — Estado `requiere_revision`: algo no cuadra o no se entendió. Nunca es un rechazo; la vendedora decide desde el panel.
- **pago reportado** — El cliente envió un comprobante que cuadra; falta que la vendedora lo vea en su banco. **No** es "pagado".
- **pago parcial** — El cliente pagó menos de lo que debe; la cuenta queda `parcial` con su saldo.
- **control humano** — La vendedora atiende la conversación de un cliente y el bot no le responde (handoff). Se activa cuando algo pasa a revisión o desde el panel; se devuelve al agente desde el panel.

## 4. Convenciones de IDs

| Entidad | Formato | Ejemplo |
|---|---|---|
| Live | `LIVE-AAAAMMDD-NNN` | `LIVE-20260925-001` |
| Cuenta diaria | `CD-AAAAMMDD-NNN-NNN` (ID del live + correlativo de la cuenta en ese live) | `CD-20260925-001-004` |
| Captura | UUID en texto | `64237423-f695-…` |
| Pago | UUID en texto | `1a587b86-3437-…` |
| Cliente | el número de WhatsApp (solo dígitos) | `59161317418` |

- `NNN` es un correlativo de 3 dígitos, empezando en `001` (por día para lives, por live para cuentas).
- Las fechas en IDs usan la `fecha_operativa` (hora de Bolivia), no la fecha de recepción.
- Capturas y pagos usan UUID: no se muestran al cliente y así no hubo que migrar los existentes.

## 5. Regla de secretos

- **Credenciales y datos de clientes NUNCA van al repositorio.** Esto incluye API keys, tokens de WhatsApp, cadenas de conexión, números de teléfono, nombres, capturas y comprobantes reales.
- Los secretos van en `.env` (ignorado por git). `.env.example` solo lista las claves **vacías**. `docker-compose.yml` los lee de `.env`.
- La carpeta `secrets/`, `n8n_data/`, `postgres_data/`, `evolution_instances/` y `pruebas_vision/` están en `.gitignore`.
- Para pruebas, usar datos ficticios o anonimizados.
- Al exportar workflows de n8n, verificar que no incluyan credenciales ni datos reales antes de versionarlos.
- En n8n, las claves viven **solo en credenciales de n8n**, nunca escritas dentro de un nodo. Credenciales en uso: `Postgres credencial` (BD `ventas`), `evolution-apikey` (Header Auth hacia Evolution), `gemini-api-vieja` / `gemini-api-viejanga` (Gemini), `panel-api-key` (Header Auth `X-Panel-Key` que protege la API del panel). Los valores no se documentan aquí.

## 6. Arquitectura actual (n8n)

Un workflow por fase de negocio (D-13). Todos en la instancia local; los cambios quedan
en **borrador** hasta que se pulsa **Publish** en n8n. La lógica de datos está en la base
(`db/`), así que muchos nodos Postgres son una sola llamada a una función.

| Workflow | ID | Qué hace |
|---|---|---|
| **WA - Adaptador de entrada (Evolution)** | `65m8fkrTuzGtYPTk` | Webhook `POST /webhook/evolution-inbound` (Evolution apunta a `http://n8n:5678/...`). Normaliza el mensaje, descarta grupos (`@g.us`), mensajes propios (`fromMe`) y eventos que no son `messages.upsert`; registra el mensaje (idempotencia + historial) y, si la vendedora atiende a ese cliente (`control = humano`), se detiene. Enruta: **imagen** → Gemini clasifica `captura_live` / `comprobante_pago`; **texto** → interpreta la respuesta; **PDF** → comprobante. |
| **WA - Adaptador de salida (Evolution)** | `IHvSy5Dn3qEbQHQQ` | Sub-workflow reutilizable: envía por Evolution texto (`sendText`) o imagen con pie (`sendMedia`) y guarda el mensaje enviado en `mensajes`. |
| **WA - Pagos** | `FKzlPXY3RHPBAZ26` | Sub-workflow: `fn_registrar_pago` concilia el comprobante (coincide / parcial / revisión) y se responde con un mensaje neutro. |
| **Panel - API** | `4LsIRtnSwlEumgHt` | Backend y página del panel (ver §8). |
| **Vencimientos** | `TbrboRHbDH2uJBMf` | Cada hora (minuto 5): `fn_vencer_cuentas` cancela cuentas vencidas sin pago y avisa al cliente y a la vendedora. |

### Flujo de una venta

1. **Captura** → Gemini lee nickname y precio manuscritos → se guarda la captura (`nueva`); la base le asigna el **live** (activo o de respaldo) y la **cuenta diaria** del cliente → se responde *"De tu captura leí el nombre X y el precio de la vendedora es Y Bs…"*, con el total si ya tenía otras pendientes.
2. **Respuesta de texto** → Gemini clasifica: `confirma` / `corrige_nombre` / `reclama_precio` / `pide_qr` / `cancela` / `otro`. Se aplica a **todas** las compras `nueva` del cliente. Sin compras `nueva`, palabras como "cancelo" o "ya no compraré" cancelan sus compras sin pagar (D-25) y "QR" reenvía el QR.
3. **QR** → se envía **una vez por cuenta diaria** con *"Total a pagar: N Bs"*. Si la cuenta ya lo recibió, la confirmación recuerda el total. Si el cliente escribe "QR", se le reenvía.
4. **Comprobante** (imagen o PDF) → Gemini extrae los datos → `WA - Pagos`: igual → `reportado`; menor → `parcial` ("te faltarían N Bs"); mayor o con banderas → `requiere_revision` y la conversación pasa a la vendedora.
5. **Vendedora** → en el panel confirma el pago con el monto que vio en su banco (total o parcial), o arrastra la cuenta a "Pagadas". El cliente recibe el aviso.
6. **Vencimiento** → al terminar el día siguiente al live, las cuentas sin nada pagado se cancelan y se avisa.

### Detalles técnicos que no hay que olvidar

- El webhook de entrada responde **al recibir** (`onReceived`). Si tardara más de 60 s, Evolution reintenta hasta 10 veces y se duplicarían respuestas.
- La idempotencia (`mensajes_procesados`) se comprueba **antes** de llamar a Gemini.
- Con "Webhook Base64" activo en Evolution, el archivo llega en `body.data.message.base64`.
- `sendMedia` de Evolution recibe el base64 **sin** prefijo `data:`; convierte imágenes a JPEG (un PNG transparente saldría negro).
- Los nodos Gemini tienen reintentos y `continueRegularOutput`: si Gemini falla, el caso cae en revisión en vez de romper el flujo.
- La BD guarda fechas en UTC; la operación es en `America/La_Paz` (n8n usa esa zona desde `docker-compose.yml`).
- n8n sirve las páginas de webhooks en un **sandbox** (sin `localStorage`): el panel guarda la clave en el enlace (`#k=…`).
- El navegador integrado de Claude no permite que esa página haga peticiones; para probar la interfaz se usa un proxy local que sirve `panel/panel.html` y reenvía `/webhook/*` a n8n.

## 7. Reglas de negocio implementadas

- **El precio nunca lo cambia el cliente** (D-14). La vendedora puede corregirlo desde el panel (no con pago reportado o pagado).
- **Nada se rechaza automáticamente y el sistema nunca acusa al cliente** (D-15). Mensajes neutros.
- **El pago confirmado siempre lo da la vendedora** (D-08), con el monto que vio en su banco.
- **Un "SÍ" confirma todas las compras pendientes** del cliente; una corrección de nombre se aplica a todas.
- **Deduplicación de capturas** de 30 min (D-17) y **una respuesta por mensaje** (D-18).
- **Live de respaldo** (D-21): sin live activo, la captura va al último live de hoy o a uno cerrado hace menos de 12 h; si no hubo, se crea uno de respaldo.
- **Cuenta diaria** por cliente + live (D-05); totales, saldo y estado los mantiene la base.
- **QR una vez por cuenta** (D-07), reenviable a pedido del cliente o desde el panel.
- **Pagos parciales** (D-20): un comprobante menor queda `parcial`; al confirmarlo, el monto se reparte entre las compras en orden de llegada.
- **Handoff**: cuando algo pasa a revisión, la vendedora toma la conversación y el bot calla; al devolverla al agente desde el panel, lo que estaba en revisión vuelve a `confirmada` y se envía el QR.
- **Vencimiento** (D-22): cuentas sin pago tras el plazo se cancelan; las que tienen pago parcial, comprobante pendiente, algo en revisión o cliente atendido por la vendedora **no** se cancelan.
- **Toda acción queda registrada** en `acciones_panel`.

## 8. Panel de control

- **Interfaz:** http://127.0.0.1:5678/webhook/panel (solo desde esta PC). Fuente: `panel/panel.html`; tras modificarla, ejecutar `db\cargar_panel.ps1`.
  - Barra del live: selector, iniciar/cerrar live e indicadores (vendido, cobrado, por cobrar, clientes, compras, por revisar).
  - **Tablero**: columnas Pendientes de pago / Por revisar / Pagadas (y canceladas o vencidas aparte). Las cuentas se arrastran entre columnas con confirmación.
  - **Detalle de cuenta**: cliente (nombre real, nicknames, control), comprobantes con "Confirmar pago…" (monto editable), compras con su captura, conversación de WhatsApp e historial.
  - **Compras**: lista y edición por compra. **Reporte**: resumen del live y descarga CSV.
- **API** (todas con header `X-Panel-Key`, credencial `panel-api-key`):

| Método y ruta (`/webhook/...`) | Uso |
|---|---|
| `GET panel/consulta?q=` `lives` · `cuentas&live_id=` · `cuenta&id=` · `captura_imagen&id=` · `reporte&live_id=` | Datos del tablero y detalle (`fn_panel_consulta`). |
| `POST panel/accion` `{accion, ...}` | `iniciar_live`, `cerrar_live`, `confirmar_pago {pago_id, monto}`, `cuenta_pagada {cuenta_id}`, `cuenta_revision {cuenta_id}`, `devolver_agente {cuenta_id o whatsapp, enviar_qr}`, `reenviar_qr`, `cliente_editar {whatsapp, nombre_real}` (`fn_panel_accion`). |
| `GET panel/resumen` · `panel/compras` · `panel/compra?id=` · `panel/comprobante?pago_id=` | Lecturas por compra. |
| `POST panel/compra/marcar-pagada` · `cambiar-estado` · `editar` | Acciones por compra. |

## 9. Estado de implementación vs. diseño

| Diseño | Estado |
|---|---|
| Lives, fecha operativa, regla de respaldo — D-05, D-06 | Hecho. |
| `cuenta_diaria` por `cliente_id + live_id` — D-05 | Hecho. |
| QR una vez por cuenta y reenvío a pedido — D-07 | Hecho (en borrador del adaptador de entrada hasta publicarlo). |
| Varios nicknames por cliente — D-02 | Hecho (`cuentas_tiktok`). |
| Nombre real / cliente provisional — D-03 | Se completa desde el panel; el bot aún no lo pregunta. |
| Handoff agente ↔ vendedora | Hecho. |
| Pagos parciales y `pagos_capturas` | Hecho. |
| Vencimiento automático | Hecho; el workflow `Vencimientos` está **apagado** hasta que la vendedora lo active. |
| Prueba de visión con 20 imágenes reales (M3) | Herramienta lista (`herramientas\probar_vision.ps1`); faltan las imágenes. |
| Panel desde el celular | Pendiente: requiere exponer n8n en la red (decisión de infraestructura). |
