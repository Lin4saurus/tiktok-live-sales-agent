# Crea el acceso directo "Panel TikTok Live" en el escritorio: prende Docker y n8n si hace falta
# y abre el panel de ventas en una ventana propia (ver iniciar.vbs).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File instalacion\crear-accesos.ps1
$ErrorActionPreference = 'Stop'
$carpeta = $PSScriptRoot
$ws = New-Object -ComObject WScript.Shell
$ruta = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Panel TikTok Live.lnk'
$a = $ws.CreateShortcut($ruta)
$a.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$a.Arguments = '"' + (Join-Path $carpeta 'iniciar.vbs') + '"'
$a.WorkingDirectory = $carpeta
$a.IconLocation = (Join-Path $carpeta 'panel.ico') + ',0'
$a.Description = 'Abre el panel de ventas del live de TikTok'
$a.Save()
Write-Host "Acceso creado: $ruta"
