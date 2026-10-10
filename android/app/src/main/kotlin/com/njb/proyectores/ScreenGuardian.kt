package com.njb.proyectores

import android.Manifest
import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import android.view.WindowManager
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Mantiene despierto al proyector mientras la app está en modo receptor.
 *
 * Los proyectores chinos con Android suelen traer un protector de pantalla
 * propio (no el "Daydream" estándar) que ignora FLAG_KEEP_SCREEN_ON y que sólo
 * respeta apps que reproducen contenido multimedia (por eso YouTube lo evita).
 * Acá reproducimos todo lo que hace un reproductor de video, en capas:
 *
 *  1. WakeLock de pantalla brillante + FLAG_KEEP_SCREEN_ON.
 *  2. Pista de audio en silencio reproduciéndose en loop: `isMusicActive()` da
 *     true, que es lo que la mayoría de esos protectores consultan.
 *  3. MediaSession activa en estado PLAYING (lo mismo que YouTube/Netflix).
 *  4. Movimiento de mouse sintético cada 20 s dentro de nuestra ventana para
 *     reiniciar el contador de inactividad del sistema (funciona hasta
 *     Android 12; en 13+ el sistema lo bloquea y lo informamos como no disponible).
 *
 * Además, [applySystemSettings] apaga el protector a nivel sistema si la app
 * recibió WRITE_SECURE_SETTINGS / WRITE_SETTINGS por ADB (ver
 * tools/configurar_proyector.ps1). Esa es la solución definitiva.
 */
class ScreenGuardian(private val activity: Activity) {

    companion object {
        private const val TAG = "ScreenGuardian"
        private const val POKE_INTERVAL_SECONDS = 20L
        private const val SAMPLE_RATE = 44100
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var audioTrack: AudioTrack? = null
    private var mediaSession: MediaSession? = null
    private var pokeExecutor: ScheduledExecutorService? = null

    @Volatile private var running = false
    @Volatile private var pokeWorks = false

    fun start(): Map<String, Any> {
        if (running) return status()
        running = true

        activity.runOnUiThread {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        acquireWakeLock()
        startSilentAudio()
        startMediaSession()
        startPokeLoop()

        Log.i(TAG, "Guardián iniciado: ${status()}")
        return status()
    }

    fun stop() {
        if (!running) return
        running = false
        pokeExecutor?.shutdownNow()
        pokeExecutor = null
        pokeWorks = false

        try {
            mediaSession?.isActive = false
            mediaSession?.release()
        } catch (_: Throwable) {
        }
        mediaSession = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Throwable) {
        }
        audioTrack = null

        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        wakeLock = null
        Log.i(TAG, "Guardián detenido")
    }

    fun status(): Map<String, Any> {
        val cr = activity.contentResolver
        val screensaverEnabled = try {
            Settings.Secure.getInt(cr, "screensaver_enabled", 1) == 1
        } catch (_: Throwable) {
            true
        }
        return mapOf(
            "running" to running,
            "wakeLock" to (wakeLock?.isHeld == true),
            "silentAudio" to (audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING),
            "mediaSession" to (mediaSession?.isActive == true),
            "inputPoke" to pokeWorks,
            "canWriteSecureSettings" to canWriteSecureSettings(),
            "canWriteSystemSettings" to canWriteSystemSettings(),
            "systemScreensaverDisabled" to !screensaverEnabled,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    // -------------------------------------------------------------------------
    // Capa 1: WakeLock
    // -------------------------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        try {
            val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            val lock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "NJB:receptor"
            )
            lock.setReferenceCounted(false)
            lock.acquire()
            wakeLock = lock
        } catch (t: Throwable) {
            Log.w(TAG, "WakeLock no disponible: $t")
        }
    }

    // -------------------------------------------------------------------------
    // Capa 2: audio en silencio (isMusicActive == true)
    // -------------------------------------------------------------------------

