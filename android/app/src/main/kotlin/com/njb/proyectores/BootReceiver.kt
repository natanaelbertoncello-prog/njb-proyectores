package com.njb.proyectores

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Al encender el proyector, abre la app si el usuario marcó
 * "Este equipo es el proyector" (la app entra sola en modo receptor).
 *
 * Android 10+ restringe abrir pantallas desde segundo plano; en proyectores y
 * TV boxes chinos suele funcionar igual. Si no, la app queda a un toque en el
 * launcher.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        // shared_preferences de Flutter guarda las claves con prefijo "flutter."
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val autoReceiver = prefs.getBoolean("flutter.autoReceiver", false)
        if (!autoReceiver) return

        Log.i("BootReceiver", "Arranque automático del modo receptor")
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try {
            context.startActivity(launch)
        } catch (t: Throwable) {
            Log.w("BootReceiver", "No se pudo abrir la app al inicio: $t")
        }
    }
}
