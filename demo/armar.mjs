// Arma la demo en línea del panel (para Vercel): copia panel/panel.html a public/index.html,
// le agrega la API falsa (demo/api-falsa.js), que responde con datos de
// ejemplo en el navegador en lugar de n8n + PostgreSQL.
// Uso: node demo/armar.mjs   (Vercel lo ejecuta solo, ver vercel.json)
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const salida = join(raiz, 'public');
let html = readFileSync(join(raiz, 'panel', 'panel.html'), 'utf8');

const reemplazos = [
  ['<title>Panel de ventas</title>', '<title>Panel de ventas · Demo</title>'],
  ['<script>\nconst API', '<script src="api-falsa.js"></script>\n<script>\nconst API'],
  ['Escribe la clave del panel para entrar.', 'Demo: escribe cualquier clave (por ejemplo «demo»).'],
  ["throw new Error('No hay conexión con n8n. ¿Está encendido?')", "throw new Error('No se pudo cargar la demo.')"],
];
html = html.replace(/\r\n/g, '\n');
for (const [de, a] of reemplazos) {
  if (!html.includes(de)) throw new Error('armar.mjs: no encontré en panel.html el texto «' + de.slice(0, 40) + '…». ¿Cambió el panel?');
  html = html.replace(de, a);
}

mkdirSync(salida, { recursive: true });
writeFileSync(join(salida, 'index.html'), html);
copyFileSync(join(raiz, 'demo', 'api-falsa.js'), join(salida, 'api-falsa.js'));
console.log('Demo armada en public/ (index.html + api-falsa.js)');
