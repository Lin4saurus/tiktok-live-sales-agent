# Carga panel/panel.html en la base (tabla panel_recursos) para que n8n lo sirva en
# http://127.0.0.1:5678/webhook/panel. Ejecutar desde la carpeta del proyecto:
#   powershell -ExecutionPolicy Bypass -File db\cargar_panel.ps1
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$archivo = Join-Path $raiz 'panel\panel.html'

docker cp $archivo postgres:/tmp/panel.html
docker exec postgres psql -U postgres -d ventas -v ON_ERROR_STOP=1 -c @"
INSERT INTO panel_recursos (nombre, contenido, actualizado)
VALUES ('panel.html', pg_read_file('/tmp/panel.html'), now())
ON CONFLICT (nombre) DO UPDATE SET contenido = EXCLUDED.contenido, actualizado = now();
"@
docker exec -u root postgres rm -f /tmp/panel.html
Write-Host 'Panel cargado. Recarga el panel en el navegador.'
