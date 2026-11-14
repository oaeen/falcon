package io.github.falcon.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Restarts [FalconGatewayService] on boot (`start_on_boot`) or after an in-place
 * package upgrade (`ACTION_MY_PACKAGE_REPLACED` while `desired_running` was true).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val shouldStart = when (action) {
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                runCatching {
                    FalconGatewayService.isDesiredRunning(context) ||
                        FalconGatewayService.isStartOnBoot(context)
                }.getOrDefault(false)
            }
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                runCatching {
                    FalconGatewayService.isStartOnBoot(context)
                }.getOrDefault(false)
            }
            else -> false
        }
        if (!shouldStart) {
            return
        }
        val serviceIntent = Intent(context, FalconGatewayService::class.java)
            .setAction(FalconGatewayService.ACTION_START)
        runCatching {
            ContextCompat.startForegroundService(context, serviceIntent)
        }
    }
}
