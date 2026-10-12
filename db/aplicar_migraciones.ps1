# Aplica en orden las migraciones de la base ventas (solo para una instalación nueva o para
# reaplicar funciones: 002 en adelante son idempotentes; 001 es el esquema inicial y falla si ya existe).
#   powershell -ExecutionPolicy Bypass -File db\aplicar_migraciones.ps1            # 002 en adelante
#   powershell -ExecutionPolicy Bypass -File db\aplicar_migraciones.ps1 -Desde 1   # instalación nueva
# Los archivos se copian al contenedor y psql los lee directamente: si se pasaran por una
# tubería de Windows PowerShell, las tildes y la ñ se convertirían en '?'.
param([int]$Desde = 2)
$ErrorActionPreference = 'Stop'
$carpeta = $PSScriptRoot

Get-ChildItem $carpeta -Filter '0*.sql' | Sort-Object Name | ForEach-Object {
  if ([int]$_.Name.Substring(0, 3) -ge $Desde) {
    Write-Host "Aplicando $($_.Name)"
    docker cp $_.FullName "postgres:/tmp/$($_.Name)"
    docker exec postgres psql -U postgres -d ventas -v ON_ERROR_STOP=1 -q -f "/tmp/$($_.Name)"
    $codigo = $LASTEXITCODE
    docker exec -u root postgres rm -f "/tmp/$($_.Name)"
    if ($codigo -ne 0) { throw "Fallo en $($_.Name)" }
  }
}
& (Join-Path $carpeta 'cargar_panel.ps1')
