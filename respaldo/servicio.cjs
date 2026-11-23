// Servicio de respaldo de la base «ventas» (contenedor «respaldo-tiktok», ver n8n-host/docker-compose.yml).
// Mismas reglas que el respaldo del ERP Dulzura (D111):
//  - «Respaldar ahora» desde el panel y respaldo automático si el último tiene más de 20 h (se revisa cada hora).
//  - Archivo .sql.gz con la fecha en /respaldos (n8n-host\respaldos_tiktok) y retención escalonada: los
//    BACKUP_KEEP más recientes (30) + el último de cada día de los últimos 30 días + el último de cada mes de 12 meses.
//  - Copia al Gmail del negocio, a sí mismo, con una contraseña de aplicación de Google (16 letras). Se prueba con
//    Gmail antes de guardarla, se guarda solo en /config (fuera de la base) y nunca viaja dentro del respaldo.
//  - El verify_token de WhatsApp Cloud tampoco viaja en el respaldo.
// Usa node, pg y nodemailer de la imagen de n8n (NODE_PATH), así que no descarga ni instala nada.
// La API la llama el panel con su clave (X-Panel-Key), que se valida contra la API del panel en n8n.
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const { promisify } = require('node:util');
const { Client } = require('pg');

const PUERTO = Number(process.env.PUERTO || 5690);
const CARPETA = process.env.BACKUP_DIR || '/respaldos';
const CONFIG = path.join(process.env.CONFIG_DIR || '/config', 'correo.json');
const PANEL_URL = process.env.PANEL_URL || 'http://n8n:5678/webhook/panel';
const CARPETA_VISIBLE = process.env.CARPETA_VISIBLE || 'n8n-host\\respaldos_tiktok';
const HORAS = 20;
const PATRON = /^tiktok_ventas_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})(?:-(\d+))?\.sql\.gz$/;
// Datos sensibles que se vacían en la copia: [tabla, columna clave, valor de la clave, columna a vaciar].
const SECRETOS_FUERA_DEL_RESPALDO = [['configuracion_whatsapp', 'clave', 'verify_token', 'valor']];
const gzip = promisify(zlib.gzip);
const gunzip = promisify(zlib.gunzip);

const log = (...a) => console.log(new Date().toISOString(), ...a);
class ErrorVisible extends Error { constructor(estado, mensaje) { super(mensaje); this.estado = estado; } }

// ─── Respaldo de la base ───