    private fun startSilentAudio() {
        try {
            val frames = SAMPLE_RATE * 2 // 2 segundos de silencio en loop
            val bytes = frames * 2       // PCM 16 bit mono
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val format = AudioFormat.Builder()
                .setSampleRate(SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val track = AudioTrack(attrs, format, bytes, AudioTrack.MODE_STATIC, AudioManager.AUDIO_SESSION_ID_GENERATE)
            val silence = ShortArray(frames)
            track.write(silence, 0, frames)
            track.setLoopPoints(0, frames, -1)
            // Volumen mínimo pero no cero: algunos firmwares ignoran pistas a 0.
            track.setVolume(0.01f)
            track.play()
            audioTrack = track
        } catch (t: Throwable) {
            Log.w(TAG, "Audio silencioso no disponible: $t")
        }
    }

    // -------------------------------------------------------------------------
    // Capa 3: MediaSession "reproduciendo"
    // -------------------------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun startMediaSession() {
        try {
            val session = MediaSession(activity, "NJB Proyectores")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            }
            session.setCallback(object : MediaSession.Callback() {})
            session.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, "NJB Proyectores")
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, "Transmisión en vivo")
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, -1L)
                    .build()
            )
            session.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_STOP)
                    .setState(PlaybackState.STATE_PLAYING, 0L, 1.0f, SystemClock.elapsedRealtime())
                    .build()
            )
            session.isActive = true
            mediaSession = session
        } catch (t: Throwable) {
            Log.w(TAG, "MediaSession no disponible: $t")
        }
    }

    // -------------------------------------------------------------------------
    // Capa 4: actividad de usuario sintética
    // -------------------------------------------------------------------------

    private fun startPokeLoop() {
        val executor = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "njb-poke").apply { isDaemon = true } }
        pokeExecutor = executor
        executor.scheduleWithFixedDelay({
            if (!running) return@scheduleWithFixedDelay
            pokeWorks = pokeUserActivity()
        }, 5, POKE_INTERVAL_SECONDS, TimeUnit.SECONDS)
    }

    /** Debe correr fuera del hilo principal. Devuelve true si algún método funcionó. */
    private fun pokeUserActivity(): Boolean {
        // 1) PowerManager.userActivity (requiere DEVICE_POWER; algunos firmwares lo permiten).
        try {
            val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            val method = pm.javaClass.getMethod("userActivity", Long::class.javaPrimitiveType, Boolean::class.javaPrimitiveType)
            method.invoke(pm, SystemClock.uptimeMillis(), false)
            return true
        } catch (_: Throwable) {
        }

        // 2) Movimiento de mouse inyectado en nuestra propia ventana (hasta Android 12).
        try {
            val now = SystemClock.uptimeMillis()
            val event = MotionEvent.obtain(now, now, MotionEvent.ACTION_HOVER_MOVE, 1f, 1f, 0)
            event.source = InputDevice.SOURCE_MOUSE
            Instrumentation().sendPointerSync(event)
            event.recycle()
            return true
        } catch (t: Throwable) {
            Log.d(TAG, "Inyección de input no permitida en este Android: ${t.javaClass.simpleName}")
        }
        return false
    }

    // -------------------------------------------------------------------------
    // Solución definitiva: apagar el protector a nivel sistema
    // -------------------------------------------------------------------------

    private fun canWriteSecureSettings(): Boolean =
        activity.checkCallingOrSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun canWriteSystemSettings(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.System.canWrite(activity)

    /**
     * Intenta escribir los ajustes que controlan el protector de pantalla y el
     * apagado automático. Cada clave informa si se pudo aplicar.
     */
    fun applySystemSettings(): Map<String, Boolean> {
        val cr = activity.contentResolver
        val results = LinkedHashMap<String, Boolean>()

        fun secure(key: String, value: Int) {
            results["secure.$key"] = try {
                canWriteSecureSettings() && Settings.Secure.putInt(cr, key, value)
            } catch (t: Throwable) {
                false
            }
        }

        fun global(key: String, value: Int) {
            results["global.$key"] = try {
                canWriteSecureSettings() && Settings.Global.putInt(cr, key, value)
            } catch (t: Throwable) {
                false
            }
        }

        fun system(key: String, value: Int) {
            results["system.$key"] = try {
                canWriteSystemSettings() && Settings.System.putInt(cr, key, value)
            } catch (t: Throwable) {
                false
            }
        }

        // Protector de pantalla (Daydream) apagado y sin activarse al dormir/cargar.
        secure("screensaver_enabled", 0)
        secure("screensaver_activate_on_sleep", 0)
        secure("screensaver_activate_on_dock", 0)
        // Sin tiempo de "sueño" ni de "atención" (Android TV).
        secure("sleep_timeout", -1)
        secure("attentive_timeout", -1)
        // La pantalla nunca se apaga sola.
        system("screen_off_timeout", Int.MAX_VALUE)
        // Mantener encendido mientras está enchufado (AC | USB | inalámbrico).
        global("stay_on_while_plugged_in", 7)

        Log.i(TAG, "Ajustes de sistema aplicados: $results")
        return results
    }
}
