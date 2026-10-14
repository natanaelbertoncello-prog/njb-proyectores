package com.njb.proyectores

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SERVICE_CHANNEL = "com.njb.proyectores/service"
        private const val GUARDIAN_CHANNEL = "com.njb.proyectores/screen_guardian"
        private const val UPDATER_CHANNEL = "com.njb.proyectores/updater"
        private const val SHARE_CHANNEL = "com.njb.proyectores/share"
        private const val SCREEN_CAPTURE_REQUEST_CODE = 1001
    }

    private var pendingResult: MethodChannel.Result? = null
    private lateinit var guardian: ScreenGuardian
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        guardian = ScreenGuardian(this)
        pendingSharedText = extractSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent) ?: return
        val channel = shareChannel
        if (channel != null) {
            channel.invokeMethod("onSharedText", text)
        } else {
            pendingSharedText = text
        }
    }

    /** "Compartir con NJB Proyectores" desde Chrome, YouTube, etc. */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }?.takeIf { it.isNotBlank() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // --- Captura de pantalla (lado emisor) -------------------------------
        MethodChannel(messenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMirroringFlow" -> {
                    pendingResult?.success(false)
                    pendingResult = result
                    startScreenCaptureWithService()
                }
                "stopService" -> {
                    val intent = Intent(this, MediaProjectionService::class.java).apply {
                        action = MediaProjectionService.ACTION_STOP
                    }
                    try {
                        startService(intent)
                    } catch (_: Throwable) {
                    }
                    result.success(null)
                }
                "adjustVolume" -> {
                    // Volumen del sistema (lado receptor): +1 / -1 / silenciar.
                    val direction = call.argument<String>("direction") ?: "up"
                    try {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val dir = when (direction) {
                            "down" -> AudioManager.ADJUST_LOWER
                            "mute" -> AudioManager.ADJUST_TOGGLE_MUTE
                            else -> AudioManager.ADJUST_RAISE
                        }
                        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(if (max > 0) cur * 100 / max else 0)
                    } catch (t: Throwable) {
                        result.success(-1)
                    }
                }
                "multicastLock" -> {
                    // Necesario para recibir SSDP (botón "Transmitir" de YouTube).
                    val on = call.argument<Boolean>("on") ?: true
                    try {
                        if (on) {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("njb-ssdp").apply { setReferenceCounted(false) }
                            }
                            multicastLock?.acquire()
                        } else {
                            if (multicastLock?.isHeld == true) multicastLock?.release()
                        }
                        result.success(true)
                    } catch (t: Throwable) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- Guardián anti-screensaver (lado receptor) -----------------------
        MethodChannel(messenger, GUARDIAN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(guardian.start())
                "stop" -> {
                    guardian.stop()
                    result.success(null)
                }
                "status" -> result.success(guardian.status())
                "applySystemSettings" -> result.success(guardian.applySystemSettings())
                else -> result.notImplemented()
            }
        }

        // --- Compartir desde otras apps ---------------------------------------
        shareChannel = MethodChannel(messenger, SHARE_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedText" -> {
                        result.success(pendingSharedText)
                        pendingSharedText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // --- Actualizador ----------------------------------------------------
        MethodChannel(messenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "Falta la ruta de la APK", null)
                    } else {
                        try {
                            result.success(ApkInstaller.install(this, path))
                        } catch (t: Throwable) {
                            result.error("INSTALL", t.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startScreenCaptureWithService() {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCREEN_CAPTURE_REQUEST_CODE) return

        if (resultCode == Activity.RESULT_OK && data != null) {
            val serviceIntent = Intent(this, MediaProjectionService::class.java).apply {
                action = MediaProjectionService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            // Le damos un instante al servicio para pasar a primer plano antes
            // de que flutter_webrtc cree la MediaProjection (requisito Android 14+).
            Handler(Looper.getMainLooper()).postDelayed({
                pendingResult?.success(true)
                pendingResult = null
            }, 300)
        } else {
            pendingResult?.success(false)
            pendingResult = null
        }
    }

    override fun onDestroy() {
        guardian.stop()
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }
}