const dos = (n) => String(n).padStart(2, '0');
const nombreParaFecha = (f) => `tiktok_ventas_${f.getFullYear()}-${dos(f.getMonth() + 1)}-${dos(f.getDate())}_${dos(f.getHours())}-${dos(f.getMinutes())}-${dos(f.getSeconds())}`;
const claveOrden = (archivo) => {
  const p = PATRON.exec(archivo);
  return `${p?.[1] ?? ''}_${p?.[2] ?? ''}#${String(Number(p?.[3] ?? 1)).padStart(3, '0')}`;
};
const ident = (s) => '"' + String(s).replace(/"/g, '""') + '"';
const literal = (s) => "'" + String(s).replace(/'/g, "''") + "'";

function conectar() {
  return new Client({
    host: process.env.PGHOST || 'postgres', port: Number(process.env.PGPORT || 5432),
    user: process.env.PGUSER || 'postgres', password: process.env.PGPASSWORD, database: process.env.PGDATABASE || 'ventas',
    application_name: 'respaldo-tiktok', statement_timeout: 120000,
  });
}

// Genera un .sql que se carga con psql: crea secuencias y tablas si faltan, vacía las tablas y vuelve a llenarlas.
// Para una base nueva, primero se aplican las migraciones de db/ (funciones y triggers); ver db/restaurar_respaldo.ps1.
async function volcarBase() {
  const db = conectar();
  await db.connect();
  try {
    // Una sola foto consistente de toda la base, aunque el panel y los workflows sigan escribiendo.
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const tablas = (await db.query(`
      SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') ORDER BY c.relname`)).rows;
    const secuencias = (await db.query(`
      SELECT sequencename, data_type, start_value, increment_by, last_value
      FROM pg_sequences WHERE schemaname = 'public' ORDER BY 1`)).rows;
    const fecha = new Date();
    const partes = [
      `-- Respaldo de la base «ventas» del panel de ventas TikTok Live · ${fecha.toISOString()}`,
      '-- Restaurar: powershell -File db\\restaurar_respaldo.ps1 <archivo.sql.gz>',
      '-- (aplica db\\*.sql si la base está vacía y luego carga este archivo con psql).',
      "SET client_encoding = 'UTF8';",
      'SET session_replication_role = replica;  -- sin triggers ni llaves foráneas mientras se cargan los datos',
      'BEGIN;',
    ];
    for (const s of secuencias) {
      partes.push(`CREATE SEQUENCE IF NOT EXISTS ${ident(s.sequencename)} AS ${s.data_type} START ${s.start_value} INCREMENT ${s.increment_by};`);
    }
    const conteos = {};
    const columnas = [];   // ADD COLUMN IF NOT EXISTS: la base real puede tener columnas que no están en db\*.sql
    const datos = [];
    for (const t of tablas) {
      const cols = (await db.query(`
        SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS tipo, a.attnotnull, a.attgenerated,
               pg_get_expr(d.adbin, d.adrelid) AS defecto
        FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = $1 AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum`, [t.oid])).rows;
      const pk = (await db.query(`SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = $1 AND contype = 'p'`, [t.oid])).rows[0];
      const defs = cols.map((c) => {
        if (c.attgenerated === 's') return `${ident(c.attname)} ${c.tipo} GENERATED ALWAYS AS (${c.defecto}) STORED`;
        return `${ident(c.attname)} ${c.tipo}${c.defecto ? ' DEFAULT ' + c.defecto : ''}${c.attnotnull ? ' NOT NULL' : ''}`;
      });
      if (pk) defs.push(pk.def);
      partes.push(`CREATE TABLE IF NOT EXISTS ${ident(t.relname)} (\n  ${defs.join(',\n  ')}\n);`);
      cols.forEach((c, i) => columnas.push(`ALTER TABLE ${ident(t.relname)} ADD COLUMN IF NOT EXISTS ${defs[i]};`));

      const normales = cols.filter((c) => !c.attgenerated).map((c) => ident(c.attname));
      let json = (await db.query(`SELECT coalesce(json_agg(t), '[]')::text AS j, count(*)::int AS n FROM ${ident(t.relname)} t`)).rows[0];
      let filas = JSON.parse(json.j);
      for (const [tabla, colClave, valorClave, colVaciar] of SECRETOS_FUERA_DEL_RESPALDO) {
        if (tabla === t.relname) filas.forEach((f) => { if (f[colClave] === valorClave) f[colVaciar] = ''; });
      }
      if (filas.length !== json.n) throw new Error(`La tabla ${t.relname} no se copió completa (${filas.length} de ${json.n}).`);
      conteos[t.relname] = filas.length;
      if (!filas.length) continue;
      const texto = JSON.stringify(filas);
      let tag = '$r$';
      for (let i = 0; texto.includes(tag); i++) tag = `$r${i}$`;
      datos.push(`INSERT INTO ${ident(t.relname)} (${normales.join(', ')}) OVERRIDING SYSTEM VALUE\n  SELECT ${normales.join(', ')} FROM json_populate_recordset(NULL::${ident(t.relname)}, ${tag}${texto}${tag}::json);`);
    }
    partes.push(`TRUNCATE ${tablas.map((t) => ident(t.relname)).join(', ')};`);
    partes.push(...columnas);
    partes.push(...datos);
    for (const s of secuencias) {
      if (s.last_value !== null) partes.push(`SELECT setval(${literal(s.sequencename)}, ${s.last_value}, true);`);
    }
    partes.push('COMMIT;', `-- Filas por tabla: ${JSON.stringify(conteos)}`, '');
    await db.query('COMMIT');
    return { sql: partes.join('\n'), conteos };
  } finally {
    await db.end().catch(() => {});
  }
}

async function listarRespaldos() {
  if (!fs.existsSync(CARPETA)) return [];
  const archivos = (await fsp.readdir(CARPETA)).filter((a) => PATRON.test(a));
  const lista = await Promise.all(archivos.map(async (archivo) => {
    const ruta = path.join(CARPETA, archivo);
    const info = await fsp.stat(ruta);
    return { archivo, ruta, fecha: info.mtime, bytes: info.size };
  }));
  return lista.sort((a, b) => claveOrden(b.archivo).localeCompare(claveOrden(a.archivo)));
}

// Igual que elegirAConservar del ERP Dulzura. `respaldos` va del más nuevo al más viejo.
function elegirAConservar(respaldos, recientes, hoy = new Date()) {
  const conservar = new Set(respaldos.slice(0, recientes).map((r) => r.archivo));
  const dia = (a) => PATRON.exec(a)?.[1] ?? '';
  const limiteDias = new Date(hoy.getTime() - 30 * 86400000).toLocaleDateString('sv-SE');
  const limiteMeses = new Date(hoy.getFullYear(), hoy.getMonth() - 11, 1).toLocaleDateString('sv-SE').slice(0, 7);
  const vistosDia = new Set();
  const vistosMes = new Set();
  for (const r of respaldos) {
    const d = dia(r.archivo);
    if (!d) continue;
    if (d >= limiteDias && !vistosDia.has(d)) { vistosDia.add(d); conservar.add(r.archivo); }
    const mes = d.slice(0, 7);
    if (mes >= limiteMeses && !vistosMes.has(mes)) { vistosMes.add(mes); conservar.add(r.archivo); }
  }
  return conservar;
}
const respaldosRecientes = () => {
  const v = Number(process.env.BACKUP_KEEP || 30);
  return Number.isInteger(v) && v > 0 ? v : 30;
};

let enCurso = null;
function crearRespaldo() {
  // Si ya hay un respaldo en marcha (botón + automático a la vez), se espera ese mismo.
  enCurso ||= (async () => {
    await fsp.mkdir(CARPETA, { recursive: true });
    const prefijo = nombreParaFecha(new Date());
    const numeros = (await fsp.readdir(CARPETA)).map((a) => PATRON.exec(a))
      .filter((m) => m && `tiktok_ventas_${m[1]}_${m[2]}` === prefijo).map((m) => Number(m[3] ?? 1));
    const base = numeros.length ? `${prefijo}-${Math.max(...numeros) + 1}` : prefijo;
    const destino = path.join(CARPETA, base + '.sql.gz');
    const temporal = destino + '.tmp';
    try {
      const { sql, conteos } = await volcarBase();
      const comprimido = await gzip(Buffer.from(sql, 'utf8'), { level: 9 });
      // Verificación: el archivo comprimido se vuelve a abrir y debe ser idéntico.
      if (!(await gunzip(comprimido)).equals(Buffer.from(sql, 'utf8'))) throw new Error('la copia comprimida no coincide');
      await fsp.writeFile(temporal, comprimido);
      await fsp.rename(temporal, destino);
      log('Respaldo creado', path.basename(destino), comprimido.length, 'bytes', JSON.stringify(conteos));
    } catch (e) {
      await fsp.rm(temporal, { force: true });
      throw new ErrorVisible(500, 'No se pudo crear el respaldo: ' + (e.message || e));
    }
    const todos = await listarRespaldos();
    const conservar = elegirAConservar(todos, respaldosRecientes());
    for (const viejo of todos.filter((r) => !conservar.has(r.archivo))) await fsp.rm(viejo.ruta, { force: true });
    const info = await fsp.stat(destino);
    return { archivo: path.basename(destino), ruta: destino, fecha: info.mtime, bytes: info.size };
  })().finally(() => { enCurso = null; });
  return enCurso;
}

// ─── Correo (Gmail del negocio, a sí mismo) ───

const CORREO_VALIDO = /^[^\s@]+@(gmail|googlemail)\.com$/i;
async function leerConfig() {
  try { return JSON.parse(await fsp.readFile(CONFIG, 'utf8')); } catch { return {}; }
}
async function guardarConfig(c) {
  await fsp.mkdir(path.dirname(CONFIG), { recursive: true });
  await fsp.writeFile(CONFIG + '.tmp', JSON.stringify(c, null, 2), { mode: 0o600 });
  await fsp.rename(CONFIG + '.tmp', CONFIG);
}
function transporte(correo, clave) {
  return require('nodemailer').createTransport({
    host: 'smtp.gmail.com', port: 465, secure: true, auth: { user: correo, pass: clave },
    connectionTimeout: 15000, greetingTimeout: 15000, socketTimeout: 60000,
  });
}
function explicar(error) {
  const codigo = error?.code ?? '';
  const r = error?.responseCode;
  if (codigo === 'EAUTH' || r === 535 || r === 534) {
    return 'Gmail no aceptó el correo o la contraseña de aplicación. Revisa que sea la de 16 letras y que la verificación en 2 pasos esté activada.';
  }
  if (['ECONNECTION', 'ETIMEDOUT', 'EDNS', 'ESOCKET', 'ENOTFOUND', 'ECONNREFUSED'].includes(codigo)) {
    return 'No hay internet o Gmail no respondió. El respaldo quedó en esta PC; se vuelve a intentar más tarde.';
  }
  return 'No se pudo mandar el correo: ' + (error?.message || error);
}
const fechaLegible = (f) => new Date(f).toLocaleString('es-BO', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });

async function configurarCorreo(correo, contrasena) {
  correo = String(correo || '').trim();
  const clave = String(contrasena || '').replace(/\s/g, '');
  if (!CORREO_VALIDO.test(correo)) throw new ErrorVisible(400, 'Escribe un correo de Gmail (termina en @gmail.com).');
  if (!/^[a-z]{16}$/i.test(clave)) throw new ErrorVisible(400, 'La contraseña de aplicación tiene 16 letras (Google la muestra en 4 grupos de 4).');
  try { await transporte(correo, clave).verify(); } catch (e) { throw new ErrorVisible(422, explicar(e)); }
  await guardarConfig({ correo, clave, ultimoEnvio: null, error: null });
}

// null = no hay correo configurado. No lanza: el respaldo ya quedó guardado aunque el correo falle.
async function enviarRespaldo(respaldo) {
  const c = await leerConfig();
  if (!c.correo || !c.clave) return null;
  try {
    await transporte(c.correo, c.clave).sendMail({
      from: { name: 'Panel TikTok Live', address: c.correo },
      to: c.correo,
      subject: `Respaldo Panel TikTok Live · ${fechaLegible(respaldo.fecha)}`,
      text: [
        `Respaldo automático del panel de ventas del live de TikTok (${fechaLegible(respaldo.fecha)}).`,
        '',
        'El archivo adjunto tiene todos los datos de ventas: lives, clientes, compras, cuentas, pagos y conversaciones de WhatsApp.',
        'No se abre con Excel: sirve para devolver el sistema a este día si la PC se pierde o se daña.',
        'Guárdalo; no hace falta responder este correo.',
      ].join('\n'),
      attachments: [{ filename: respaldo.archivo, path: respaldo.ruta, contentType: 'application/gzip' }],
    });
    await guardarConfig({ ...(await leerConfig()), ultimoEnvio: new Date().toISOString(), error: null });
    log('Respaldo enviado por correo', respaldo.archivo);
    return { enviado: true };
  } catch (e) {
    const mensaje = explicar(e);
    await guardarConfig({ ...(await leerConfig()), error: mensaje });
    log('Falló el envío por correo:', mensaje);
    return { enviado: false, error: mensaje };
  }
}

const masViejoQue = (fecha, horas) => !fecha || Date.now() - new Date(fecha).getTime() >= horas * 3600000;

// Cada hora: respalda si el último tiene más de 20 h y manda el último si el último envío tiene más de 20 h.
async function automatico() {
  try {
    let [ultimo] = await listarRespaldos();
    if (!ultimo || masViejoQue(ultimo.fecha, HORAS)) ultimo = await crearRespaldo();
    const c = await leerConfig();
    if (c.correo && masViejoQue(c.ultimoEnvio, HORAS)) await enviarRespaldo(ultimo);
  } catch (e) {
    log('Respaldo automático falló:', e.message || e);
  }
}

async function estado() {
  const lista = await listarRespaldos();
  const c = await leerConfig();
  const u = lista[0];
  return {
    ok: true,
    ultimo: u ? { archivo: u.archivo, fecha: u.fecha.toISOString(), bytes: u.bytes } : null,
    cantidad: lista.length,
    carpeta: CARPETA_VISIBLE,
    correo: c.correo || null,
    ultimoEnvio: c.correo ? c.ultimoEnvio || null : null,
    error: c.correo ? c.error || null : null,
  };
}

// ─── API HTTP ───

const clavesValidas = new Map(); // hash de la clave -> vence (ms)
async function claveValida(clave) {
  if (!clave) return false;
  const h = crypto.createHash('sha256').update(clave).digest('hex');
  if ((clavesValidas.get(h) || 0) > Date.now()) return true;
  try {
    const r = await fetch(PANEL_URL + '/consulta?q=version', { headers: { 'X-Panel-Key': clave }, signal: AbortSignal.timeout(8000) });
    if (r.status === 200) { clavesValidas.set(h, Date.now() + 10 * 60000); return true; }
    if (r.status === 403) return false;
    throw new Error('HTTP ' + r.status);
  } catch (e) {
    throw new ErrorVisible(503, 'No se pudo comprobar la clave con n8n. ¿Está encendido?');
  }
}

function responder(res, estadoHttp, cuerpo) {
  res.writeHead(estadoHttp, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'X-Panel-Key, Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Max-Age': '600',
    'Cache-Control': 'no-store',
  });
  res.end(cuerpo === undefined ? '' : JSON.stringify(cuerpo));
}
function leerCuerpo(req) {
  return new Promise((resolve, reject) => {
    let datos = '';
    req.on('data', (c) => { datos += c; if (datos.length > 10000) { reject(new ErrorVisible(413, 'Petición muy grande.')); req.destroy(); } });
    req.on('end', () => { try { resolve(datos ? JSON.parse(datos) : {}); } catch { reject(new ErrorVisible(400, 'JSON inválido.')); } });
    req.on('error', reject);
  });
}

