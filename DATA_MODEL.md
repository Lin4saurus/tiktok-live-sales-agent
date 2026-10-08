# DATA_MODEL.md — Modelo de datos

Esquema de la base de datos. Convenciones de IDs en `CLAUDE.md` §4; decisiones que
afectan al modelo en `DECISIONS.md`.

- Motor: **PostgreSQL 16** (contenedor `postgres`), base de datos **`ventas`**.
- Extensiones: `unaccent` y `fuzzystrmatch` (comparación flexible de nombres en la conciliación).
- Fechas: `timestamp without time zone` en **UTC** (`now()` del servidor). La operación es en
  **America/La_Paz**: `hoy_operativo()` da el día local y `fn_limite_pago()` el plazo en UTC.
- Importes: `numeric`, en Bs.

## Migraciones (`db/`)

| Archivo | Contenido |
|---|---|
| `001_esquema_inicial.sql` | Esquema al 2026-10-07 antes de lives/cuentas (clientes, capturas, pagos, configuracion_pago, mensajes_procesados, acciones_panel). |
| `002_lives_cuentas_pagos.sql` | Tablas `lives`, `cuentas_diarias`, `cuentas_tiktok`, `pagos_capturas`, `mensajes`; columnas nuevas; triggers; migración de datos existentes. |
| `003_funciones_negocio.sql` | `fn_registrar_pago`, `fn_confirmar_pago`, `fn_vencer_cuentas` y utilidades. |
| `004_panel.sql` | `fn_panel_consulta`, `fn_panel_accion`, columna del tablero e indicadores del live. |
| `005_panel_web.sql` | Tabla `panel_recursos` con la página web del panel. |

Instalación nueva: `init-db.sh` crea la base y luego `db\aplicar_migraciones.ps1 -Desde 1`.
002–005 son idempotentes. La página del panel se carga con `db\cargar_panel.ps1`.

## Relaciones

```
lives 1─┬─< cuentas_diarias >─1 clientes 1─< cuentas_tiktok
        │         1                1
        │         │                └─< mensajes (por whatsapp)
        └─< capturas >─────────────┘
                 1
                 └─< pagos_capturas >─1 pagos
```

## Lógica que vive en la base (triggers)

- **Al insertar una captura** (`capturas_antes_insert`): crea el cliente si no existe, asigna
  el live (`fn_live_para_captura`), la cuenta diaria (`fn_cuenta_para`) y la fecha operativa.
- **Después de cada cambio en capturas** (`capturas_despues`): recalcula la cuenta
  (`fn_recalcular_cuenta`), registra el nickname en `cuentas_tiktok` y, si la compra pasa a
  `requiere_revision`, pone el control del cliente en `humano`.
- **Pagos** (`pagos_despues`): un comprobante en `requiere_revision` pasa el control a `humano`;
  verificar un pago recalcula las cuentas de sus compras. `pagos_capturas_despues` también recalcula.

**Regla de respaldo del live** (`fn_live_para_captura`): 1) el live activo; 2) si no hay, el
último live de hoy o uno cerrado hace menos de 12 h; 3) si no hubo live, se crea uno de
respaldo para hoy (`origen = 'respaldo'`, cerrado).

---

## Tablas

### lives
| Columna | Tipo | Notas |
|---|---|---|
| `live_id` | text **PK** | `LIVE-AAAAMMDD-NNN`. |
| `fecha_operativa` | date NOT NULL | Día del live (hora de Bolivia). |
| `titulo` | text | Opcional. |
| `estado` | text NOT NULL | `activo` / `cerrado`. **Solo un live activo** (índice único parcial). |
| `origen` | text NOT NULL | `manual` (abierto en el panel) / `respaldo` (creado automáticamente). |
| `inicio`, `cierre` | timestamp | |

### clientes
Un cliente por número de WhatsApp (D-02, D-03).

