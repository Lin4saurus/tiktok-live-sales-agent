# Aplica en orden las migraciones de la base ventas (solo para una instalación nueva o para
# reaplicar funciones: 002-005 son idempotentes; 001 es el esquema inicial y falla si ya existe).
#   powershell -ExecutionPolicy Bypass -File db\aplicar_migraciones.ps1            # 002 en adelante
#   powershell -ExecutionPolicy Bypass -File db\aplicar_migraciones.ps1 -Desde 1   # instalación nueva
param([int]$Desde = 2)
$ErrorActionPreference = 'Stop'
$carpeta = $PSScriptRoot

Get-ChildItem $carpeta -Filter '0*.sql' | Sort-Object Name | ForEach-Object {
  if ([int]$_.Name.Substring(0, 3) -ge $Desde) {
    Write-Host "Aplicando $($_.Name)"
    Get-Content -Raw -Encoding UTF8 $_.FullName | docker exec -i postgres psql -U postgres -d ventas -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE -ne 0) { throw "Fallo en $($_.Name)" }
  }
}
& (Join-Path $carpeta 'cargar_panel.ps1')
