<#
.SYNOPSIS
  Muestra los 4 secrets que hay que cargar en GitHub para que Actions firme las
  APK con la misma clave que usás localmente. Se cargan una sola vez en:
  GitHub -> tu repo -> Settings -> Secrets and variables -> Actions -> New repository secret
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$props = Join-Path $root 'android\key.properties'
if (-not (Test-Path $props)) { throw "No existe android\key.properties. Generá la clave primero (ver README)." }

$kv = @{}
Get-Content $props | ForEach-Object {
    if ($_ -match '^\s*([^=#]+)=(.*)$') { $kv[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$storeFile = Join-Path (Join-Path $root 'android') $kv['storeFile']
if (-not (Test-Path $storeFile)) { throw "No existe el keystore: $storeFile" }

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($storeFile))

Write-Host "`nCargá estos 4 secrets en GitHub (nombre exacto):`n" -ForegroundColor Cyan
Write-Host "KEYSTORE_PASSWORD = $($kv['storePassword'])"
Write-Host "KEY_ALIAS         = $($kv['keyAlias'])"
Write-Host "KEY_PASSWORD      = $($kv['keyPassword'])"
Write-Host "KEYSTORE_BASE64   = (se copió al portapapeles, son $($b64.Length) caracteres)"
try {
    Set-Clipboard -Value $b64
} catch {
    Write-Host "`nNo se pudo copiar al portapapeles. Valor de KEYSTORE_BASE64:`n$b64"
}
Write-Host "`nGUARDÁ una copia de android\keystore\njb-release.jks y de key.properties en un lugar seguro." -ForegroundColor Yellow
Write-Host "Si se pierde esa clave, no se van a poder instalar actualizaciones sobre las apps ya instaladas."