| Columna | Tipo | Notas |
|---|---|---|
| `cliente_id` | text **PK** | Igual al `whatsapp`. |
| `whatsapp` | text NOT NULL **UNIQUE** | Solo dígitos, con código de país. |
| `nombre_real` | text | Si es NULL el cliente es **provisional** (D-03). Se completa desde el panel. |
| `push_name` | text | Nombre de perfil de WhatsApp. |
| `control` | text NOT NULL | `agente` (responde el bot) / `humano` (atiende la vendedora; el bot calla). |
| `control_desde` | timestamp | Último cambio de control. |
| `fecha_registro` | timestamp NOT NULL | |
| `notas` | text | |

### cuentas_tiktok
Nicknames usados por cada cliente (D-02). Nunca se fusionan automáticamente.

| Columna | Tipo | Notas |
|---|---|---|
| `cliente_id` + `nickname` | **PK** | |
| `primera_vez`, `ultima_vez` | timestamp | |
| `capturas` | int | Veces que se usó. |

### cuentas_diarias
Cuenta de cobro por cliente y live (D-05).

| Columna | Tipo | Notas |
|---|---|---|
| `cuenta_id` | text **PK** | `CD-AAAAMMDD-NNN-NNN` (live + correlativo en el live). |
| `cliente_id` | text NOT NULL | FK clientes. **UNIQUE (cliente_id, live_id)**. |
| `live_id` | text NOT NULL | FK lives. |
| `fecha_operativa` | date NOT NULL | La del live. |
| `fecha_limite_pago` | timestamp NOT NULL | Fin del día siguiente al live, en UTC (D-06). |
| `subtotal` | numeric | Suma de compras no canceladas (la mantiene el trigger). |
| `monto_confirmado` | numeric | Lo verificado por la vendedora. |
| `saldo` | numeric (generada) | `subtotal - monto_confirmado`. |
| `estado` | text | `abierta`, `parcial`, `pagada`, `cancelada`, `vencida`. |
| `qr_enviado_en` | timestamp | D-07: el QR se envía una vez por cuenta. |
| `vencida_en` | timestamp | Marcada por el vencimiento automático. |
| `fecha_creacion` | timestamp | |

### capturas
Una fila = una captura = una compra (D-04).

| Columna | Tipo | Notas |
|---|---|---|
| `captura_id` | text **PK** | UUID. |
| `whatsapp` | text NOT NULL | Cliente. |
| `live_id`, `cuenta_id`, `fecha_operativa` | | Asignados por el trigger. |
| `message_id` | text **UNIQUE** | Mensaje de WhatsApp que la trajo. |
| `nickname` | text | Leído por la IA; el cliente puede corregirlo. |
| `precio` | numeric | Leído por la IA. **El cliente no puede cambiarlo** (D-14). |
| `tipo_imagen` | text | `captura_live` / `desconocido` (D-09). |
| `confianza` | numeric | 0–1. |
| `imagen_base64` | text | Imagen original de la captura. |
| `estado_captura` | text NOT NULL | Ver estados. |
| `fecha_recepcion` | timestamp NOT NULL | |

**Estados:** `nueva` (espera confirmación) · `confirmada` (por pagar) · `requiere_revision` ·
`pago_reportado` (comprobante que cuadra, sin verificar) · `pagada` (solo la vendedora) ·
`cancelada` (vendedora o vencimiento).

### pagos
Un comprobante recibido (imagen o PDF).

| Columna | Tipo | Notas |
|---|---|---|
| `pago_id` | text **PK** | UUID. |
| `whatsapp` | text NOT NULL | |
| `message_id` | text **UNIQUE** | Un comprobante reentregado no se registra dos veces. |
| `monto_pagado` | numeric | Leído del comprobante. |
| `monto_esperado` | numeric | Lo que debía al recibirlo (saldo de sus compras confirmadas menos parciales sin verificar). |
| `monto_confirmado` | numeric | Lo que la vendedora vio en su banco. |
| `excedente` | numeric | Pagado de más. |
| `resultado` | text | `coincide` / `parcial` / `revision`. |
| `estado_pago` | text NOT NULL | `reportado` / `requiere_revision` / `verificado`. |
| `motivo_revision` | text | Banderas separadas por coma. |
| `capturas_ids` | text[] | Compras que cubría al llegar (histórico; la relación vigente está en `pagos_capturas`). |
| `referencia_pago`, `referencia_normalizada` | text | Para detectar referencias repetidas. |
| `enviado_por`, `receptor_comprobante`, `fecha_comprobante`, `banco_app` | text | Leídos del comprobante. |
| `confianza` | numeric | |
| `comprobante_base64` | text | Archivo original. |
| `fecha_recepcion`, `fecha_verificacion` | timestamp | |
| `notas` | text | |

