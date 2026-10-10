<#
.SYNOPSIS
  Prepara un proyector Android por ADB (una sola vez): instala la app, le da los
  permisos para apagar el protector de pantalla a nivel sistema y deja la
  pantalla siempre encendida.

.DESCRIPTION
  Requisitos en el proyector (una vez):
    1. Ajustes -> Acerca de -> tocar "Número de compilación" 7 veces (activa Opciones de desarrollador).
    2. Opciones de desarrollador -> activar "Depuración USB" y, si existe, "Depuración por red/ADB por Wi-Fi".
    3. Si sólo hay depuración USB: conectalo por cable a la PC y ejecutá primero
       `.\tools\configurar_proyector.ps1 -HabilitarWifi` para abrir ADB por Wi-Fi.
  Cuando el proyector pregunte "¿Permitir depuración USB?", aceptá y marcá "Siempre".

.EXAMPLE
  .\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -Apk build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
  .\tools\configurar_proyector.ps1 -Ip 192.168.1.50                # sólo permisos y ajustes
  .\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -DetectarScreensaver
  .\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -DesactivarPaquete com.fabricante.screensaver
  .\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -Restaurar     # vuelve los ajustes a como estaban
#>
param(
    [string]$Ip,
    [string]$Apk,
    [switch]$HabilitarWifi,
    [switch]$DetectarScreensaver,
    [string]$DesactivarPaquete,
    [switch]$Restaurar
)

$ErrorActionPreference = 'Continue'
$pkg = 'com.njb.proyectores'

# --- Encontrar adb -----------------------------------------------------------
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe' }
if (-not (Test-Path $adb)) {
    throw "No se encontró adb. Instalá 'Android SDK Platform-Tools' o Android Studio."
}
function Adb { & $adb @args }

if ($HabilitarWifi) {
    Write-Host "Abriendo ADB por Wi-Fi en el proyector conectado por USB..." -ForegroundColor Cyan
    Adb tcpip 5555
    $ipLine = Adb shell ip -f inet addr show wlan0 2>$null | Select-String 'inet (\d+\.\d+\.\d+\.\d+)'
    if ($ipLine) { Write-Host "IP del proyector: $($ipLine.Matches[0].Groups[1].Value). Ahora podés desconectar el cable y usar -Ip." -ForegroundColor Green }
    return
}

if ($Ip) {
    Write-Host "Conectando a $Ip:5555..." -ForegroundColor Cyan
    $out = Adb connect "$Ip`:5555"
    Write-Host $out
}

$devices = (Adb devices) | Select-String '\sdevice$'
if (-not $devices) {
    throw "No hay ningún dispositivo autorizado. Revisá que la depuración esté activa y aceptá el aviso en el proyector."
}
Write-Host "Dispositivo: $($devices[0].ToString().Trim())" -ForegroundColor Green
$model = (Adb shell getprop ro.product.model).Trim()
$sdk = (Adb shell getprop ro.build.version.sdk).Trim()
Write-Host "Modelo: $model  |  Android API $sdk"

# --- Modos especiales ----------------------------------------------------------
if ($Restaurar) {
    Write-Host "`nRestaurando ajustes de pantalla por defecto..." -ForegroundColor Yellow
    Adb shell settings put secure screensaver_enabled 1
    Adb shell settings put secure screensaver_activate_on_sleep 1
    Adb shell settings put secure screensaver_activate_on_dock 1
    Adb shell settings delete secure sleep_timeout
    Adb shell settings delete secure attentive_timeout
    Adb shell settings put system screen_off_timeout 600000
    Adb shell settings put global stay_on_while_plugged_in 0
    Write-Host "Listo."
    return
}

if ($DetectarScreensaver) {
    Write-Host "`nEsperá a que aparezca el protector de pantalla en el proyector y después presioná Enter acá..." -ForegroundColor Yellow
    Read-Host | Out-Null
    Write-Host "Ventana con foco:" -ForegroundColor Cyan
    Adb shell dumpsys window | Select-String 'mCurrentFocus|mFocusedApp'
    Write-Host "`nActividad en primer plano:" -ForegroundColor Cyan
    Adb shell dumpsys activity activities | Select-String 'topResumedActivity|mResumedActivity|ResumedActivity'
    Write-Host "`nComponentes de Daydream configurados:" -ForegroundColor Cyan
    Adb shell settings get secure screensaver_components
    Adb shell settings get secure screensaver_default_component
    Write-Host "`nEl paquete es lo que aparece antes de la barra '/'. Para apagarlo:" -ForegroundColor Green
    Write-Host "  .\tools\configurar_proyector.ps1 -Ip $Ip -DesactivarPaquete <paquete>"
    return
}

if ($DesactivarPaquete) {
    Write-Host "`nSe va a desactivar el paquete '$DesactivarPaquete' en el proyector." -ForegroundColor Yellow
    Write-Host "Se puede revertir con: adb shell pm enable $DesactivarPaquete"
    $ok = Read-Host "¿Continuar? (s/n)"
    if ($ok -ne 's') { return }
    Adb shell pm disable-user --user 0 $DesactivarPaquete
    Write-Host "Listo."
    return
}

# --- Instalar APK ---------------------------------------------------------------
if ($Apk) {
    if (-not (Test-Path $Apk)) { throw "No existe la APK: $Apk" }
    Write-Host "`nInstalando $Apk ..." -ForegroundColor Cyan
    $res = Adb install -r -d $Apk 2>&1
    Write-Host $res
    if ("$res" -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match') {
        Write-Host "La app instalada tiene otra firma. Desinstalando y reinstalando..." -ForegroundColor Yellow
        Adb uninstall $pkg
        Adb install -r $Apk
    }
}

# --- Permisos ----------------------------------------------------------------------
Write-Host "`nOtorgando permisos a $pkg ..." -ForegroundColor Cyan
Adb shell pm grant $pkg android.permission.WRITE_SECURE_SETTINGS
Adb shell appops set $pkg WRITE_SETTINGS allow
Adb shell appops set $pkg REQUEST_INSTALL_PACKAGES allow
Adb shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>$null

# --- Ajustes del sistema ------------------------------------------------------------
Write-Host "`nApagando protector de pantalla y apagado automático..." -ForegroundColor Cyan
Adb shell settings put secure screensaver_enabled 0
Adb shell settings put secure screensaver_activate_on_sleep 0
Adb shell settings put secure screensaver_activate_on_dock 0
Adb shell settings put secure sleep_timeout -1
Adb shell settings put secure attentive_timeout -1
Adb shell settings put system screen_off_timeout 2147483647
Adb shell settings put global stay_on_while_plugged_in 7

Write-Host "`nEstado actual:" -ForegroundColor Cyan
"  screensaver_enabled      = " + (Adb shell settings get secure screensaver_enabled)
"  screen_off_timeout       = " + (Adb shell settings get system screen_off_timeout)
"  stay_on_while_plugged_in = " + (Adb shell settings get global stay_on_while_plugged_in)
"  screensaver_components   = " + (Adb shell settings get secure screensaver_components)

Write-Host "`nListo. Abrí NJB Proyectores en el proyector y entrá en 'Usar como receptor'." -ForegroundColor Green
Write-Host "Si el protector sigue apareciendo, es una app del fabricante: usá -DetectarScreensaver para identificarla y -DesactivarPaquete para apagarla."
Adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
