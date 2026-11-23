' Abre el panel de ventas del live de TikTok en una ventana propia.
' El panel lo sirve n8n (http://127.0.0.1:5678/webhook/panel), que corre en Docker desde la carpeta
' n8n-host (al lado de esta carpeta del proyecto). Si n8n no responde: prende Docker Desktop si hace
' falta, levanta los contenedores (docker compose up -d) y espera a que n8n conteste.
Option Explicit
Dim sh, fso, proyecto, infra, url, i
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
proyecto = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
infra = fso.BuildPath(fso.GetParentFolderName(proyecto), "n8n-host")
url = "http://127.0.0.1:5678/webhook/panel"

If Not N8nPrendido() Then
  If Not DockerListo() Then
    PrenderDocker
    For i = 1 To 90
      WScript.Sleep 2000
      If DockerListo() Then Exit For
    Next
    If Not DockerListo() Then
      Fallo "Docker Desktop no termino de arrancar." & vbCrLf & "Abrelo a mano desde el escritorio y vuelve a intentar."
    End If
  End If

  If Not fso.FileExists(fso.BuildPath(infra, "docker-compose.yml")) Then
    Fallo "No encontre la carpeta de Docker:" & vbCrLf & infra
  End If
  sh.Run "cmd /c cd /d """ & infra & """ && docker compose up -d", 0, True

  For i = 1 To 90
    WScript.Sleep 2000
    If N8nPrendido() Then Exit For
  Next
  If Not N8nPrendido() Then
    Fallo "n8n no respondio." & vbCrLf & "Revisa los contenedores en Docker Desktop (n8n, postgres, evolution-api)."
  End If
End If

AbrirVentana

Function N8nPrendido()
  Dim h
  N8nPrendido = False
  On Error Resume Next
  Set h = CreateObject("MSXML2.ServerXMLHTTP.6.0")
  h.setTimeouts 1000, 1000, 1000, 2000
  h.Open "GET", "http://127.0.0.1:5678/healthz", False
  h.Send
  If Err.Number = 0 Then N8nPrendido = (h.Status = 200)
  On Error GoTo 0
End Function

Function DockerListo()
  DockerListo = (sh.Run("cmd /c docker info >nul 2>&1", 0, True) = 0)
End Function

Sub PrenderDocker()
  Dim exe
  exe = sh.ExpandEnvironmentStrings("%ProgramW6432%") & "\Docker\Docker\Docker Desktop.exe"
  If Not fso.FileExists(exe) Then exe = sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Docker\Docker\Docker Desktop.exe"
  If Not fso.FileExists(exe) Then Fallo "No encontre Docker Desktop instalado en esta PC."
  sh.Run """" & exe & """", 0, False
End Sub

Sub Fallo(texto)
  MsgBox texto, vbExclamation, "Panel de ventas TikTok"
  WScript.Quit 1
End Sub

' Edge en modo aplicacion: una ventana propia, sin pestanas ni barra de direcciones. Si no hay Edge, el navegador de siempre.
Sub AbrirVentana()
  Dim edge
  edge = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\Microsoft\Edge\Application\msedge.exe"
  If Not fso.FileExists(edge) Then edge = sh.ExpandEnvironmentStrings("%ProgramW6432%") & "\Microsoft\Edge\Application\msedge.exe"
  If Not fso.FileExists(edge) Then edge = sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Microsoft\Edge\Application\msedge.exe"
  If fso.FileExists(edge) Then
    sh.Run """" & edge & """ --app=" & url, 1, False
  Else
    sh.Run url, 1, False
  End If
End Sub
