<#
.SYNOPSIS
  Publica una versión nueva: sube el número de versión, hace commit, crea el tag
  y lo empuja a GitHub. GitHub Actions compila y publica las APK; las apps
  instaladas se actualizan solas.

.EXAMPLE
  .\tools\publicar.ps1                      # 1.1.0 -> 1.1.1
  .\tools\publicar.ps1 -Minor               # 1.1.0 -> 1.2.0
  .\tools\publicar.ps1 -Mensaje "Arreglo de audio"
#>
param(
    [switch]$Minor,
    [switch]$Major,
    [string]$Mensaje
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Esta carpeta no es un repositorio git. Seguí el paso 'Configurar GitHub' del README." }

$remote = git remote get-url origin 2>$null
if (-not $remote) { throw "No hay remoto 'origin'. Creá el repo en GitHub y ejecutá: git remote add origin https://github.com/USUARIO/REPO.git" }

# --- Subir versión en pubspec.yaml -------------------------------------------
$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = [IO.File]::ReadAllText($pubspecPath)
if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    throw "No se encontró 'version: X.Y.Z+N' en pubspec.yaml"
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]; $build = [int]$Matches[4]
$old = "$maj.$min.$pat+$build"

if ($Major) { $maj++; $min = 0; $pat = 0 }
elseif ($Minor) { $min++; $pat = 0 }
else { $pat++ }
$build++

$semver = "$maj.$min.$pat"
$new = "$semver+$build"
$pubspec = $pubspec -replace '(?m)^version:\s*\S+', "version: $new"
[IO.File]::WriteAllText($pubspecPath, $pubspec, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Versión: $old  ->  $new" -ForegroundColor Cyan

# --- Commit + tag + push ------------------------------------------------------
if (-not $Mensaje) { $Mensaje = "Versión $semver" }
git add -A
git commit -m $Mensaje | Out-Null
git tag "v$semver"
git push origin HEAD
git push origin "v$semver"

$web = $remote -replace '\.git$', '' -replace '^git@github\.com:', 'https://github.com/'
Write-Host ""
Write-Host "Listo. GitHub está compilando la versión v$semver." -ForegroundColor Green
Write-Host "Progreso:  $web/actions"
Write-Host "Descargas: $web/releases/latest"
Write-Host "Los proyectores y PCs con la app instalada la van a detectar solos (como máximo en 30 minutos, o al abrir la app)."
