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