const servidor = http.createServer(async (req, res) => {
  const ruta = new URL(req.url, 'http://x').pathname;
  try {
    if (req.method === 'OPTIONS') return responder(res, 204);
    if (ruta === '/salud') return responder(res, 200, { ok: true });
    if (!(await claveValida(req.headers['x-panel-key']))) return responder(res, 403, { ok: false, error: 'Clave incorrecta' });

    if (req.method === 'GET' && ruta === '/estado') return responder(res, 200, await estado());
    if (req.method === 'POST' && ruta === '/respaldar') {
      const respaldo = await crearRespaldo();
      const envio = await enviarRespaldo(respaldo);
      return responder(res, 200, { ok: true, respaldo: { archivo: respaldo.archivo, bytes: respaldo.bytes, fecha: respaldo.fecha.toISOString() }, envio });
    }
    if (req.method === 'POST' && ruta === '/correo') {
      const b = await leerCuerpo(req);
      await configurarCorreo(b.correo, b.contrasena);
      // Al guardar se manda el primer respaldo al momento.
      const envio = await enviarRespaldo(await crearRespaldo());
      return responder(res, 200, { ok: true, correo: (await leerConfig()).correo, envio });
    }
    if (req.method === 'POST' && ruta === '/correo/quitar') {
      await fsp.rm(CONFIG, { force: true });
      return responder(res, 200, { ok: true });
    }
    return responder(res, 404, { ok: false, error: 'No encontrado' });
  } catch (e) {
    if (!(e instanceof ErrorVisible)) log('Error:', e);
    return responder(res, e.estado || 500, { ok: false, error: e instanceof ErrorVisible ? e.message : 'Error interno del respaldo.' });
  }
});

if (require.main === module) servidor.listen(PUERTO, '0.0.0.0', () => {
  log(`Servicio de respaldo escuchando en el puerto ${PUERTO}; respaldos en ${CARPETA}`);
  setTimeout(automatico, 60000);          // al arrancar, cuando Postgres ya está listo
  setInterval(automatico, 3600000);       // y cada hora
});
if (require.main === module) process.on('SIGTERM', () => servidor.close(() => process.exit(0)));

module.exports = { elegirAConservar, crearRespaldo, PATRON };
