# NJB Proyectores

Espejado de pantalla por Wi-Fi: la PC o el celular **emiten**, y el proyector
Android (con esta misma app en "modo receptor") **recibe**. Todo va por la red
local con WebRTC, sin internet ni servidores externos.

- **Emisor:** Windows (pantalla completa o una sola ventana) y Android (celular).
- **Receptor:** cualquier Android 5.0+ (proyectores chinos, TV boxes, tablets) y también Windows.
- **Actualización automática:** las apps instaladas detectan versiones nuevas publicadas en GitHub y se actualizan solas.
- **Anti-screensaver:** el receptor se comporta como YouTube para que el proyector no lance su protector, y puede apagarlo del todo a nivel sistema.

---

## 1. Uso diario

1. En el proyector: abrir **NJB Proyectores → "Usar como receptor"**. Queda esperando y muestra su IP.
2. En la PC o el celular: abrir la app. El receptor aparece solo en la lista
   (mDNS + barrido de red). Si no aparece, usar el botón **"Conectar por IP"** con la IP que muestra el proyector.
3. Tocar **PROYECTAR**. En Windows se elige pantalla completa o una ventana.
4. Los ajustes de imagen (brillo, contraste, nitidez, etc.) se aplican en vivo en el receptor.

Si el emisor se cae o cambia de red, el receptor vuelve solo a "esperando conexión".
Si el receptor se reinicia, el emisor intenta reconectarse 5 veces antes de avisar.

---

## 2. Instalar en el proyector por primera vez

> **Importante:** la app cambió de nombre de paquete (`com.njb.proyectores`) y de firma.
> Si ya tenías la versión vieja instalada hay que **desinstalarla una vez**. Después, nunca más.

### Opción A: con cable o ADB por Wi-Fi (recomendada, deja todo configurado)

En el proyector, una sola vez: *Ajustes → Acerca de → tocar "Número de compilación" 7 veces*,
luego en *Opciones de desarrollador* activar **Depuración USB** (y "Depuración por red" si existe).

Desde la PC:

```powershell
# 1. Compilar la APK (o bajarla de GitHub Releases)
.\tools\compilar.ps1

# 2. Instalar + permisos + apagar screensaver, todo junto
.\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -Apk build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Si el proyector sólo tiene depuración USB: conectarlo por cable y correr primero
`.\tools\configurar_proyector.ps1 -HabilitarWifi`; después ya se usa `-Ip`.

### Opción B: a mano

Copiar `njb-proyectores-arm64-v8a.apk` (o `armeabi-v7a` si es muy viejo) en un pendrive
e instalarla con el explorador de archivos del proyector. Funciona igual, pero el
screensaver sólo se puede "engañar", no apagar (ver sección 3).

---

## 3. El protector de pantalla del proyector

Hay dos niveles:

**Nivel 1 – automático, sin configurar nada.** Mientras está en modo receptor la app
hace lo mismo que YouTube: wakelock de pantalla, sesión multimedia en estado
"reproduciendo", una pista de audio en silencio en loop (muchos firmwares chinos
consultan `isMusicActive()`) y simula actividad cada 20 s. El HUD del receptor
muestra qué capas están activas (`PROTECCIÓN: WAKELOCK + AUDIO + MEDIA + INPUT`).

**Nivel 2 – definitivo (requiere `configurar_proyector.ps1` una vez).** El script
le da a la app el permiso `WRITE_SECURE_SETTINGS` y apaga el protector y el apagado
automático a nivel sistema. Cada vez que arranca el modo receptor, la app vuelve a
aplicarlo. El HUD muestra `SCREENSAVER DEL SISTEMA DESACTIVADO`.

Si aun así aparece, es una app propia del fabricante:

```powershell
.\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -DetectarScreensaver   # te dice qué paquete es
.\tools\configurar_proyector.ps1 -Ip 192.168.1.50 -DesactivarPaquete com.fabricante.screensaver
```

Para volver todo a como estaba: `-Restaurar`.

---

## 4. Actualizaciones automáticas (configurar GitHub una sola vez)

Cómo funciona: `tools/publicar.ps1` sube la versión y crea un tag → GitHub Actions
compila las APK firmadas y el ZIP de Windows → los publica en **Releases** → cada app
instalada consulta ese Release al abrir y cada 30 minutos; en Android descarga la APK
correcta para su procesador y lanza la instalación (la primera vez el proyector pide
confirmar; desde Android 12 las siguientes son silenciosas).

Se eligió GitHub y no Drive ni Firebase porque: es gratis, da URLs de descarga
directas y estables, versiona todo y además compila por nosotros. Drive no sirve
para descargas directas de archivos grandes y Firebase App Distribution obliga a
que cada equipo inicie sesión.

### Pasos (una vez)

1. Crear un repositorio **público** en GitHub (por ejemplo `njb-proyectores`).
   Público es necesario para que las apps consulten Releases sin token.
2. Conectar esta carpeta y subirla:
   ```powershell
   git remote add origin https://github.com/TU_USUARIO/njb-proyectores.git
   git push -u origin main
   ```
3. Cargar los secrets de firma. Este comando los muestra y copia el keystore al portapapeles:
   ```powershell
   .\tools\secrets_github.ps1
   ```
   En GitHub: *Settings → Secrets and variables → Actions → New repository secret*,
   crear `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` y `KEY_PASSWORD`.
4. Publicar la primera versión:
   ```powershell
   .\tools\publicar.ps1
   ```
   En 10 a 15 minutos aparece en `https://github.com/TU_USUARIO/njb-proyectores/releases`.

### Cada vez que cambiás algo

```powershell
.\tools\publicar.ps1 -Mensaje "Mejora de audio"
```

Nada más. Los proyectores y las PCs se actualizan solos.

> **Guardá `android/keystore/njb-release.jks` y `android/key.properties` en un lugar seguro.**
> Están fuera de git a propósito. Sin esa clave no se pueden instalar actualizaciones
> sobre las apps ya instaladas.

---

## 5. Compilar localmente

```powershell
.\tools\compilar.ps1           # APK Android (todas las arquitecturas)
.\tools\compilar.ps1 -Windows  # ejecutable Windows
flutter test                   # tests
```

`compilar.ps1` toma el repositorio de GitHub del remoto `origin` y lo embebe en la app
(`--dart-define=UPDATE_REPO=usuario/repo`); sin remoto, la app no busca actualizaciones.

---

## 6. Estructura

```
lib/
  core/        app_config (puerto, canales, repo), app_version, mirroring_manager (emisor)
  services/    signaling (WebSocket + WebRTC), discovery (mDNS + barrido), update, screen_guardian
  ui/pages     home, projector_mode (emisor), receiver_mode (receptor)
android/app/src/main/kotlin/com/njb/proyectores/
  ScreenGuardian.kt       capas anti-screensaver + ajustes de sistema
  ApkInstaller.kt         instalación de actualizaciones (PackageInstaller)
  MediaProjectionService  servicio en primer plano para capturar en Android 14+
tools/                    scripts PowerShell: publicar, compilar, configurar_proyector, secrets_github
.github/workflows/        ci (analyze + test) y release (APK + Windows a Releases)
```

Protocolo de red: el receptor escucha en el puerto 8080. `GET /info` devuelve
`{app, name, version, platform}` y sirve para descubrirlo; cualquier otra ruta acepta
WebSocket con mensajes `hello`, `offer`, `answer`, `candidate`, `settings_update`, `bye`.
