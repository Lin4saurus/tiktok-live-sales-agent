# DECISIONS.md — Decisiones de diseño cerradas

Estas decisiones están cerradas. Para cambiar una, añade una nueva entrada que la
reemplace (indicando "Reemplaza a D-XX") en lugar de editar la original.

---

### D-01 · 2026-09-25 — Se registran transacciones, no productos
No hay inventario, SKU ni control de stock. El sistema registra ventas (transacciones).

### D-02 · 2026-09-25 — Identidad anclada al número de WhatsApp
El cliente se identifica por su número de WhatsApp. Un cliente puede tener varios
nicknames de TikTok; los nicknames nunca se fusionan sin confirmación.

### D-03 · 2026-09-25 — Cliente nuevo entra como provisional
Un cliente nuevo se crea como provisional. Su nombre real se completa después, dentro
de una conversación que el propio cliente inició.

### D-04 · 2026-09-25 — Una captura = un producto
Cada captura representa un producto. La venta se crea en el momento en que llega la captura.

### D-05 · 2026-09-25 — Agrupación en cuenta_diaria por cliente + live
Las capturas del mismo cliente en el mismo live se agrupan en una `cuenta_diaria`.
Clave de agrupación: `cliente_id + live_id` (no la fecha).

### D-06 · 2026-09-25 — Fechas: operativa y límite de pago
`fecha_operativa` = día del live. Plazo de pago (`fecha_limite_pago`) = fin del día
siguiente al live. La fecha de recepción de la captura y la fecha de pago pueden ser
distintas entre sí y respecto a la `fecha_operativa`.

### D-07 · 2026-09-25 — QR enviado una sola vez por cuenta
El QR de pago se envía una sola vez por `cuenta_diaria`. Solo se reenvía si el cliente lo pide.

### D-08 · 2026-09-25 — La vendedora confirma el pago, no la IA
El estado "Pago confirmado" lo asigna la vendedora. La IA lee el comprobante y precarga
los datos, pero no valida que el dinero haya llegado.

### D-09 · 2026-09-25 — La IA de visión clasifica primero la imagen
El primer campo que devuelve la IA de visión es `tipo_imagen` (clasificación de la
imagen recibida), antes de extraer cualquier otro dato.

### D-10 · 2026-09-25 — Entregas y envíos fuera de alcance
La gestión de entregas y envíos queda fuera del alcance por ahora.

Handoff agente↔vendedora: cada conversación tiene un estado de control ('agente' / 'humano'). Cuando un caso va a revisión, el control pasa a 'humano' y el agente se silencia para ese cliente. La vendedora resuelve manualmente por WhatsApp y, desde el panel, devuelve el control al agente (que entonces envía el QR). Esto evita que el bot interfiera en la conversación humana.

> Nota (2026-10-07): D-11 y D-12 se citan en otras decisiones (D-13 menciona D-12, las
> fases de negocio) pero no están escritas en este archivo. Completarlas desde los
> documentos de diseño.

### D-13 · 2026-09-30 — Un sub-workflow por fase de negocio, nunca uno nuevo por cada cambio
Cuando se pida agregar un nodo, cambiar una configuración o corregir algo, SIEMPRE se
edita el workflow existente de esa fase, encadenando o modificando nodos DENTRO del mismo
workflow. NUNCA se crea un workflow nuevo para probar, inspeccionar o iterar. Solo se crea
un workflow nuevo cuando empieza una fase de negocio distinta (entrada, capturas, pagos,
delivery, vencimientos, etc.), según D-12.
El workflow de la fase de ENTRADA de WhatsApp es "WA - Adaptador de entrada (Evolution)".
Fases creadas hasta hoy: entrada, salida (envío reutilizable), pagos y panel (ver `CLAUDE.md` §6).

### D-14 · 2026-10-07 — El cliente nunca cambia el precio
El precio es el que leyó la IA de la captura (lo escribe la vendedora). El cliente solo
puede corregir su nombre/nickname. Si reclama el precio, la compra pasa a
`requiere_revision` y se le responde que el precio lo define la vendedora. Solo la
vendedora puede corregir un precio, desde el panel, y no cuando ya hay un pago reportado
o la compra está pagada.

### D-15 · 2026-10-07 — Nada se rechaza automáticamente y nunca se acusa al cliente
El agente no acusa al cliente de fraude ni afirma que un comprobante es falso. Nada
rechaza un pago automáticamente: todo lo sospechoso, ilegible o que no cuadra va a
`requiere_revision` con un mensaje neutro, y la vendedora decide. Complementa a D-08.

