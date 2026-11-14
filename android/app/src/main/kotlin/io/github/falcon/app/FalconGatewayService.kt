package io.github.falcon.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.widget.Toast
import androidx.core.content.ContextCompat
import java.io.File
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Foreground service supervising the local Falcon core binary (`libfalcon_core.so`),
 * holding partial WakeLock and WifiLock, monitoring LAN IPv4 / DNS changes, and
 * exposing runtime state to Flutter.
 */
class FalconGatewayService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var defaultNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var lanNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var restoreNotificationRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        when (action) {
            ACTION_STOP -> {
                stopGateway(clearDesired = true)
                return START_NOT_STICKY
            }
            ACTION_COPY_ADDRESS -> {
                handleCopyAddress()
                if (!serviceRunning.get()) {
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                return START_STICKY
            }
            ACTION_UPDATE_NOTIFICATION -> {
                if (serviceRunning.get()) {
                    refreshNetworkSnapshot(this)
                    updateNotificationNow(this)
                    notifyStateChanged(this)
                }
                return if (serviceRunning.get()) START_STICKY else START_NOT_STICKY
            }
            null -> {
                // System restarted START_STICKY service: only resume if user still desires running.
                if (!isDesiredRunning(this)) {
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
            }
        }

        startGatewayInternal()
        return START_STICKY
    }

    override fun onDestroy() {
        val keepDesired = isDesiredRunning(this)
        stopSupervisorProcess()
        unregisterNetworkCallbacks()
        releaseLocks()
        serviceRunning.set(false)
        startedAtMs.set(0L)
        corePid.set(0)
        if (!keepDesired) {
            setDesiredRunning(this, false)
        }
        restoreNotificationRunnable?.let { mainHandler.removeCallbacks(it) }
        restoreNotificationRunnable = null
        notifyStateChanged(this)
        super.onDestroy()
    }

