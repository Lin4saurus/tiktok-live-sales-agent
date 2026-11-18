// API falsa del panel para la demo en línea (Vercel).
// Reemplaza a n8n + PostgreSQL: intercepta fetch('/webhook/panel/...') y responde con datos de
// ejemplo guardados en memoria del navegador. Imita las respuestas de "Panel - API"
// (fn_panel_consulta / fn_panel_accion). Nada sale del navegador: no hay WhatsApp, ni Gemini,
// ni base de datos. Al recargar la página, la demo vuelve a empezar.
(() => {
  'use strict';

  // --- Utilidades de tiempo ---
  const AHORA = Date.now();
  const MIN = 60 * 1000;
  const iso = (ms) => new Date(ms).toISOString();
  const hoyBolivia = (ms = Date.now()) => new Date(ms - 4 * 60 * MIN).toISOString().slice(0, 10);
  const finDiaSiguiente = (fecha) => {
    const d = new Date(fecha + 'T23:59:59-04:00');
    return iso(d.getTime() + 24 * 60 * MIN);
  };

  // --- Datos de ejemplo ---
  const hoy = hoyBolivia(AHORA);
  const ayer = hoyBolivia(AHORA - 24 * 60 * MIN);
  const db = {
    version: 1,
    seq: { captura: 100, pago: 50 },
    lives: [
      { live_id: 'LIVE-' + ayer.replace(/-/g, '') + '-001', titulo: 'Live de carteras', fecha_operativa: ayer, estado: 'cerrado', origen: 'manual', inicio: iso(AHORA - 26 * 60 * MIN), cierre: iso(AHORA - 24 * 60 * MIN) },
      { live_id: 'LIVE-' + hoy.replace(/-/g, '') + '-001', titulo: 'Live de ropa', fecha_operativa: hoy, estado: 'activo', origen: 'manual', inicio: iso(AHORA - 50 * MIN), cierre: null },
    ],
    clientes: {},
    capturas: [],
    pagos: [],
    cuentas: {},     // datos propios de cada cuenta: qr_enviado_en, cerrada
    mensajes: {},    // whatsapp -> [{direccion, texto, tipo, fecha}]
    historial: {},   // cuenta_id -> [{accion, fecha, estado_anterior, estado_nuevo, detalle}]
  };
  const LIVE_AYER = db.lives[0].live_id;
  const LIVE_HOY = db.lives[1].live_id;

  function cliente(whatsapp, push_name, nombre_real = null) {
    db.clientes[whatsapp] = { whatsapp, push_name, nombre_real, control: 'agente' };
    db.mensajes[whatsapp] = [];
  }
  function msg(whatsapp, direccion, texto, minutosAtras, tipo = 'texto') {
    db.mensajes[whatsapp].push({ direccion, texto, tipo, fecha: iso(AHORA - minutosAtras * MIN) });
  }
  function captura(live_id, whatsapp, nickname, precio, estado, minutosAtras, extra = {}) {
    const c = { captura_id: 'CAP-' + (++db.seq.captura), live_id, whatsapp, nickname, precio, estado_captura: estado,
      fecha_recepcion: iso(AHORA - minutosAtras * MIN), confianza: 0.93, motivo_revision: null, ...extra };
    db.capturas.push(c);
    return c;
  }
  function pago(live_id, whatsapp, datos) {
    const p = { pago_id: 'PAG-' + (++db.seq.pago), cuenta_id: cuentaId(whatsapp, live_id), estado_pago: 'reportado', resultado: 'coincide',
      motivo_revision: null, monto_confirmado: null, fecha_verificacion: null, excedente: null, tiene_comprobante: true,
      receptor_comprobante: 'Maria Fernanda Rojas', banco_app: 'Yape', ...datos };
    if (p.tiene_comprobante && !p.fecha_comprobante) p.fecha_comprobante = horaLocal(Date.parse(p.fecha_recepcion) - 2 * MIN);
    db.pagos.push(p);
    return p;
  }
  function horaLocal(ms) {
    const d = new Date(ms), z = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())} ${z(d.getHours())}:${z(d.getMinutes())}`;
  }
  function cuentaId(whatsapp, live_id) { return 'CD-' + live_id.slice(5, 13) + '-' + whatsapp.slice(-4); }
  function datosCuenta(id) { return db.cuentas[id] || (db.cuentas[id] = { qr_enviado_en: null, cerrada: null }); }
  function registrar(cuenta_id, accion, detalle = {}, estado_anterior = null, estado_nuevo = null) {
    (db.historial[cuenta_id] ||= []).unshift({ accion, fecha: iso(Date.now()), estado_anterior, estado_nuevo, detalle });
  }

  // Clientes de ejemplo (nombres y números inventados).
  cliente('59171234501', 'Fri Cosi', 'Fricosi Mamani');
  cliente('59172345602', 'Lu ✨', null);
  cliente('59173456703', 'Carla R.', 'Carla Rodríguez');
  cliente('59174567804', 'Pao', null);
  cliente('59175678905', 'Don Jorge', 'Jorge Quispe');
  cliente('59176789006', 'Vane', 'Vanessa Flores');
  cliente('59177890107', 'Mili', null);

  // Live de hoy
  captura(LIVE_HOY, '59171234501', 'fricosi_bo', 10, 'confirmada', 44);
  captura(LIVE_HOY, '59171234501', 'fricosi_bo', 35, 'confirmada', 31);
  msg('59171234501', 'entrante', '', 44, 'imagen');
  msg('59171234501', 'saliente', '¡Hola Fricosi! 🛍️ Registré tu compra: fricosi_bo · 10 Bs. ¿Es correcto? Responde SÍ o NO.', 44);
  msg('59171234501', 'entrante', 'si', 43);
  msg('59171234501', 'entrante', '', 31, 'imagen');
  msg('59171234501', 'saliente', 'Anoté otra compra: fricosi_bo · 35 Bs. Tu total de hoy es 45 Bs. Al cerrar el live te mando el QR para pagar.', 31);
  datosCuenta(cuentaId('59171234501', LIVE_HOY));

  captura(LIVE_HOY, '59172345602', 'lu.compras', 50, 'pago_reportado', 40);
  msg('59172345602', 'entrante', '', 40, 'imagen');
  msg('59172345602', 'saliente', 'Registré tu compra: lu.compras · 50 Bs. ¿Es correcto? Responde SÍ o NO.', 40);
  msg('59172345602', 'entrante', 'sí, ya te pago', 39);
  msg('59172345602', 'saliente', 'Gracias 💛 Este es tu QR para pagar 50 Bs. Envíame el comprobante cuando pagues.', 38);
  msg('59172345602', 'entrante', '', 12, 'imagen');
  datosCuenta(cuentaId('59172345602', LIVE_HOY)).qr_enviado_en = iso(AHORA - 38 * MIN);
  pago(LIVE_HOY, '59172345602', { monto_pagado: 50, monto_esperado: 50, enviado_por: 'Lucia Vargas', referencia_pago: '00483921', fecha_recepcion: iso(AHORA - 12 * MIN) });

  captura(LIVE_HOY, '59173456703', 'carlita_r', 80, 'requiere_revision', 25);
  msg('59173456703', 'entrante', '', 25, 'imagen');
  msg('59173456703', 'saliente', 'Registré tu compra: carlita_r · 80 Bs. ¿Es correcto? Responde SÍ o NO.', 25);
  msg('59173456703', 'entrante', '', 9, 'imagen');
  datosCuenta(cuentaId('59173456703', LIVE_HOY)).qr_enviado_en = iso(AHORA - 24 * MIN);
  db.clientes['59173456703'].control = 'humano';
  pago(LIVE_HOY, '59173456703', { monto_pagado: 50, monto_esperado: 80, estado_pago: 'requiere_revision', resultado: 'revision',
    motivo_revision: 'referencia_duplicada', enviado_por: 'Lucia Vargas', referencia_pago: '00483921', fecha_recepcion: iso(AHORA - 9 * MIN) });
  db.capturas[db.capturas.length - 1].motivo_revision = 'referencia_duplicada';

  captura(LIVE_HOY, '59174567804', 'pao.style', 25, 'nueva', 4);
  msg('59174567804', 'entrante', '', 4, 'imagen');
  msg('59174567804', 'saliente', 'Registré tu compra: pao.style · 25 Bs. ¿Es correcto? Responde SÍ o NO.', 4);

  captura(LIVE_HOY, '59175678905', 'jorgeq', 120, 'pagada', 47);
  msg('59175678905', 'entrante', '', 47, 'imagen');
  msg('59175678905', 'saliente', 'Registré tu compra: jorgeq · 120 Bs. ¿Es correcto? Responde SÍ o NO.', 47);
  msg('59175678905', 'entrante', 'Correcto', 46);
  msg('59175678905', 'saliente', 'Este es tu QR para pagar 120 Bs.', 46);
  msg('59175678905', 'entrante', '', 30, 'imagen');
  msg('59175678905', 'saliente', '¡Pago confirmado! ✅ Gracias por tu compra, Jorge.', 20);
  datosCuenta(cuentaId('59175678905', LIVE_HOY)).qr_enviado_en = iso(AHORA - 46 * MIN);
  pago(LIVE_HOY, '59175678905', { monto_pagado: 120, monto_esperado: 120, estado_pago: 'verificado', monto_confirmado: 120, fecha_verificacion: iso(AHORA - 20 * MIN),
    enviado_por: 'Jorge Quispe', referencia_pago: '77120455', banco_app: 'BNB', fecha_recepcion: iso(AHORA - 30 * MIN) });
  registrar(cuentaId('59175678905', LIVE_HOY), 'confirmar_pago', { monto_confirmado: 120 }, 'pago_reportado', 'pagada');

  // Live de ayer (cerrado): una cuenta con pago parcial y una vencida.
  captura(LIVE_AYER, '59176789006', 'vane.flores', 90, 'confirmada', 25 * 60);
  captura(LIVE_AYER, '59176789006', 'vane.flores', 40, 'confirmada', 25 * 60 - 20);
  msg('59176789006', 'entrante', '', 25 * 60, 'imagen');
  msg('59176789006', 'saliente', 'Tu total del live es 130 Bs. Aquí tienes tu QR.', 24 * 60);
  msg('59176789006', 'entrante', 'te pago la mitad hoy y lo demás mañana', 23 * 60);
  datosCuenta(cuentaId('59176789006', LIVE_AYER)).qr_enviado_en = iso(AHORA - 24 * 60 * MIN);
  pago(LIVE_AYER, '59176789006', { monto_pagado: 70, monto_esperado: 130, estado_pago: 'verificado', resultado: 'parcial', monto_confirmado: 70,
    fecha_verificacion: iso(AHORA - 22 * 60 * MIN), enviado_por: 'Vanessa Flores', referencia_pago: '55102233', fecha_recepcion: iso(AHORA - 23 * 60 * MIN) });

  captura(LIVE_AYER, '59177890107', 'mili_bo', 30, 'cancelada', 25 * 60 - 40);
  msg('59177890107', 'entrante', '', 25 * 60 - 40, 'imagen');
  msg('59177890107', 'entrante', 'ya no lo quiero, disculpa', 25 * 60 - 30);
  datosCuenta(cuentaId('59177890107', LIVE_AYER)).cerrada = 'cancelada';
  registrar(cuentaId('59177890107', LIVE_AYER), 'cancelada_por_cliente', { mensaje_cliente: 'ya no lo quiero, disculpa' }, 'nueva', 'cancelada');

  // --- Cálculos (lo que en la base hacen las vistas y funciones) ---
  const r2 = (n) => Math.round(Number(n) * 100) / 100;
  function cuentasIds(live_id) {
    const ids = [];
    db.capturas.forEach((c) => { if (c.live_id === live_id) { const id = cuentaId(c.whatsapp, live_id); if (!ids.includes(id)) ids.push(id); } });
    return ids;
  }
  function calcularCuenta(id) {
    const caps = db.capturas.filter((c) => cuentaId(c.whatsapp, c.live_id) === id);
    if (!caps.length) return null;
    const { whatsapp, live_id } = caps[0];
    const live = db.lives.find((l) => l.live_id === live_id);
    const cl = db.clientes[whatsapp];
    const propios = datosCuenta(id);
    const activas = caps.filter((c) => c.estado_captura !== 'cancelada');
    const pagos = db.pagos.filter((p) => p.cuenta_id === id);
    const subtotal = r2(activas.reduce((s, c) => s + Number(c.precio), 0));
    const monto_confirmado = r2(pagos.filter((p) => p.estado_pago === 'verificado').reduce((s, p) => s + Number(p.monto_confirmado || 0), 0));
    const saldo = r2(Math.max(0, subtotal - monto_confirmado));
    let estado = 'abierta';
    if (propios.cerrada || !activas.length) estado = propios.cerrada || 'cancelada';
    else if (saldo === 0) estado = 'pagada';
    else if (monto_confirmado > 0) estado = 'parcial';
    const pendiente = pagos.find((p) => p.estado_pago !== 'verificado') || null;
    const en_revision = activas.filter((c) => c.estado_captura === 'requiere_revision').length;
    const motivos = [...new Set([...pagos.filter((p) => p.estado_pago !== 'verificado').map((p) => p.motivo_revision),
      ...activas.map((c) => c.motivo_revision)].filter(Boolean).flatMap((m) => m.split(',')))].join(',');
    let columna = 'pendientes';
    if (estado === 'cancelada' || estado === 'vencida') columna = 'cerradas';
    else if (estado === 'pagada') columna = 'pagadas';
    else if (en_revision > 0 || pendiente || cl.control === 'humano') columna = 'revision';
    const nicks = [...new Set(caps.map((c) => c.nickname).filter(Boolean))];
    return {
      cuenta_id: id, live_id, whatsapp, fecha_operativa: live.fecha_operativa, fecha_limite_pago: finDiaSiguiente(live.fecha_operativa),
      cliente: cl.nombre_real || cl.push_name, nicknames: nicks.join(', '), compras: activas.length, control: cl.control,
      subtotal, monto_confirmado, saldo, estado, columna, en_revision, motivos: motivos || null, qr_enviado_en: propios.qr_enviado_en,
      pago_por_verificar: !!pendiente, pago_pendiente: pendiente ? { pago_id: pendiente.pago_id, monto_pagado: pendiente.monto_pagado, fecha_recepcion: pendiente.fecha_recepcion } : null,
    };
  }
  function calcularLive(l) {
    const cuentas = cuentasIds(l.live_id).map(calcularCuenta).filter(Boolean);
    const vivas = cuentas.filter((c) => c.columna !== 'cerradas');
    return { ...l,
      vendido: r2(vivas.reduce((s, c) => s + c.subtotal, 0)),
      cobrado: r2(vivas.reduce((s, c) => s + c.monto_confirmado, 0)),
      pendiente: r2(vivas.reduce((s, c) => s + c.saldo, 0)),
      clientes: vivas.length,
      compras: vivas.reduce((s, c) => s + c.compras, 0),
      cuentas_en_revision: cuentas.filter((c) => c.columna === 'revision').length,
      cuentas_pagadas: cuentas.filter((c) => c.estado === 'pagada').length,
    };
  }
  function totalCliente(whatsapp) {
    const ids = [...new Set(db.capturas.filter((c) => c.whatsapp === whatsapp).map((c) => cuentaId(c.whatsapp, c.live_id)))];
    return r2(ids.map(calcularCuenta).filter((c) => c && c.columna !== 'cerradas').reduce((s, c) => s + c.saldo, 0));
  }
  // Los estados de las compras siguen a la cuenta (como los triggers de la base).
  function sincronizar(id) {
    const c = calcularCuenta(id);
    if (!c) return;
    const pp = db.pagos.find((p) => p.cuenta_id === id && p.estado_pago === 'reportado');
    db.capturas.filter((x) => cuentaId(x.whatsapp, x.live_id) === id).forEach((x) => {
      if (x.estado_captura === 'cancelada' || x.estado_captura === 'requiere_revision') return;
      if (c.estado === 'pagada') x.estado_captura = 'pagada';
      else if (pp && x.estado_captura === 'confirmada') x.estado_captura = 'pago_reportado';
    });
  }
  const cambio = () => { db.version++; };

  // --- Imágenes de ejemplo (SVG dibujado aquí, sin fotos reales) ---
  const b64 = (s) => btoa(unescape(encodeURIComponent(s)));
  function svgCaptura(c) {
    return b64(`<svg xmlns="http://www.w3.org/2000/svg" width="360" height="640" viewBox="0 0 360 640">
      <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b2a4a"/><stop offset="1" stop-color="#1b1424"/></linearGradient></defs>
      <rect width="360" height="640" fill="url(#g)"/>
      <rect x="14" y="16" rx="12" width="96" height="26" fill="#fe2c55"/><text x="62" y="34" font-family="sans-serif" font-size="14" fill="#fff" text-anchor="middle" font-weight="700">LIVE</text>
      <text x="124" y="34" font-family="sans-serif" font-size="13" fill="#ddd">👁 1.2K</text>
      <rect x="80" y="210" rx="18" width="200" height="230" fill="#c9a27e"/><rect x="120" y="180" rx="10" width="120" height="50" fill="none" stroke="#8a6a4f" stroke-width="10"/>
      <rect x="105" y="290" width="150" height="70" rx="6" fill="#fffbe8" transform="rotate(-4 180 325)"/>
      <text x="180" y="338" font-family="'Comic Sans MS','Segoe Print',cursive" font-size="30" fill="#1b3a8a" text-anchor="middle" transform="rotate(-4 180 325)">${c.nickname.split(/[._]/)[0]} ${c.precio}</text>
      <text x="20" y="560" font-family="sans-serif" font-size="14" fill="#fff" font-weight="700">${c.nickname}</text>
      <text x="20" y="582" font-family="sans-serif" font-size="13" fill="#ccc">¡lo quiero! 🙋‍♀️</text>
      <text x="180" y="625" font-family="sans-serif" font-size="11" fill="#999" text-anchor="middle">Imagen de ejemplo · demo</text></svg>`);
  }
  function svgComprobante(p) {
    return b64(`<svg xmlns="http://www.w3.org/2000/svg" width="360" height="560" viewBox="0 0 360 560">
      <rect width="360" height="560" fill="#f4f1fb"/><rect x="20" y="20" width="320" height="520" rx="16" fill="#fff" stroke="#ddd"/>
      <circle cx="180" cy="90" r="34" fill="#742284"/><text x="180" y="100" font-family="sans-serif" font-size="26" fill="#fff" text-anchor="middle">✓</text>
      <text x="180" y="160" font-family="sans-serif" font-size="16" fill="#555" text-anchor="middle">¡Yapeaste!</text>
      <text x="180" y="205" font-family="sans-serif" font-size="36" fill="#222" text-anchor="middle" font-weight="700">Bs ${p.monto_pagado}</text>
      <text x="40" y="270" font-family="sans-serif" font-size="13" fill="#888">Para</text><text x="40" y="290" font-family="sans-serif" font-size="15" fill="#222">${p.receptor_comprobante}</text>
      <text x="40" y="330" font-family="sans-serif" font-size="13" fill="#888">De</text><text x="40" y="350" font-family="sans-serif" font-size="15" fill="#222">${p.enviado_por}</text>
      <text x="40" y="390" font-family="sans-serif" font-size="13" fill="#888">Nro. de operación</text><text x="40" y="410" font-family="sans-serif" font-size="15" fill="#222">${p.referencia_pago}</text>
      <text x="40" y="450" font-family="sans-serif" font-size="13" fill="#888">Fecha</text><text x="40" y="470" font-family="sans-serif" font-size="15" fill="#222">${p.fecha_comprobante}</text>
      <text x="180" y="525" font-family="sans-serif" font-size="11" fill="#999" text-anchor="middle">Comprobante de ejemplo · demo</text></svg>`);
  }

  // --- Respuestas de la API ---
  const ok = (o = {}) => ({ ok: true, ...o });
  const error = (e) => ({ ok: false, error: e });

  function consulta(p) {
    const q = p.get('q');
    if (q === 'version') return ok({ version: db.version });
    if (q === 'lives') {
      const lives = db.lives.map(calcularLive).sort((a, b) => b.inicio.localeCompare(a.inicio));
      return ok({ lives, activo: db.lives.find((l) => l.estado === 'activo')?.live_id || null });
    }
    if (q === 'cuentas') {
      const l = db.lives.find((x) => x.live_id === p.get('live_id')) || db.lives[db.lives.length - 1];
      return ok({ live: calcularLive(l), cuentas: cuentasIds(l.live_id).map(calcularCuenta).filter(Boolean) });
    }
    if (q === 'cuenta') {
      const c = calcularCuenta(p.get('id'));
      if (!c) return error('cuenta_no_encontrada');
      const cl = db.clientes[c.whatsapp];
      const caps = db.capturas.filter((x) => cuentaId(x.whatsapp, x.live_id) === c.cuenta_id);
      const todas = db.capturas.filter((x) => x.whatsapp === c.whatsapp);
      const nick = {};
      todas.forEach((x) => { if (x.nickname) nick[x.nickname] = (nick[x.nickname] || 0) + 1; });
      const pagos = db.pagos.filter((x) => x.cuenta_id === c.cuenta_id).map((x) => {
        const o = { ...x };
        if (String(x.motivo_revision || '').includes('referencia_duplicada')) {
          const otro = db.pagos.find((y) => y.pago_id !== x.pago_id && y.referencia_pago === x.referencia_pago);
          if (otro) {
            const oc = db.clientes[db.capturas.find((k) => cuentaId(k.whatsapp, k.live_id) === otro.cuenta_id).whatsapp];
            o.referencia_repetida = { cliente: oc.nombre_real || oc.push_name, whatsapp: oc.whatsapp, monto_pagado: otro.monto_pagado,
              fecha_recepcion: otro.fecha_recepcion, estado_pago: otro.estado_pago, mismo_cliente: oc.whatsapp === c.whatsapp };
          }
        }
        return o;
      });
      return ok({
        cuenta: c,
        cliente: { ...cl, nicknames: Object.entries(nick).map(([nickname, capturas]) => ({ nickname, capturas })), total_a_pagar: totalCliente(c.whatsapp) },
        pagos,
        mensajes: db.mensajes[c.whatsapp],
        capturas: caps.map((x) => ({ ...x, tiene_imagen: true, confirmado: x.estado_captura === 'pagada' ? x.precio : 0 })),
        historial: db.historial[c.cuenta_id] || [],
      });
    }
    if (q === 'captura_imagen') {
      const c = db.capturas.find((x) => x.captura_id === p.get('id'));
      return c ? ok({ imagen_base64: svgCaptura(c), mime_type: 'image/svg+xml' }) : error('sin_imagen');
    }
    if (q === 'reporte') return consulta(new URLSearchParams({ q: 'cuentas', live_id: p.get('live_id') || '' }));
    return error('consulta_desconocida');
  }

  function cuentaDe(body) {
    if (body.cuenta_id) return calcularCuenta(body.cuenta_id);
    const cap = [...db.capturas].reverse().find((x) => x.whatsapp === body.whatsapp);
    return cap ? calcularCuenta(cuentaId(cap.whatsapp, cap.live_id)) : null;
  }
  function avisar(whatsapp, texto) { db.mensajes[whatsapp].push({ direccion: 'saliente', texto, tipo: 'texto', fecha: iso(Date.now()) }); }
  function enviarQR(c) {
    datosCuenta(c.cuenta_id).qr_enviado_en = iso(Date.now());
    const total = totalCliente(c.whatsapp);
    avisar(c.whatsapp, `Este es tu QR para pagar ${total} Bs. Envíame el comprobante cuando pagues. 💛`);
    db.mensajes[c.whatsapp].push({ direccion: 'saliente', texto: '', tipo: 'imagen', fecha: iso(Date.now()) });
    return total;
  }

  function accion(b) {
    const nota = b.nota ? { nota: b.nota } : {};
    switch (b.accion) {
      case 'iniciar_live': {
        if (db.lives.some((l) => l.estado === 'activo')) return error('ya_hay_un_live_activo');
        const fecha = hoyBolivia();
        const n = db.lives.filter((l) => l.fecha_operativa === fecha).length + 1;
        const live = { live_id: 'LIVE-' + fecha.replace(/-/g, '') + '-' + String(n).padStart(3, '0'), titulo: b.titulo || 'Live', fecha_operativa: fecha,
          estado: 'activo', origen: 'manual', inicio: iso(Date.now()), cierre: null };
        db.lives.push(live);
        cambio();
        return ok({ live });
      }
      case 'cerrar_live': {
        const l = db.lives.find((x) => x.estado === 'activo');
        if (!l) return error('no_hay_live_activo');
        l.estado = 'cerrado'; l.cierre = iso(Date.now());
        cambio();
        return ok({ live: l });
      }
      case 'confirmar_pago_cuenta':
      case 'confirmar_pago':
      case 'cuenta_pagada': {
        let p = b.pago_id ? db.pagos.find((x) => x.pago_id === b.pago_id) : null;
        const c = p ? calcularCuenta(p.cuenta_id) : cuentaDe(b);
        if (!c) return error('cuenta_no_encontrada');
        if (p && p.estado_pago === 'verificado') return error('pago_ya_verificado');
        if (c.saldo <= 0) return error('sin_saldo_pendiente');
        const monto = r2(b.monto ?? c.saldo);
        if (!(monto > 0)) return error('monto_requerido');
        p ||= db.pagos.find((x) => x.cuenta_id === c.cuenta_id && x.estado_pago !== 'verificado');
        if (!p) p = pago(c.live_id, c.whatsapp, { monto_pagado: monto, monto_esperado: c.saldo, resultado: 'manual', tiene_comprobante: false });
        Object.assign(p, { estado_pago: 'verificado', monto_confirmado: monto, fecha_verificacion: iso(Date.now()), excedente: monto > c.saldo ? r2(monto - c.saldo) : null });
        db.capturas.filter((x) => cuentaId(x.whatsapp, x.live_id) === c.cuenta_id && x.estado_captura === 'requiere_revision').forEach((x) => { x.estado_captura = 'confirmada'; x.motivo_revision = null; });
        sincronizar(c.cuenta_id);
        const d = calcularCuenta(c.cuenta_id);
        registrar(c.cuenta_id, 'confirmar_pago', { monto_confirmado: monto, ...nota }, c.estado, d.estado);
        if (b.notificar_cliente !== false) avisar(c.whatsapp, d.saldo > 0 ? `Recibimos ${monto} Bs. ✅ Te falta pagar ${d.saldo} Bs.` : '¡Pago confirmado! ✅ Gracias por tu compra.');
        cambio();
        return ok({ saldo_pendiente: d.saldo });
      }
      case 'cuenta_revision': {
        const c = cuentaDe(b);
        if (!c) return error('cuenta_no_encontrada');
        db.clientes[c.whatsapp].control = 'humano';
        registrar(c.cuenta_id, 'tomar_conversacion', nota);
        cambio();
        return ok();
      }
      case 'devolver_agente': {
        const c = cuentaDe(b);
        if (!c) return error('cliente_no_encontrado');
        db.clientes[c.whatsapp].control = 'agente';
        db.capturas.filter((x) => cuentaId(x.whatsapp, x.live_id) === c.cuenta_id && x.estado_captura === 'requiere_revision').forEach((x) => { x.estado_captura = 'confirmada'; x.motivo_revision = null; });
        db.pagos.filter((x) => x.cuenta_id === c.cuenta_id && x.estado_pago === 'requiere_revision').forEach((x) => { x.estado_pago = 'reportado'; });
        registrar(c.cuenta_id, 'devolver_agente', nota);
        let total = totalCliente(c.whatsapp), qr = false;
        if (b.enviar_qr && total > 0) { total = enviarQR(c); qr = true; }
        cambio();
        return ok({ qr_enviado: qr, total_a_pagar: total });
      }
      case 'reenviar_qr': {
        const c = cuentaDe(b);
        if (!c) return error('cuenta_no_encontrada');
        enviarQR(c);
        registrar(c.cuenta_id, 'reenviar_qr', nota);
        cambio();
        return ok();
      }
      case 'cliente_editar': {
        const cl = db.clientes[b.whatsapp];
        if (!cl) return error('cliente_no_encontrado');
        cl.nombre_real = String(b.nombre_real || '').trim() || null;
        cambio();
        return ok();
      }
    }
    return error('accion_desconocida');
  }

  const ESTADOS = ['requiere_revision', 'pago_reportado', 'confirmada', 'nueva', 'pagada', 'cancelada'];
  function rutaGet(ruta, p) {
    if (ruta === '/consulta') return consulta(p);
    if (ruta === '/resumen') {
      const r = { total: db.capturas.length };
      ESTADOS.forEach((e) => { r[e] = db.capturas.filter((c) => c.estado_captura === e).length; });
      return ok(r);
    }
    if (ruta === '/compras') {
      const e = p.get('estado');
      return ok({ compras: db.capturas.filter((c) => !e || c.estado_captura === e).sort((a, b) => b.fecha_recepcion.localeCompare(a.fecha_recepcion)) });
    }
    if (ruta === '/compra') {
      const c = db.capturas.find((x) => x.captura_id === p.get('id'));
      return c ? ok({ compra: c }) : error('compra_no_encontrada');
    }
    if (ruta === '/comprobante') {
      const x = db.pagos.find((y) => y.pago_id === p.get('pago_id'));
      return x && x.tiene_comprobante ? ok({ comprobante_base64: svgComprobante(x), mime_type: 'image/svg+xml', tipo: 'imagen' }) : error('sin_comprobante');
    }
    return null;
  }
  function rutaPost(ruta, b) {
    if (ruta === '/accion') return accion(b);
    if (ruta === '/compra/marcar-pagada') {
      const caps = db.capturas.filter((c) => (b.ids || []).includes(c.captura_id));
      if (caps.some((c) => c.estado_captura === 'cancelada')) return { ok: false, no_permitidas: caps.filter((c) => c.estado_captura === 'cancelada').map((c) => c.captura_id) };
      caps.forEach((c) => {
        const id = cuentaId(c.whatsapp, c.live_id);
        const antes = c.estado_captura;
        pago(c.live_id, c.whatsapp, { monto_pagado: c.precio, monto_esperado: c.precio, resultado: 'manual', tiene_comprobante: false,
          estado_pago: 'verificado', monto_confirmado: c.precio, fecha_verificacion: iso(Date.now()) });
        c.estado_captura = 'pagada'; c.motivo_revision = null;
        registrar(id, 'marcar_pagada', b.nota ? { nota: b.nota } : {}, antes, 'pagada');
        if (b.notificar_cliente) avisar(c.whatsapp, `Tu compra ${c.nickname} · ${c.precio} Bs quedó pagada. ✅`);
        sincronizar(id);
      });
      cambio();
      return ok();
    }
    if (ruta === '/compra/cambiar-estado') {
      const c = db.capturas.find((x) => x.captura_id === b.id);
      if (!c) return error('compra_no_encontrada');
      if (!['confirmada', 'requiere_revision', 'nueva', 'cancelada'].includes(b.estado) || b.estado === c.estado_captura) return error('estado_no_permitido');
      const antes = c.estado_captura;
      const id = cuentaId(c.whatsapp, c.live_id);
      if (antes === 'pagada') db.pagos.filter((p) => p.cuenta_id === id && p.estado_pago === 'verificado').forEach((p) => { p.estado_pago = 'reportado'; p.monto_confirmado = null; p.fecha_verificacion = null; });
      c.estado_captura = b.estado;
      if (b.estado !== 'requiere_revision') c.motivo_revision = null;
      if (b.estado === 'cancelada' && !db.capturas.some((x) => cuentaId(x.whatsapp, x.live_id) === id && x.estado_captura !== 'cancelada')) datosCuenta(id).cerrada = 'cancelada';
      if (b.estado !== 'cancelada') datosCuenta(id).cerrada = null;
      registrar(id, 'cambiar_estado', b.nota ? { nota: b.nota } : {}, antes, b.estado);
      cambio();
      return ok({ estado_nuevo: b.estado });
    }
    if (ruta === '/compra/editar') {
      const c = db.capturas.find((x) => x.captura_id === b.id);
      if (!c) return error('compra_no_encontrada');
      const nick = String(b.nickname || '').trim();
      const precio = String(b.precio ?? '').replace(',', '.').trim();
      if (!nick && !precio) return error('nada_que_editar');
      let hubo = false;
      if (precio) {
        if (['pago_reportado', 'pagada'].includes(c.estado_captura)) return error('precio_bloqueado');
        if (!/^\d+(\.\d{1,2})?$/.test(precio) || Number(precio) <= 0) return error('precio_invalido');
        if (Number(precio) !== Number(c.precio)) { c.precio = Number(precio); hubo = true; }
      }
      if (nick && nick !== c.nickname) { c.nickname = nick; hubo = true; }
      if (hubo) { registrar(cuentaId(c.whatsapp, c.live_id), 'editar', {}); cambio(); }
      return ok({ cambio: hubo });
    }
    return null;
  }

  // --- Simulación del live: llegan compras nuevas por WhatsApp mientras miras ---
  const LLEGADAS = [
    ['59178901208', 'Ana Belén', 'anabelen.bo', 45],
    ['59174567804', null, 'pao.style', 60],
    ['59179012309', 'Rocío', 'rocio_compras', 35],
    ['59171234501', null, 'fricosi_bo', 20],
    ['59170123410', 'Kathy', 'kathy.lpz', 70],
    ['59172345602', null, 'lu.compras', 15],
  ];
  let llegada = 0;
  function simular() {
    const live = db.lives.find((l) => l.estado === 'activo');
    if (live && llegada < LLEGADAS.length) {
      const [wa, nombre, nick, precio] = LLEGADAS[llegada++];
      if (!db.clientes[wa]) cliente(wa, nombre);
      const c = captura(live.live_id, wa, nick, precio, 'nueva', 0);
      db.mensajes[wa].push({ direccion: 'entrante', texto: '', tipo: 'imagen', fecha: iso(Date.now()) });
      avisar(wa, `Registré tu compra: ${nick} · ${precio} Bs. ¿Es correcto? Responde SÍ o NO.`);
      cambio();
      // A los pocos segundos el cliente responde "sí" y la compra queda confirmada.
      setTimeout(() => {
        if (c.estado_captura !== 'nueva') return;
        db.mensajes[wa].push({ direccion: 'entrante', texto: 'sí', tipo: 'texto', fecha: iso(Date.now()) });
        c.estado_captura = 'confirmada';
        avisar(wa, 'Perfecto 🙌 Al cerrar el live te mando el QR con tu total.');
        cambio();
      }, 9000);
    }
    setTimeout(simular, 25000 + Math.random() * 15000);
  }
  setTimeout(simular, 15000);

  // --- Interceptar fetch ---
  const fetchOriginal = window.fetch.bind(window);
  const PREFIJO = '/webhook/panel';
  window.fetch = async (entrada, opciones = {}) => {
    const url = new URL(typeof entrada === 'string' ? entrada : entrada.url, location.href);
    if (url.origin !== location.origin || !url.pathname.startsWith(PREFIJO)) return fetchOriginal(entrada, opciones);
    const ruta = url.pathname.slice(PREFIJO.length);
    await new Promise((r) => setTimeout(r, 60 + Math.random() * 120));   // latencia de red simulada
    let r;
    try {
      r = (opciones.method || 'GET').toUpperCase() === 'POST'
        ? rutaPost(ruta, JSON.parse(opciones.body || '{}'))
        : rutaGet(ruta, url.searchParams);
    } catch (e) {
      console.error('[demo] error en la API falsa', e);
      r = error('error_demo');
    }
    if (!r) return new Response('No encontrado', { status: 404 });
    return new Response(JSON.stringify(r), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };

  // Entra directo, sin pedir la clave (cualquier clave sirve si se pulsa «Salir»).
  try { localStorage.setItem('panel_clave', 'demo'); } catch {
    if (!location.hash.includes('k=')) history.replaceState(null, '', '#k=demo');
  }
})();