### D-16 · 2026-10-07 — Conciliación contra la suma de compras confirmadas
Un comprobante se compara con la suma de las compras `confirmada` del cliente. Si cuadra
y no tiene banderas, el pago queda `reportado` (pendiente de que la vendedora lo vea en su
banco), nunca "pagado". Banderas que llevan a revisión: `referencia_duplicada`,
`monto_no_coincide`, `receptor_distinto`, `sin_compra_confirmada`, `comprobante_ilegible`.
Mientras no existan cuentas diarias (D-05), esta suma hace de "cuenta" del cliente.

### D-17 · 2026-10-07 — Deduplicación de capturas
Si el mismo cliente envía otra captura con el mismo nickname y el mismo precio en menos
de 30 minutos, se considera repetida: se conserva la primera y no se responde de nuevo.

### D-18 · 2026-10-07 — Un mensaje recibido produce como máximo una respuesta
Cada mensaje de WhatsApp se procesa una sola vez (idempotencia por `message_id`,
verificada antes de llamar a la IA), aunque Evolution lo reentregue. Si el cliente escribe
cuando su compra ya está confirmada o en revisión (últimas 24 h), solo se responde que se
revisará con la vendedora, sin cambiar ningún estado.

### D-19 · 2026-10-07 — Panel de la vendedora sobre webhooks de n8n con clave
El panel usa n8n como backend: cada acción es un webhook del workflow `Panel - API`,
protegido con autenticación por header (`X-Panel-Key`, credencial de n8n). Ningún webhook
del panel queda abierto. La interfaz web la sirve el mismo workflow. Cada acción de la
vendedora queda registrada en `acciones_panel`.

### D-20 · 2026-10-07 — Pagos parciales (reemplaza parcialmente a D-16)
Siguiendo el M7 del diseño: un comprobante **menor** a lo que el cliente debe ya no es una
bandera de revisión, sino un pago `parcial` (estado `reportado`) y se le dice al cliente,
sin acusar, cuánto le faltaría. Un comprobante **mayor** sí va a revisión (bandera
`monto_mayor`, que reemplaza a `monto_no_coincide`). Al confirmar, la vendedora escribe el
monto que vio en su banco; se reparte entre las compras en orden de llegada (`pagos_capturas`):
las cubiertas pasan a `pagada` y la cuenta queda `parcial` con su saldo. Lo pagado de más
queda como `excedente`.

### D-21 · 2026-10-07 — Live de respaldo y formato de IDs
Si llega una captura y no hay un live activo, se asocia al último live del día operativo o
a uno cerrado hace menos de 12 horas (las capturas suelen llegar al terminar el live); si no
hubo ninguno, se crea un live de respaldo (`origen = 'respaldo'`). Solo puede haber un live
activo. IDs: `LIVE-AAAAMMDD-NNN` y cuenta diaria `CD-AAAAMMDD-NNN-NNN` (live + correlativo);
capturas y pagos conservan UUID.

### D-22 · 2026-10-07 — Qué cancela el vencimiento automático
Al pasar la `fecha_limite_pago` (D-06) se cancelan solo las cuentas **sin nada pagado**, y
se avisa al cliente con un mensaje neutro y a la vendedora con un resumen. No se cancelan
las cuentas con pago parcial (se avisan una vez a la vendedora), con un comprobante sin
verificar, con algo en revisión, ni las de clientes que la vendedora está atendiendo.

### D-23 · 2026-10-07 — Las reglas de datos viven en la base
La asignación de live y cuenta, los totales, el control agente/humano, la conciliación, la
confirmación de pagos, el vencimiento y las acciones del panel son funciones y triggers de
PostgreSQL (`db/`). Los workflows de n8n las llaman; así la regla se cumple igual venga el
cambio de WhatsApp o del panel. La página del panel también se guarda en la base
(`panel_recursos`) y su fuente está en `panel/panel.html`.

### D-24 · 2026-10-07 — Un "SÍ" confirma todas las compras pendientes
Si el cliente tiene varias compras sin confirmar, un "SÍ" (o una corrección de nombre) se
aplica a todas, y el QR (o el recordatorio, si ya lo recibió) indica el total a pagar.
Pendiente de validar por la vendedora en una prueba real por WhatsApp.