# Devuelve la base a un respaldo (.sql.gz) hecho por el contenedor «respaldo-tiktok» (o llegado por Gmail).
#   powershell -ExecutionPolicy Bypass -File db\restaurar_respaldo.ps1 -Archivo <ruta.sql.gz> -Confirmar
#   powershell -ExecutionPolicy Bypass -File db\restaurar_respaldo.ps1 -Archivo <ruta.sql.gz> -Base ventas_prueba   # para probar
# Si la base no existe o está vacía (PC nueva), primero crea el esquema con las migraciones de db\ y luego carga
# los datos. OJO: reemplaza TODOS los datos de la base. Para «ventas» exige -Confirmar.
# Después de restaurar hay que volver a escribir en el panel el Gmail y la contraseña de aplicación del respaldo,
# y el verify_token de WhatsApp Cloud si se usaba: no viajan en los respaldos.
param(
  [Parameter(Mandatory = $true)][string]$Archivo,
  [string]$Base = 'ventas',
  [switch]$Confirmar
)
$ErrorActionPreference = 'Stop'
$carpeta = $PSScriptRoot
if (-not (Test-Path $Archivo)) { throw "No existe el archivo $Archivo" }
if ($Base -eq 'ventas' -and -not $Confirmar) {
  throw 'Esto reemplaza todos los datos de la base ventas. Si estás segura, agrega -Confirmar.'
}

function Psql([string]$db, [string[]]$extra) {
  # Los avisos (NOTICE) de psql salen por stderr: no deben cortar el script; solo cuenta el código de salida.
  $ErrorActionPreference = 'Continue'
  docker exec -e PGOPTIONS='-c client_min_messages=warning' postgres psql -U postgres -d $db -v ON_ERROR_STOP=1 -q @extra
  if ($LASTEXITCODE -ne 0) { throw "psql falló en la base $db" }
}

$existe = docker exec postgres psql -U postgres -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '$Base'"
if (-not $existe) {
  Write-Host "Creando la base $Base"
  Psql 'postgres' @('-c', "CREATE DATABASE `"$Base`"")
}
$tablas = docker exec postgres psql -U postgres -d $Base -At -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'"
if ([int]$tablas -eq 0) {
  Get-ChildItem $carpeta -Filter '0*.sql' | Sort-Object Name | ForEach-Object {
    Write-Host "Esquema: $($_.Name)"
    docker cp $_.FullName "postgres:/tmp/$($_.Name)"
    Psql $Base @('-f', "/tmp/$($_.Name)")
    docker exec -u root postgres rm -f "/tmp/$($_.Name)"
  }
}

# Se descomprime dentro del contenedor (gzip de Postgres) para no pasar el texto por PowerShell (tildes).
Write-Host "Cargando datos de $(Split-Path $Archivo -Leaf)"
docker cp $Archivo postgres:/tmp/restaurar.sql.gz
try {
  docker exec postgres sh -c "gunzip -c /tmp/restaurar.sql.gz > /tmp/restaurar.sql"
  if ($LASTEXITCODE -ne 0) { throw 'El archivo no es un respaldo .sql.gz válido.' }
  Psql $Base @('-f', '/tmp/restaurar.sql')
} finally {
  docker exec -u root postgres rm -f /tmp/restaurar.sql.gz /tmp/restaurar.sql
}
Write-Host "Listo: la base $Base quedó como en el respaldo."
