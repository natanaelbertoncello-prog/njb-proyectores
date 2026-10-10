package com.njb.proyectores

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import java.io.File

/**
 * Instala una APK descargada usando la API PackageInstaller.
 *
 * - La primera vez el sistema pide confirmación en pantalla.
 * - A partir de Android 12, una vez que esta app es "instalador de registro"
 *   de sí misma, las siguientes actualizaciones se aplican sin preguntar.
 */
object ApkInstaller {
    private const val TAG = "ApkInstaller"
    const val ACTION_INSTALL_RESULT = "com.njb.proyectores.INSTALL_RESULT"

    fun install(context: Context, path: String): String {
        val file = File(path)
        require(file.exists() && file.length() > 0) { "La APK no existe: $path" }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            } catch (t: Throwable) {
                Log.w(TAG, "No se pudo abrir la pantalla de 'apps desconocidas': $t")
            }
            return "needs_permission"
        }

        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }

        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            session.openWrite("njb-update.apk", 0, file.length()).use { out ->
                file.inputStream().use { input -> input.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(context, InstallResultReceiver::class.java).setAction(ACTION_INSTALL_RESULT)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pending.intentSender)
        } catch (t: Throwable) {
            session.abandon()
            throw t
        } finally {
            session.close()
        }
        return "started"
    }
}

class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirm)
                    } catch (t: Throwable) {
                        Log.e("ApkInstaller", "No se pudo abrir la confirmación: $t")
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Toast.makeText(context, "NJB Proyectores actualizado", Toast.LENGTH_LONG).show()
            }
            else -> {
                Log.e("ApkInstaller", "Instalación falló ($status): $message")
                Toast.makeText(context, "No se pudo actualizar: ${message ?: status}", Toast.LENGTH_LONG).show()
            }
        }
    }
}