**Resultado al llegar el comprobante (M7):** igual a lo que debe → `coincide` (`reportado`);
menor → `parcial` (`reportado`); mayor o con banderas → `revision` (`requiere_revision`).
**Banderas:** `referencia_duplicada`, `monto_mayor`, `receptor_distinto`,
`sin_compra_confirmada`, `comprobante_ilegible`. Nada se rechaza (D-15).

### pagos_capturas
| Columna | Tipo | Notas |
|---|---|---|
| `pago_id` + `captura_id` | **PK** | |
| `monto_aplicado` | numeric | Se fija al confirmar el pago: el monto se reparte en orden de llegada. |

### mensajes
Historial de la conversación (sin archivos).

| Columna | Tipo | Notas |
|---|---|---|
| `mensaje_id` | bigserial **PK** | |
| `message_id` | text | Único para los entrantes. |
| `whatsapp` | text NOT NULL | |
| `direccion` | text | `entrante` / `saliente`. |
| `tipo` | text | `texto`, `imagen`, `documento`… |
| `texto` | text | Texto o pie de foto. |
| `fecha` | timestamp | |

### configuracion_pago
| Columna | Tipo | Notas |
|---|---|---|
| `config_id` | text **PK** | La fila activa es `default`. |
| `metodo_pago`, `nombre_receptor` | text | `nombre_receptor` se usa para la bandera `receptor_distinto`. |
| `qr_base64` | text | Imagen del QR. |
| `instrucciones` | text | Pie del mensaje del QR. |
| `whatsapp_vendedora` | text | Número que recibe los avisos del sistema (vencimientos). |
| `activo`, `fecha_actualizacion` | | |

### mensajes_procesados
Idempotencia de mensajes entrantes: `message_id` **PK**, `whatsapp`, `fecha_recepcion`.

### acciones_panel
Auditoría de acciones de la vendedora y del sistema.

| Columna | Tipo | Notas |
|---|---|---|
| `accion_id` | bigserial **PK** | |
| `fecha` | timestamp | |
| `accion` | text | `marcar_pagada`, `cambiar_estado`, `editar`, `confirmar_pago`, `tomar_conversacion`, `devolver_agente`, `reenviar_qr`, `cliente_editar`, `iniciar_live`, `cerrar_live`, `vencimiento`. |
| `captura_id`, `pago_id`, `cuenta_id`, `whatsapp` | text | Según la acción. |
| `estado_anterior`, `estado_nuevo` | text | |
| `detalle` | jsonb | Nota, montos, valores anteriores/nuevos. |

### panel_recursos
Página web del panel: `nombre` **PK** (`panel.html`), `contenido`, `actualizado`.
Fuente en `panel/panel.html`.

## Funciones principales

| Función | Uso |
|---|---|
| `fn_registrar_pago(...)` | WA - Pagos: concilia y registra un comprobante. |
| `fn_confirmar_pago(pago_id, monto, nota, notificar)` | Panel: la vendedora confirma lo que vio en su banco (total o parcial). |
| `fn_vencer_cuentas()` | Workflow Vencimientos (cada hora). |
| `fn_panel_consulta(q, parametros)` | `GET /webhook/panel/consulta`. |
| `fn_panel_accion(body)` | `POST /webhook/panel/accion`. |
| `fn_total_a_pagar(whatsapp)` | Saldo de las compras confirmadas del cliente. |
| `fn_confirmado_captura(captura_id)` | Cuánto de una compra ya está verificado. |
