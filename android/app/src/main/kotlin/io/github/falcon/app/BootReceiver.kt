package io.github.falcon.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Starts [FalconGatewayService] on device boot or app update when `start_on_boot`
 * is enabled in `falcon_runtime_prefs`.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val prefs = context.getSharedPreferences(FalconGatewayService.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("start_on_boot", false)) {
            return
        }
        val serviceIntent = Intent(context, FalconGatewayService::class.java)
            .setAction(FalconGatewayService.ACTION_START)
        runCatching {
            ContextCompat.startForegroundService(context, serviceIntent)
        }
    }
}
