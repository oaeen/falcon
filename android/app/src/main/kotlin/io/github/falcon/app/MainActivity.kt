package io.github.falcon.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var pendingNotifResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var serviceStateListener: ((Map<String, Any>) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                serviceStateListener?.let { FalconGatewayService.removeStateListener(it) }
                val listener: (Map<String, Any>) -> Unit = { status ->
                    eventSink?.success(status)
                }
                serviceStateListener = listener
                FalconGatewayService.addStateListener(listener)
                events?.success(FalconGatewayService.buildRuntimeStatusMap(applicationContext))
            }

            override fun onCancel(arguments: Any?) {
                serviceStateListener?.let { FalconGatewayService.removeStateListener(it) }
                serviceStateListener = null
                eventSink = null
            }
        })
    }

    override fun onResume() {
        super.onResume()
        if (eventSink != null) {
            FalconGatewayService.notifyStateChanged(applicationContext)
        }
    }

    override fun onDestroy() {
        serviceStateListener?.let { FalconGatewayService.removeStateListener(it) }
        serviceStateListener = null
        eventSink = null
        pendingNotifResult = null
        backgroundExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val pending = pendingNotifResult
            pendingNotifResult = null
            val granted = (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) ||
                FalconGatewayService.isNotificationPermissionGranted(applicationContext)
            pending?.success(granted)
            if (eventSink != null) {
                FalconGatewayService.notifyStateChanged(applicationContext)
            }
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startGateway" -> handleStartGateway(result)
            "stopGateway" -> handleStopGateway(result)
            "getRuntimeStatus" -> {
                result.success(FalconGatewayService.buildRuntimeStatusMap(applicationContext))
            }
            "requestBatteryOptimizationExemption" -> {
                result.success(handleRequestBatteryOptimizationExemption())
            }
            "openAppBatterySettings" -> {
                handleOpenAppBatterySettings()
                result.success(true)
            }
            "requestNotificationPermission" -> handleRequestNotificationPermission(result)
            "setStartOnBoot" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                FalconGatewayService.setStartOnBoot(applicationContext, enabled)
                result.success(enabled)
            }
            "updateNotificationSummary" -> {
                val lanEnabled = call.argument<Boolean>("lanEnabled") ?: false
                val port = (call.argument<Number>("port")?.toInt())
                    ?: FalconGatewayService.DEFAULT_GATEWAY_PORT
                FalconGatewayService.updateSummary(applicationContext, lanEnabled, port)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleStartGateway(result: MethodChannel.Result) {
        val ctx = applicationContext
        FalconGatewayService.start(ctx)
        backgroundExecutor.execute {
            val hasCore = FalconGatewayService.hasCoreBinary(ctx)
            val deadline = System.currentTimeMillis() + if (hasCore) 3_000L else 500L
            while (System.currentTimeMillis() < deadline) {
                val running = FalconGatewayService.isRunning
                if (running && (!hasCore || FalconGatewayService.isAdminPortOpen())) {
                    break
                }
                try {
                    Thread.sleep(80L)
                } catch (_: InterruptedException) {
                    break
                }
            }
            val status = FalconGatewayService.buildRuntimeStatusMap(ctx)
            runOnUiThread { result.success(status) }
        }
    }

    private fun handleStopGateway(result: MethodChannel.Result) {
        val ctx = applicationContext
        FalconGatewayService.stop(ctx)
        backgroundExecutor.execute {
            val deadline = System.currentTimeMillis() + 1_200L
            while (System.currentTimeMillis() < deadline && FalconGatewayService.isRunning) {
                try {
                    Thread.sleep(60L)
                } catch (_: InterruptedException) {
                    break
                }
            }
            val status = FalconGatewayService.buildRuntimeStatusMap(ctx)
            runOnUiThread { result.success(status) }
        }
    }

    @SuppressLint("BatteryLife")
    private fun handleRequestBatteryOptimizationExemption(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val ignored = runCatching { pm.isIgnoringBatteryOptimizations(packageName) }.getOrDefault(false)
        if (!ignored) {
            val directIntent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
            val launched = runCatching { startActivity(directIntent) }.isSuccess
            if (!launched) {
                runCatching {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        }
        return runCatching { pm.isIgnoringBatteryOptimizations(packageName) }.getOrDefault(false)
    }

    private fun handleOpenAppBatterySettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        runCatching { startActivity(intent) }
    }

    private fun handleRequestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(FalconGatewayService.isNotificationPermissionGranted(applicationContext))
            return
        }
        if (FalconGatewayService.isNotificationPermissionGranted(applicationContext)) {
            result.success(true)
            return
        }
        pendingNotifResult?.success(false)
        pendingNotifResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIFICATIONS)
    }

    companion object {
        private const val METHOD_CHANNEL = "falcon/platform"
        private const val EVENT_CHANNEL = "falcon/runtime_events"
        private const val REQ_POST_NOTIFICATIONS = 4081
    }
}
