# CLAUDE.md — Contexto permanente del proyecto

> **Instrucción fija:** Antes de trabajar, lee siempre `TASK.md` y este archivo.
> Al terminar, actualiza `TASK.md` y añade una línea a `CHANGELOG.md`.

Idioma de trabajo: **español** (documentos, comentarios, mensajes de commit).

Documentos relacionados:
- `TASK.md` — tablero de milestones y foco actual.
- `DECISIONS.md` — decisiones de diseño ya cerradas (no se reabren sin nueva entrada).
- `DATA_MODEL.md` — esquema de datos.
- `CHANGELOG.md` — bitácora de cambios.

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

## 2. Stack y por qué

| Componente | Elección | Por qué |
|---|---|---|
| Orquestación | **n8n** (self-hosted en Docker, ver `docker-compose.yml`) | Flujos visuales fáciles de mostrar y mantener; nodos nativos para HTTP, webhooks, BD y LLMs; nodos Code en JavaScript para la lógica propia. |
| Lógica | **JavaScript** (nodos Code de n8n) | Lenguaje nativo de n8n; evita servicios extra para reglas de negocio. |
| Mensajería | **Evolution API** o **WhatsApp Cloud API** | Canal donde ya escriben los clientes. Evolution: rápido de montar para pruebas; Cloud API: oficial y estable para producción. Elección final pendiente. |
| Visión | **GPT-4o / Gemini / Claude** (modelo multimodal) | Leer capturas del live y comprobantes de pago; clasificar el tipo de imagen y devolver JSON estructurado. Se elegirá por precisión/costo. |
| Base de datos | **Base de datos relacional** (motor por definir) | El dominio es relacional (clientes, lives, cuentas, capturas, pagos) y requiere integridad y consultas por fecha/estado. |
| Panel de control | **Panel web + webhooks de n8n** | La vendedora revisa y confirma pagos; el panel dispara acciones en n8n vía webhooks. |

## 3. Glosario del dominio

- **live** — Transmisión en vivo de TikTok donde se venden productos. Tiene una fecha (su día) que define la `fecha_operativa` de todo lo que se vende en él.
- **captura** — Imagen (screenshot del live) que envía el cliente por WhatsApp con su nickname y el precio. **Una captura = un producto = una venta.** La venta se crea al llegar la captura.
- **cuenta_diaria** — Cuenta de cobro que agrupa todas las capturas de un mismo cliente en un mismo live. Clave: `cliente_id + live_id` (no la fecha). Recibe un único QR de pago.
- **comprobante** — Imagen del pago (transferencia/QR) que el cliente envía. La IA la lee y precarga los datos; la vendedora confirma.
- **cliente provisional** — Cliente creado automáticamente al llegar su primer mensaje, identificado solo por su número de WhatsApp. Su nombre real se completa después, dentro de una conversación iniciada por el cliente.
- **fecha_operativa** — Día del live al que pertenece una venta/cuenta, independientemente de cuándo llegue la captura o el pago.
- **fecha_limite_pago** — Fin del día siguiente a la `fecha_operativa` (fin del día siguiente al live).

## 4. Convenciones de IDs

| Entidad | Formato | Ejemplo |
|---|---|---|
| Live | `LIVE-AAAAMMDD-NNN` | `LIVE-20260925-001` |
| Cuenta diaria | `CD-...` | `CD-...` *(formato exacto por completar desde diseño)* |
| Captura | `CAP-...` | `CAP-...` *(por completar)* |
| Pago | `P-...` | `P-...` *(por completar)* |

- `NNN` es un correlativo de 3 dígitos por día, empezando en `001`.
- Las fechas en IDs usan la `fecha_operativa`, no la fecha de recepción.

## 5. Regla de secretos

- **Credenciales y datos de clientes NUNCA van al repositorio.** Esto incluye API keys, tokens de WhatsApp, cadenas de conexión, números de teléfono, nombres, capturas y comprobantes reales.
- Los secretos van en `.env` (ignorado por git). `.env.example` solo lista las claves **vacías**.
- La carpeta `secrets/` y `n8n_data/` (clave de cifrado y BD interna de n8n con credenciales) están en `.gitignore`.
- Para pruebas, usar datos ficticios o anonimizados.
- Al exportar workflows de n8n, verificar que no incluyan credenciales ni datos reales antes de versionarlos.
