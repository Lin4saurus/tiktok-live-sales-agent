# M3 · Prueba de la visión IA con imágenes reales.
#
# 1. Pon las imágenes en la carpeta pruebas_vision/ (ignorada por git) con estos nombres:
#      captura__<nickname>__<precio>.jpg        ej. captura__Fricosi__10.jpg
#      comprobante__<monto>.jpg | .png | .pdf    ej. comprobante__35.pdf
#    (Para varias del mismo dato agrega un sufijo: captura__Fricosi__10__2.jpg)
# 2. Con n8n encendido y el "WA - Adaptador de entrada" PUBLICADO, ejecuta:
#      powershell -ExecutionPolicy Bypass -File herramientas\probar_vision.ps1
#
# Cada imagen se envía al webhook de entrada como si llegara por WhatsApp, desde un número
# ficticio distinto (591000001NN), y se compara lo que la IA guardó con lo esperado.
# Al terminar se borran todos los datos de prueba (clientes, capturas, pagos, mensajes).
# Las respuestas del bot a esos números ficticios fallan en Evolution: es lo esperado.
param(
  [string]$Carpeta = (Join-Path (Split-Path -Parent $PSScriptRoot) 'pruebas_vision'),
  [int]$EsperaMaxSeg = 120
)
$ErrorActionPreference = 'Stop'
$webhook = 'http://127.0.0.1:5678/webhook/evolution-inbound'
function Sql([string]$q) { (docker exec postgres psql -U postgres -d ventas -At -F '|' -c $q) }

$archivos = Get-ChildItem $Carpeta -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp|pdf)$' } | Sort-Object Name
if (-not $archivos) { throw "No hay imágenes en $Carpeta" }
$inicio = (Sql "SELECT now()")
$numeros = @()
$resultados = @()
$i = 0

foreach ($f in $archivos) {
  $i++
  $partes = $f.BaseName -split '__'
  $tipo = $partes[0].ToLower()
  $numero = '591000001' + $i.ToString('00')
  $numeros += $numero
  $id = 'VISION-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
  $esPdf = $f.Extension -eq '.pdf'
  $mime = if ($esPdf) { 'application/pdf' } elseif ($f.Extension -eq '.png') { 'image/png' } elseif ($f.Extension -eq '.webp') { 'image/webp' } else { 'image/jpeg' }
  $mensaje = if ($esPdf) { @{ documentMessage = @{ mimetype = $mime; fileName = $f.Name }; base64 = $b64 } }
             else { @{ imageMessage = @{ mimetype = $mime }; base64 = $b64 } }
  $cuerpo = @{
    event = 'messages.upsert'; instance = 'ventas_tiktok'
    data = @{ key = @{ remoteJid = "$numero@s.whatsapp.net"; fromMe = $false; id = $id }
              pushName = 'Prueba vision'; messageType = $(if ($esPdf) { 'documentMessage' } else { 'imageMessage' })
              message = $mensaje }
  } | ConvertTo-Json -Depth 8 -Compress
  Invoke-RestMethod -Method Post -Uri $webhook -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo)) -ContentType 'application/json' | Out-Null

  # Espera a que el flujo guarde la captura o el pago
  $fila = $null
  $limite = (Get-Date).AddSeconds($EsperaMaxSeg)
  while (-not $fila -and (Get-Date) -lt $limite) {
    Start-Sleep -Seconds 3
    $fila = Sql "SELECT 'captura', nickname, precio, confianza FROM capturas WHERE message_id = '$id'
                 UNION ALL SELECT 'comprobante', NULL, monto_pagado, confianza FROM pagos WHERE message_id = '$id'"
  }
  $leido = if ($fila) { $fila -split '\|' } else { @('sin_respuesta', '', '', '') }

  $esperadoNick = if ($tipo -eq 'captura') { $partes[1] } else { '' }
  $esperadoMonto = if ($tipo -eq 'captura') { $partes[2] } else { $partes[1] }
  $okTipo = $leido[0] -eq $tipo
  $okNick = ($tipo -ne 'captura') -or ($leido[1].Trim().ToLower() -eq $esperadoNick.Trim().ToLower())
  $okMonto = ($leido[2] -ne '') -and ([decimal]$leido[2] -eq [decimal]($esperadoMonto -replace ',', '.'))
  $resultados += [pscustomobject]@{
    Archivo = $f.Name; Tipo = $leido[0]; Nickname = $leido[1]; Monto = $leido[2]; Confianza = $leido[3]
    Correcto = $(if ($okTipo -and $okNick -and $okMonto) { 'SI' } else { 'NO' })
  }
  Write-Host ("[{0}/{1}] {2} -> {3}" -f $i, $archivos.Count, $f.Name, $resultados[-1].Correcto)
}

$resultados | Format-Table -AutoSize
$bien = ($resultados | Where-Object Correcto -eq 'SI').Count
Write-Host ("Aciertos: {0} de {1}" -f $bien, $resultados.Count)
$dudosas = $resultados | Where-Object { $_.Confianza -and [decimal]$_.Confianza -lt 0.6 }
Write-Host ("Con confianza baja (< 0.6): {0}" -f $dudosas.Count)
$csv = Join-Path $Carpeta ('resultado_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '.csv')
$resultados | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
Write-Host "Detalle guardado en $csv"

# Limpieza de los datos de prueba
$lista = ($numeros | ForEach-Object { "'$_'" }) -join ','
Sql @"
BEGIN;
DELETE FROM acciones_panel WHERE whatsapp IN ($lista);
DELETE FROM pagos WHERE whatsapp IN ($lista);
DELETE FROM capturas WHERE whatsapp IN ($lista);
DELETE FROM cuentas_diarias cd WHERE cd.cliente_id IN ($lista);
DELETE FROM cuentas_tiktok WHERE cliente_id IN ($lista);
DELETE FROM mensajes WHERE whatsapp IN ($lista);
DELETE FROM mensajes_procesados WHERE whatsapp IN ($lista);
DELETE FROM clientes WHERE whatsapp IN ($lista);
DELETE FROM lives l WHERE l.origen = 'respaldo' AND l.inicio >= '$inicio'
  AND NOT EXISTS (SELECT 1 FROM capturas c WHERE c.live_id = l.live_id)
  AND NOT EXISTS (SELECT 1 FROM cuentas_diarias cd WHERE cd.live_id = l.live_id);
COMMIT;
"@ | Out-Null
Write-Host 'Datos de prueba borrados.'
