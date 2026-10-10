<#
.SYNOPSIS
  Compila la app localmente (APK Android y/o Windows) con el repositorio de
  actualizaciones embebido, igual que lo hace GitHub Actions.

.EXAMPLE
  .\tools\compilar.ps1            # APK Android
  .\tools\compilar.ps1 -Windows   # Sólo Windows
  .\tools\compilar.ps1 -Todo      # Android + Windows
#>
param(
    [switch]$Windows,
    [switch]$Todo
)

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# Deducir usuario/repo del remoto git para que la app sepa de dónde actualizarse.
$repo = ''
$remote = (& git remote get-url origin 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) { $remote = $null }
if ($remote -and $remote -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    $repo = "$($Matches[1])/$($Matches[2])"
    Write-Host "Repositorio de actualizaciones: $repo" -ForegroundColor Cyan
} else {
    Write-Warning "No se detectó un remoto de GitHub: la app compilada NO va a buscar actualizaciones."
}

$define = if ($repo) { "--dart-define=UPDATE_REPO=$repo" } else { '' }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falló' }

if (-not $Windows -or $Todo) {
    Write-Host "`n=== Compilando APK Android ===" -ForegroundColor Yellow
    flutter build apk --release $define
    if ($LASTEXITCODE -ne 0) { throw 'La compilación Android falló' }
    Write-Host "`nAPK generadas en build\app\outputs\flutter-apk\:" -ForegroundColor Green
    Get-ChildItem build\app\outputs\flutter-apk\*.apk | ForEach-Object { "  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB) }
    Write-Host "Para el proyector usá app-arm64-v8a-release.apk (o armeabi-v7a si es muy viejo)."
}

if ($Windows -or $Todo) {
    Write-Host "`n=== Compilando Windows ===" -ForegroundColor Yellow
    flutter build windows --release $define
    if ($LASTEXITCODE -ne 0) { throw 'La compilación Windows falló' }
    Write-Host "`nEjecutable en build\windows\x64\runner\Release\proyectar.exe" -ForegroundColor Green

    $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $iscc) {
        $version = ([IO.File]::ReadAllText("$root\pubspec.yaml") | Select-String '(?m)^version:\s*([\d.]+)').Matches[0].Groups[1].Value
        & $iscc /Q /DAppVersion=$version windows\installer\njb-proyectores.iss
        if ($LASTEXITCODE -eq 0) { Write-Host "Instalador en dist\njb-proyectores-setup.exe" -ForegroundColor Green }
    } else {
        Write-Host "Inno Setup no está instalado: no se generó el instalador (winget install JRSoftware.InnoSetup)."
    }
}