    private fun startGatewayInternal() {
        ensureNotificationChannel(this)
        setDesiredRunning(this, true)
        desiredRunning.set(true)
        refreshNetworkSnapshot(this)

        val notification = buildNotification(this, temporaryNotice = null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (serviceRunning.compareAndSet(false, true)) {
            startedAtMs.set(System.currentTimeMillis())
        }

        acquireLocks()
        registerNetworkCallbacks()
        startSupervisorIfNeeded()
        updateNotificationNow(this)
        notifyStateChanged(this)
    }

    private fun stopGateway(clearDesired: Boolean) {
        if (clearDesired) {
            setDesiredRunning(this, false)
        }
        desiredRunning.set(false)
        serviceRunning.set(false)
        startedAtMs.set(0L)
        stopSupervisorProcess()
        unregisterNetworkCallbacks()
        releaseLocks()
        stopForegroundCompat()
        notifyStateChanged(this)
        stopSelf()
    }

    private fun handleCopyAddress() {
        refreshNetworkSnapshot(this)
        val endpoint = primaryEndpoint(this)
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("Falcon Gateway", endpoint))

        mainHandler.post {
            Toast.makeText(applicationContext, "已复制地址：$endpoint", Toast.LENGTH_SHORT).show()
            if (serviceRunning.get()) {
                updateNotificationNow(this, temporaryNotice = "已复制 $endpoint")
                restoreNotificationRunnable?.let { mainHandler.removeCallbacks(it) }
                val restore = Runnable {
                    if (serviceRunning.get()) {
                        updateNotificationNow(this@FalconGatewayService, temporaryNotice = null)
                    }
                }
                restoreNotificationRunnable = restore
                mainHandler.postDelayed(restore, 2500L)
            }
        }
    }

    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                runCatching { acquire() }
            }
        }
        wakeLockHeld.set(wakeLock?.isHeld == true)

        if (wifiLock?.isHeld != true) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                @Suppress("DEPRECATION")
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wm.createWifiLock(mode, WIFI_LOCK_TAG).apply {
                setReferenceCounted(false)
                runCatching { acquire() }
            }
        }
        wifiLockHeld.set(wifiLock?.isHeld == true)
    }

    private fun releaseLocks() {
        runCatching {
            wakeLock?.let { if (it.isHeld) it.release() }
        }
        wakeLock = null
        wakeLockHeld.set(false)

        runCatching {
            wifiLock?.let { if (it.isHeld) it.release() }
        }
        wifiLock = null
        wifiLockHeld.set(false)
    }

    private fun registerNetworkCallbacks() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        if (defaultNetworkCallback == null) {
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = onNetworkChanged()
                override fun onLost(network: Network) = onNetworkChanged()
                override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                    onNetworkChanged()
                }
            }
            if (runCatching { cm.registerDefaultNetworkCallback(cb) }.isSuccess) {
                defaultNetworkCallback = cb
            }
        }

        if (lanNetworkCallback == null) {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
                .build()
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = onNetworkChanged()
                override fun onLost(network: Network) = onNetworkChanged()
                override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                    onNetworkChanged()
                }
            }
            if (runCatching { cm.registerNetworkCallback(request, cb) }.isSuccess) {
                lanNetworkCallback = cb
            }
        }
    }

    private fun unregisterNetworkCallbacks() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        defaultNetworkCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        defaultNetworkCallback = null
        lanNetworkCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        lanNetworkCallback = null
    }

    private fun onNetworkChanged() {
        val changed = refreshNetworkSnapshot(this)
        if (serviceRunning.get()) {
            updateNotificationNow(this)
        }
        if (changed) {
            notifyStateChanged(this)
        }
    }

    private fun startSupervisorIfNeeded() {
        val existing = supervisorThread.get()
        if (existing != null && existing.isAlive) {
            return
        }
        val runGen = supervisorGeneration.incrementAndGet()
        val thread = Thread({
            runSupervisorLoop(runGen)
        }, "FalconCoreSupervisor")
        thread.isDaemon = true
        supervisorThread.set(thread)
        thread.start()
    }

    private fun runSupervisorLoop(runGen: Long) {
        var backoffMs = 1_000L
        while (desiredRunning.get() && supervisorGeneration.get() == runGen) {
            val dataDir = File(filesDir, "falcon").apply { mkdirs() }
            val cacheSubDir = File(cacheDir, "falcon").apply { mkdirs() }
            val coreBin = File(applicationInfo.nativeLibraryDir, CORE_BINARY_NAME)
            val bunBin = File(applicationInfo.nativeLibraryDir, BUN_BINARY_NAME)

            if (!coreBin.exists() || !coreBin.canExecute()) {
                appendLog("[supervisor] core binary unavailable at ${coreBin.absolutePath}")
                notifyStateChanged(this)
                if (!sleepInterruptibly(backoffMs, runGen)) break
                backoffMs = (backoffMs * 2).coerceAtMost(30_000L)
                continue
            }

            val port = getGatewayPort(this)
            val adminToken = getOrCreateAdminToken(this)
            val dns = resolveActiveDns(this)

            val cmd = listOf(
                coreBin.absolutePath,
                "--data-dir", dataDir.absolutePath,
                "--cache-dir", cacheSubDir.absolutePath,
                "--gateway-port", port.toString(),
                "--admin-addr=$ADMIN_ADDR",
            )

            val process = try {
                ProcessBuilder(cmd).apply {
                    directory(dataDir)
                    redirectErrorStream(true)
                    environment().apply {
                        put("FALCON_DATA_DIR", dataDir.absolutePath)
                        put("FALCON_CACHE_DIR", cacheSubDir.absolutePath)
                        put("FALCON_BUN", bunBin.absolutePath)
                        put("FALCON_ADMIN_ADDR", ADMIN_ADDR)
                        put("FALCON_ADMIN_TOKEN", adminToken)
                        put("FALCON_GATEWAY_PORT", port.toString())
                        put("FALCON_DNS", dns)
                    }
                }.start()
            } catch (e: Exception) {
                appendLog("[supervisor] failed to start core: ${e.message ?: e.javaClass.simpleName}")
                notifyStateChanged(this)
                if (!sleepInterruptibly(backoffMs, runGen)) break
                backoffMs = (backoffMs * 2).coerceAtMost(30_000L)
                continue
            }

            currentProcess.set(process)
            val launchedAt = System.currentTimeMillis()
            val pid = extractPid(process)
            corePid.set(pid)
            appendLog("[supervisor] started libfalcon_core.so pid=$pid port=$port dns=$dns")
            notifyStateChanged(this)

            try {
                process.inputStream.bufferedReader().use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        appendLog(line)
                    }
                }
            } catch (_: Exception) {
                // Stream closed during shutdown.
            }

            val exitCode = runCatching { process.waitFor() }.getOrElse { -1 }
            currentProcess.compareAndSet(process, null)
            corePid.set(0)
            appendLog("[supervisor] libfalcon_core.so exited with code=$exitCode")
            notifyStateChanged(this)

            if (!desiredRunning.get() || supervisorGeneration.get() != runGen) {
                break
            }

            backoffMs = if (System.currentTimeMillis() - launchedAt >= 15_000L) {
                1_000L
            } else {
                (backoffMs * 2).coerceAtMost(30_000L)
            }
            appendLog("[supervisor] restarting in ${backoffMs}ms")
            if (!sleepInterruptibly(backoffMs, runGen)) break
        }
    }

    private fun sleepInterruptibly(durationMs: Long, runGen: Long): Boolean {
        val deadline = System.currentTimeMillis() + durationMs
        while (desiredRunning.get() && supervisorGeneration.get() == runGen) {
            val remaining = deadline - System.currentTimeMillis()
            if (remaining <= 0L) return true
            try {
                Thread.sleep(remaining.coerceAtMost(250L))
            } catch (_: InterruptedException) {
                if (!desiredRunning.get() || supervisorGeneration.get() != runGen) return false
            }
        }
        return false
    }

    private fun stopSupervisorProcess() {
        desiredRunning.set(false)
        supervisorGeneration.incrementAndGet()
        val proc = currentProcess.getAndSet(null)
        if (proc != null) {
            runCatching { proc.destroy() }
            val deadline = System.currentTimeMillis() + 1_200L
            while (System.currentTimeMillis() < deadline) {
                if (runCatching { proc.exitValue() }.isSuccess) break
                runCatching { Thread.sleep(50L) }
            }
            if (runCatching { proc.exitValue() }.isFailure) {
                runCatching { proc.destroyForcibly() }
            }
        }
        supervisorThread.getAndSet(null)?.interrupt()
        corePid.set(0)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        const val PREFS_NAME = "falcon_runtime_prefs"
        private const val KEY_ADMIN_TOKEN = "admin_token"
        private const val KEY_START_ON_BOOT = "start_on_boot"
        private const val KEY_DESIRED_RUNNING = "desired_running"
        private const val KEY_GATEWAY_PORT = "gateway_port"
        private const val KEY_LAN_ENABLED = "lan_enabled"

        const val DEFAULT_GATEWAY_PORT = 18787
        const val ADMIN_PORT = 18788
        const val ADMIN_ADDR = "127.0.0.1:$ADMIN_PORT"
        const val ADMIN_BASE_URL = "http://$ADMIN_ADDR"
        private const val FALLBACK_DNS = "223.5.5.5,119.29.29.29,8.8.8.8,1.1.1.1"

        private const val CORE_BINARY_NAME = "libfalcon_core.so"
        private const val BUN_BINARY_NAME = "libbun.so"
        private const val WAKE_LOCK_TAG = "Falcon::GatewayWakeLock"
        private const val WIFI_LOCK_TAG = "Falcon::GatewayWifiLock"

        private const val CHANNEL_ID = "falcon_gateway_status"
        private const val NOTIFICATION_ID = 4080
        private const val MAX_LOG_LINES = 100

        const val ACTION_START = "io.github.falcon.app.action.START_GATEWAY"
        const val ACTION_STOP = "io.github.falcon.app.action.STOP_GATEWAY"
        const val ACTION_COPY_ADDRESS = "io.github.falcon.app.action.COPY_ADDRESS"
        const val ACTION_UPDATE_NOTIFICATION = "io.github.falcon.app.action.UPDATE_NOTIFICATION"

        private val serviceRunning = AtomicBoolean(false)
        private val desiredRunning = AtomicBoolean(false)
        private val wakeLockHeld = AtomicBoolean(false)
        private val wifiLockHeld = AtomicBoolean(false)
        private val startedAtMs = AtomicLong(0L)
        private val corePid = AtomicInteger(0)
        private val supervisorGeneration = AtomicLong(0L)
        private val supervisorThread = AtomicReference<Thread?>(null)
        private val currentProcess = AtomicReference<Process?>(null)
        private val cachedLanIpv4s = AtomicReference<List<String>>(emptyList())
        private val cachedDns = AtomicReference<String>(FALLBACK_DNS)
        private val logLock = Any()
        private val logBuffer = ArrayDeque<String>(MAX_LOG_LINES)
        private val stateListeners = CopyOnWriteArraySet<(Map<String, Any>) -> Unit>()
        private val mainUiHandler = Handler(Looper.getMainLooper())

        val isRunning: Boolean get() = serviceRunning.get()
        val currentCorePid: Int get() = corePid.get()

        fun addStateListener(listener: (Map<String, Any>) -> Unit) {
            stateListeners.add(listener)
        }

        fun removeStateListener(listener: (Map<String, Any>) -> Unit) {
            stateListeners.remove(listener)
        }

        fun start(context: Context) {
            val intent = Intent(context, FalconGatewayService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            if (!serviceRunning.get() && !isDesiredRunning(context)) return
            val intent = Intent(context, FalconGatewayService::class.java).setAction(ACTION_STOP)
            runCatching { context.startService(intent) }
        }

        fun updateSummary(context: Context, lanEnabled: Boolean, port: Int) {
            prefs(context).edit()
                .putBoolean(KEY_LAN_ENABLED, lanEnabled)
                .putInt(KEY_GATEWAY_PORT, port)
                .apply()
            if (serviceRunning.get()) {
                val intent = Intent(context, FalconGatewayService::class.java)
                    .setAction(ACTION_UPDATE_NOTIFICATION)
                runCatching { context.startService(intent) }
                updateNotificationNow(context)
                notifyStateChanged(context)
            }
        }

        fun isStartOnBoot(context: Context): Boolean =
            prefs(context).getBoolean(KEY_START_ON_BOOT, false)

        fun setStartOnBoot(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_START_ON_BOOT, enabled).apply()
            notifyStateChanged(context)
        }

        fun isDesiredRunning(context: Context): Boolean =
            prefs(context).getBoolean(KEY_DESIRED_RUNNING, false)

        private fun setDesiredRunning(context: Context, running: Boolean) {
            prefs(context).edit().putBoolean(KEY_DESIRED_RUNNING, running).apply()
        }

        fun getGatewayPort(context: Context): Int =
            prefs(context).getInt(KEY_GATEWAY_PORT, DEFAULT_GATEWAY_PORT)

        fun isLanEnabled(context: Context): Boolean =
            prefs(context).getBoolean(KEY_LAN_ENABLED, false)

        @Synchronized
        fun getOrCreateAdminToken(context: Context): String {
            val p = prefs(context)
            val existing = p.getString(KEY_ADMIN_TOKEN, null)
            if (!existing.isNullOrBlank() && existing.length == 32) {
                return existing
            }
            val bytes = ByteArray(16)
            SecureRandom().nextBytes(bytes)
            val token = bytes.joinToString("") { "%02x".format(it) }
            p.edit().putString(KEY_ADMIN_TOKEN, token).commit()
            return token
        }

        fun hasCoreBinary(context: Context): Boolean =
            File(context.applicationInfo.nativeLibraryDir, CORE_BINARY_NAME).exists()

        fun isAdminPortOpen(): Boolean {
            return try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", ADMIN_PORT), 120)
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun buildRuntimeStatusMap(context: Context): Map<String, Any> {
            refreshNetworkSnapshot(context)
            val running = serviceRunning.get()
            val startMs = startedAtMs.get()
            val uptime = if (running && startMs > 0L) {
                (System.currentTimeMillis() - startMs).coerceAtLeast(0L)
            } else {
                0L
            }
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val batteryIgnored = runCatching {
                pm.isIgnoringBatteryOptimizations(context.packageName)
            }.getOrDefault(false)

            val notifGranted = isNotificationPermissionGranted(context)
            val logsSnapshot = synchronized(logLock) { logBuffer.toList() }

            return mapOf(
                "running" to running,
                "adminBaseUrl" to ADMIN_BASE_URL,
                "adminToken" to getOrCreateAdminToken(context),
                "lanIpv4s" to cachedLanIpv4s.get(),
                "platform" to "android",
                "keepScreenAwake" to false,
                "backgroundAudioKeepAlive" to false,
                "batteryOptimizationIgnored" to batteryIgnored,
                "notificationPermissionGranted" to notifGranted,
                "wakeLockHeld" to wakeLockHeld.get(),
                "wifiLockHeld" to wifiLockHeld.get(),
                "startOnBoot" to isStartOnBoot(context),
                "uptimeMs" to uptime,
                "corePid" to corePid.get(),
                "lastLogs" to logsSnapshot,
            )
        }

        fun isNotificationPermissionGranted(context: Context): Boolean {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val systemEnabled = nm.areNotificationsEnabled()
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                systemEnabled && ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                systemEnabled
            }
        }

        fun notifyStateChanged(context: Context) {
            if (stateListeners.isEmpty()) return
            val snapshot = buildRuntimeStatusMap(context.applicationContext)
            mainUiHandler.post {
                for (listener in stateListeners) {
                    runCatching { listener(snapshot) }
                }
            }
        }

        private fun prefs(context: Context) =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        private fun appendLog(line: String) {
            synchronized(logLock) {
                if (logBuffer.size >= MAX_LOG_LINES) {
                    logBuffer.removeFirst()
                }
                logBuffer.addLast(line)
            }
        }

        private fun extractPid(process: Process): Int {
            runCatching {
                val method = process.javaClass.getMethod("pid")
                val value = method.invoke(process) as? Number
                if (value != null) return value.toInt()
            }
            runCatching {
                val field = process.javaClass.getDeclaredField("pid")
                field.isAccessible = true
                return field.getInt(process)
            }
            return 0
        }

        private fun resolveActiveDns(context: Context): String {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val servers = runCatching {
                cm.getLinkProperties(cm.activeNetwork)?.dnsServers
            }.getOrNull().orEmpty()
                .mapNotNull { it.hostAddress?.substringBefore('%')?.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
            val joined = if (servers.isNotEmpty()) servers.joinToString(",") else FALLBACK_DNS
            cachedDns.set(joined)
            return joined
        }

        private fun isValidLanIpv4(addr: Inet4Address): Boolean {
            if (addr.isLoopbackAddress ||
                addr.isLinkLocalAddress ||
                addr.isMulticastAddress ||
                addr.isAnyLocalAddress
            ) {
                return false
            }
            val raw = addr.address
            if (raw.size != 4) return false
            val b0 = raw[0].toInt() and 0xFF
            val b1 = raw[1].toInt() and 0xFF
            // Filter Clash / Sing-box TUN fake-IP subnet 198.18.0.0/15
            if (b0 == 198 && (b1 == 18 || b1 == 19)) {
                return false
            }
            return true
        }

        private fun isRfc1918(ip: String): Boolean {
            val parts = ip.split('.')
            if (parts.size != 4) return false
            val a = parts[0].toIntOrNull() ?: return false
            val b = parts[1].toIntOrNull() ?: return false
            if (a == 10) return true
            if (a == 172 && b in 16..31) return true
            return a == 192 && b == 168
        }

        @Suppress("DEPRECATION")
        private fun refreshNetworkSnapshot(context: Context): Boolean {
            val prevIps = cachedLanIpv4s.get()
            val prevDns = cachedDns.get()

            val discovered = LinkedHashSet<String>()
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            // Prefer Wi-Fi / Ethernet LinkProperties reported by ConnectivityManager.
            runCatching {
                for (network in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(network) ?: continue
                    val isLanTransport = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                    if (!isLanTransport) continue
                    val lp = cm.getLinkProperties(network) ?: continue
                    val ifaceName = lp.interfaceName?.lowercase().orEmpty()
                    if (ifaceName.startsWith("tun") ||
                        ifaceName.startsWith("utun") ||
                        ifaceName.startsWith("ppp") ||
                        ifaceName.startsWith("wg")
                    ) {
                        continue
                    }
                    for (linkAddr in lp.linkAddresses) {
                        val addr = linkAddr.address
                        if (addr is Inet4Address && isValidLanIpv4(addr)) {
                            addr.hostAddress?.let { discovered.add(it) }
                        }
                    }
                }
            }

            // Fallback / hotspot interfaces via NetworkInterface enumeration.
            runCatching {
                val ifaces = NetworkInterface.getNetworkInterfaces()
                while (ifaces != null && ifaces.hasMoreElements()) {
                    val nif = ifaces.nextElement()
                    if (!nif.isUp || nif.isLoopback) continue
                    val name = nif.name.lowercase()
                    if (name.startsWith("rmnet") ||
                        name.startsWith("ccmni") ||
                        name.startsWith("pdp") ||
                        name.startsWith("clat") ||
                        name.startsWith("tun") ||
                        name.startsWith("utun") ||
                        name.startsWith("ppp") ||
                        name.startsWith("wg") ||
                        name.startsWith("dummy")
                    ) {
                        continue
                    }
                    val addrs = nif.inetAddresses
                    while (addrs.hasMoreElements()) {
                        val addr = addrs.nextElement()
                        if (addr is Inet4Address && isValidLanIpv4(addr)) {
                            addr.hostAddress?.let { discovered.add(it) }
                        }
                    }
                }
            }

            val nextIps = discovered.sortedWith(
                compareByDescending<String> { isRfc1918(it) }.thenBy { it },
            )
            cachedLanIpv4s.set(nextIps)
            val nextDns = resolveActiveDns(context)
            return nextIps != prevIps || nextDns != prevDns
        }

        private fun primaryEndpoint(context: Context): String {
            val port = getGatewayPort(context)
            val lanEnabled = isLanEnabled(context)
            val ip = cachedLanIpv4s.get().firstOrNull()
            return if (lanEnabled && ip != null) {
                "http://$ip:$port"
            } else {
                "http://127.0.0.1:$port"
            }
        }

        private fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Falcon 网关状态",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持 Falcon 本地与局域网 AI 网关在后台运行"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        private fun updateNotificationNow(context: Context, temporaryNotice: String? = null) {
            if (!serviceRunning.get()) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification(context, temporaryNotice))
        }

        private fun buildNotification(context: Context, temporaryNotice: String?): Notification {
            val port = getGatewayPort(context)
            val lanEnabled = isLanEnabled(context)
            val primaryIp = cachedLanIpv4s.get().firstOrNull()

            val contentText = temporaryNotice ?: if (lanEnabled && primaryIp != null) {
                "局域网 $primaryIp:$port · 本机 127.0.0.1:$port"
            } else {
                "本机 127.0.0.1:$port（仅限本机访问）"
            }

            val launchIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val copyIntent = PendingIntent.getService(
                context,
                1,
                Intent(context, FalconGatewayService::class.java).setAction(ACTION_COPY_ADDRESS),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val stopIntent = PendingIntent.getService(
                context,
                2,
                Intent(context, FalconGatewayService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            return builder
                .setSmallIcon(R.drawable.ic_stat_falcon)
                .setContentTitle("Falcon 网关运行中")
                .setContentText(contentText)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(launchIntent)
                .addAction(Notification.Action.Builder(null, "复制地址", copyIntent).build())
                .addAction(Notification.Action.Builder(null, "停止", stopIntent).build())
                .build()
        }
    }
}
