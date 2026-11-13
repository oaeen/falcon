import AVFoundation
import Darwin
import Flutter
import Foundation
import Network
import Security
import UIKit
import UserNotifications

/// Native iOS platform bridge implementing `falcon/platform` MethodChannel and
/// `falcon/runtime_events` EventChannel for the embedded Go Falcon gateway.
@objcMembers
public final class FalconPlatformPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "falcon/platform"
  private static let eventChannelName = "falcon/runtime_events"

  private static let defaultGatewayPort = 18787
  private static let adminPort: UInt16 = 18788
  private static let adminAddr = "127.0.0.1:18788"
  private static let adminBaseUrl = "http://127.0.0.1:18788"
  private static let defaultDnsServers = "223.5.5.5,119.29.29.29,8.8.8.8,1.1.1.1"
  private static let maxLogLines = 120

  private enum PrefKeys {
    static let gatewayPort = "falcon.ios.gateway_port"
    static let lanEnabled = "falcon.ios.lan_enabled"
    static let adminToken = "falcon.ios.admin_token"
    static let keepScreenAwake = "falcon.ios.keep_screen_awake"
    static let backgroundAudioKeepAlive = "falcon.ios.background_audio_keep_alive"
  }

  private let defaults = UserDefaults.standard
  private let workerQueue = DispatchQueue(label: "io.github.falcon.app.platform.worker", qos: .userInitiated)
  private let stateLock = NSLock()

  private var eventSink: FlutterEventSink?
  private var isRunning = false
  private var startedAtMs: Int64 = 0
  private var logs: [String] = []
  private var notificationGranted = false

  private var audioPlayer: AVAudioPlayer?
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private var pathMonitor: NWPathMonitor?
  private var lastLanIpv4s: [String] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FalconPlatformPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public override init() {
    super.init()
    _ = getOrCreateAdminToken()
    lastLanIpv4s = Self.enumerateLanIpv4s()
    registerObservers()
    refreshNotificationStatus(emitAfter: false)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    pathMonitor?.cancel()
    pathMonitor = nil
    stopSilentAudioPlayer()
  }

  // MARK: - FlutterPlugin

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startGateway":
      let args = call.arguments as? [String: Any]
      if let portArg = args?["port"] as? NSNumber, portArg.intValue > 0 {
        defaults.set(portArg.intValue, forKey: PrefKeys.gatewayPort)
      }
      handleStartGateway(result: result)

    case "stopGateway":
      handleStopGateway(result: result)

    case "getRuntimeStatus":
      refreshNotificationStatus(emitAfter: false) { [weak self] in
        guard let self = self else {
          result([:])
          return
        }
        result(self.buildStatusMap())
      }

    case "requestNotificationPermission":
      handleRequestNotificationPermission(result: result)

    case "setKeepScreenAwake":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      handleSetKeepScreenAwake(enabled: enabled, result: result)

    case "setIosBackgroundAudioKeepAlive":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      handleSetBackgroundAudioKeepAlive(enabled: enabled, result: result)

    case "updateNotificationSummary":
      let args = call.arguments as? [String: Any]
      let lanEnabled = (args?["lanEnabled"] as? Bool) ?? defaults.bool(forKey: PrefKeys.lanEnabled)
      let port = (args?["port"] as? NSNumber)?.intValue ?? configuredGatewayPort()
      defaults.set(lanEnabled, forKey: PrefKeys.lanEnabled)
      if port > 0 && port <= 65535 {
        defaults.set(port, forKey: PrefKeys.gatewayPort)
      }
      emitStatusSnapshot()
      result(true)

    case "requestBatteryOptimizationExemption":
      // iOS does not have Android-style battery optimization exemption prompts.
      result(true)

    case "openAppBatterySettings":
      DispatchQueue.main.async {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
      }
      result(true)

    case "setStartOnBoot":
      // iOS does not permit third-party apps to auto-launch at boot.
      result(false)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stateLock.lock()
    eventSink = events
    stateLock.unlock()

    startPathMonitorIfNeeded()
    refreshNotificationStatus(emitAfter: true)
    emitStatusSnapshot()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stateLock.lock()
    eventSink = nil
    stateLock.unlock()
    return nil
  }

  // MARK: - Gateway Lifecycle

  private func handleStartGateway(result: @escaping FlutterResult) {
    let port = configuredGatewayPort()
    let token = getOrCreateAdminToken()
    let dataDir = ensureDirectory(in: .applicationSupportDirectory, subpath: "falcon")
    let cacheDir = ensureDirectory(in: .cachesDirectory, subpath: "falcon")

    workerQueue.async { [weak self] in
      guard let self = self else { return }

      let rc = dataDir.withCString { dataPtr in
        cacheDir.withCString { cachePtr in
          Self.adminAddr.withCString { adminPtr in
            token.withCString { tokenPtr in
              Self.defaultDnsServers.withCString { dnsPtr in
                FalconStart(dataPtr, cachePtr, Int32(port), adminPtr, tokenPtr, dnsPtr)
              }
            }
          }
        }
      }

      if rc == 0 {
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
          if self.isLocalTcpPortOpen(port: Self.adminPort) {
            break
          }
          if let coreStatus = self.readCoreStatusJson(),
             (coreStatus["running"] as? Bool) == true {
            break
          }
          Thread.sleep(forTimeInterval: 0.06)
        }

        self.stateLock.lock()
        self.isRunning = true
        if self.startedAtMs == 0 {
          self.startedAtMs = Self.nowMs()
        }
        self.stateLock.unlock()

        self.appendLog("[ios] gateway started on port \(port) (admin \(Self.adminAddr))")

        DispatchQueue.main.async {
          if self.isKeepScreenAwakeEnabled() {
            UIApplication.shared.isIdleTimerDisabled = true
          }
          if self.isBackgroundAudioKeepAliveEnabled() {
            self.startSilentAudioPlayer()
          }
        }
      } else {
        let coreStatus = self.readCoreStatusJson()
        let errMsg = (coreStatus?["error"] as? String) ?? "FalconStart returned code \(rc)"
        self.stateLock.lock()
        self.isRunning = false
        self.startedAtMs = 0
        self.stateLock.unlock()
        self.appendLog("[ios] failed to start gateway: \(errMsg)")
      }

      self.refreshNotificationStatus(emitAfter: false) {
        let snapshot = self.buildStatusMap()
        self.emitStatusSnapshot(snapshot)
        DispatchQueue.main.async {
          result(snapshot)
        }
      }
    }
  }

  private func handleStopGateway(result: @escaping FlutterResult) {
    workerQueue.async { [weak self] in
      guard let self = self else { return }

      FalconStop()

      self.stateLock.lock()
      self.isRunning = false
      self.startedAtMs = 0
      self.stateLock.unlock()

      self.appendLog("[ios] gateway stopped")

      DispatchQueue.main.async {
        self.stopSilentAudioPlayer()
        self.endBackgroundKeepAliveTask()
        UIApplication.shared.isIdleTimerDisabled = false

        let snapshot = self.buildStatusMap()
        self.emitStatusSnapshot(snapshot)
        result(snapshot)
      }
    }
  }

  private func handleRequestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { [weak self] granted, _ in
      guard let self = self else {
        DispatchQueue.main.async { result(granted) }
        return
      }
      self.stateLock.lock()
      self.notificationGranted = granted
      self.stateLock.unlock()

      self.emitStatusSnapshot()
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  private func handleSetKeepScreenAwake(enabled: Bool, result: @escaping FlutterResult) {
    defaults.set(enabled, forKey: PrefKeys.keepScreenAwake)
    DispatchQueue.main.async { [weak self] in
      UIApplication.shared.isIdleTimerDisabled = enabled
      self?.appendLog("[ios] keepScreenAwake = \(enabled)")
      self?.emitStatusSnapshot()
      result(enabled)
    }
  }

  private func handleSetBackgroundAudioKeepAlive(enabled: Bool, result: @escaping FlutterResult) {
    defaults.set(enabled, forKey: PrefKeys.backgroundAudioKeepAlive)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(enabled)
        return
      }
      if enabled {
        if self.currentlyRunning() {
          self.startSilentAudioPlayer()
        }
      } else {
        self.stopSilentAudioPlayer()
      }
      self.appendLog("[ios] backgroundAudioKeepAlive = \(enabled)")
      self.emitStatusSnapshot()
      result(enabled)
    }
  }

  // MARK: - Background Audio & Task Protection

  private func startSilentAudioPlayer() {
    if let existing = audioPlayer, existing.isPlaying {
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)

      let wavData = Self.buildSilentWavData()
      let player = try AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue)
      player.numberOfLoops = -1
      player.volume = 0.0
      player.prepareToPlay()
      if player.play() {
        audioPlayer = player
        appendLog("[ios] background audio keep-alive active (.mixWithOthers)")
      } else {
        appendLog("[ios] AVAudioPlayer.play() returned false")
      }
    } catch {
      appendLog("[ios] background audio setup error: \(error.localizedDescription)")
    }
  }

  private func stopSilentAudioPlayer() {
    if let player = audioPlayer {
      player.stop()
      audioPlayer = nil
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func registerObservers() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(onDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(onWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(onAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  @objc private func onDidEnterBackground() {
    guard currentlyRunning() else { return }
    beginBackgroundKeepAliveTask()
  }

  @objc private func onWillEnterForeground() {
    endBackgroundKeepAliveTask()
    if currentlyRunning() && isBackgroundAudioKeepAliveEnabled() {
      startSilentAudioPlayer()
    }
    refreshNotificationStatus(emitAfter: true)
  }

  @objc private func onAudioSessionInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
      return
    }
    if type == .ended && currentlyRunning() && isBackgroundAudioKeepAliveEnabled() {
      DispatchQueue.main.async { [weak self] in
        self?.startSilentAudioPlayer()
      }
    }
  }

  private func beginBackgroundKeepAliveTask() {
    guard backgroundTaskId == .invalid else { return }
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "FalconGatewayKeepAlive") { [weak self] in
      self?.endBackgroundKeepAliveTask()
    }
  }

  private func endBackgroundKeepAliveTask() {
    guard backgroundTaskId != .invalid else { return }
    let taskId = backgroundTaskId
    backgroundTaskId = .invalid
    UIApplication.shared.endBackgroundTask(taskId)
  }

  // MARK: - Network & Status

  private func startPathMonitorIfNeeded() {
    guard pathMonitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] _ in
      guard let self = self else { return }
      let ips = Self.enumerateLanIpv4s()
      self.stateLock.lock()
      let changed = (ips != self.lastLanIpv4s)
      if changed {
        self.lastLanIpv4s = ips
      }
      self.stateLock.unlock()
      if changed {
        self.emitStatusSnapshot()
      }
    }
    monitor.start(queue: workerQueue)
    pathMonitor = monitor
  }

  private func refreshNotificationStatus(emitAfter: Bool, completion: (() -> Void)? = nil) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      let granted: Bool
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        granted = true
      default:
        granted = false
      }
      if let self = self {
        self.stateLock.lock()
        self.notificationGranted = granted
        self.stateLock.unlock()
        if emitAfter {
          self.emitStatusSnapshot()
        }
      }
      if let completion = completion {
        DispatchQueue.main.async {
          completion()
        }
      }
    }
  }

  private func buildStatusMap() -> [String: Any] {
    let coreStatus = readCoreStatusJson()
    let lanIps = Self.enumerateLanIpv4s()
    let keepAwake = isKeepScreenAwakeEnabled()
    let audioKeepAlive = isBackgroundAudioKeepAliveEnabled()
    let audioPlaying = audioPlayer?.isPlaying ?? false

    stateLock.lock()
    lastLanIpv4s = lanIps
    let coreRunning = (coreStatus?["running"] as? Bool) ?? false
    let running = isRunning || coreRunning
    let startMs = startedAtMs
    let notifGranted = notificationGranted
    let logsSnapshot = logs
    let hasBgTask = (backgroundTaskId != .invalid)
    stateLock.unlock()

    let uptimeMs: Int64
    if running && startMs > 0 {
      uptimeMs = max(0, Self.nowMs() - startMs)
    } else if running, let coreUptime = coreStatus?["uptimeMs"] as? NSNumber {
      uptimeMs = max(0, coreUptime.int64Value)
    } else {
      uptimeMs = 0
    }

    let pluginMode = (coreStatus?["pluginRuntimeMode"] as? String) ?? "embedded"

    return [
      "running": running,
      "adminBaseUrl": Self.adminBaseUrl,
      "adminToken": getOrCreateAdminToken(),
      "lanIpv4s": lanIps,
      "platform": "ios",
      "keepScreenAwake": keepAwake,
      "backgroundAudioKeepAlive": audioKeepAlive,
      "pluginRuntimeMode": pluginMode,
      "notificationPermissionGranted": notifGranted,
      "batteryOptimizationIgnored": true,
      "wakeLockHeld": running && (audioPlaying || keepAwake || hasBgTask),
      "wifiLockHeld": running,
      "startOnBoot": false,
      "uptimeMs": uptimeMs,
      "corePid": 0,
      "lastLogs": logsSnapshot,
    ]
  }

  private func emitStatusSnapshot(_ explicitSnapshot: [String: Any]? = nil) {
    stateLock.lock()
    let sink = eventSink
    stateLock.unlock()
    guard let sink = sink else { return }
    let payload = explicitSnapshot ?? buildStatusMap()
    DispatchQueue.main.async {
      sink(payload)
    }
  }

  // MARK: - Helpers

  private func currentlyRunning() -> Bool {
    stateLock.lock()
    let running = isRunning
    stateLock.unlock()
    return running
  }

  private func configuredGatewayPort() -> Int {
    let saved = defaults.integer(forKey: PrefKeys.gatewayPort)
    return (saved > 0 && saved <= 65535) ? saved : Self.defaultGatewayPort
  }

  private func isKeepScreenAwakeEnabled() -> Bool {
    defaults.bool(forKey: PrefKeys.keepScreenAwake)
  }

  private func isBackgroundAudioKeepAliveEnabled() -> Bool {
    defaults.bool(forKey: PrefKeys.backgroundAudioKeepAlive)
  }

  private func getOrCreateAdminToken() -> String {
    if let existing = defaults.string(forKey: PrefKeys.adminToken), existing.count >= 16 {
      return existing
    }
    var bytes = [UInt8](repeating: 0, count: 16)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let token: String
    if status == errSecSuccess {
      token = bytes.map { String(format: "%02x", $0) }.joined()
    } else {
      token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    defaults.set(token, forKey: PrefKeys.adminToken)
    return token
  }

  private func ensureDirectory(in searchPath: FileManager.SearchPathDirectory, subpath: String) -> String {
    let fm = FileManager.default
    let baseUrl = fm.urls(for: searchPath, in: .userDomainMask).first
      ?? fm.temporaryDirectory
    let targetUrl = baseUrl.appendingPathComponent(subpath, isDirectory: true)
    try? fm.createDirectory(at: targetUrl, withIntermediateDirectories: true, attributes: nil)
    return targetUrl.path
  }

  private func appendLog(_ line: String) {
    stateLock.lock()
    if logs.count >= Self.maxLogLines {
      logs.removeFirst(logs.count - Self.maxLogLines + 1)
    }
    logs.append(line)
    stateLock.unlock()
  }

  private func readCoreStatusJson() -> [String: Any]? {
    guard let ptr = FalconStatus() else { return nil }
    defer { FalconFreeString(ptr) }
    let json = String(cString: ptr)
    guard let data = json.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return parsed
  }

  private func isLocalTcpPortOpen(host: String = "127.0.0.1", port: UInt16) -> Bool {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var tv = timeval(tv_sec: 0, tv_usec: 150_000)
    _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    guard host.withCString({ Darwin.inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
      return false
    }

    let rc = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return rc == 0
  }

  private static func nowMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private static func enumerateLanIpv4s() -> [String] {
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
      return []
    }
    defer { freeifaddrs(ifaddrPtr) }

    var wifiOrEthernet: [String] = []
    var bridgeOrHotspot: [String] = []
    var vpnTunnels: [String] = []
    var otherIps: [String] = []
    var seen = Set<String>()

    var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let ifa = cursor {
      defer { cursor = ifa.pointee.ifa_next }

      let flags = Int32(ifa.pointee.ifa_flags)
      guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else {
        continue
      }
      guard let addrPtr = ifa.pointee.ifa_addr,
            addrPtr.pointee.sa_family == UInt8(AF_INET) else {
        continue
      }

      let ifName = String(cString: ifa.pointee.ifa_name).lowercased()
      if ifName.hasPrefix("pdp_ip") || ifName.hasPrefix("lo") {
        continue
      }

      var sin = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
        continue
      }
      let ip = String(cString: buffer)
      guard !ip.isEmpty,
            !ip.hasPrefix("127."),
            !ip.hasPrefix("169.254."),
            seen.insert(ip).inserted else {
        continue
      }

      if ifName.hasPrefix("en") {
        wifiOrEthernet.append(ip)
      } else if ifName.hasPrefix("bridge") {
        bridgeOrHotspot.append(ip)
      } else if ifName.hasPrefix("utun") {
        vpnTunnels.append(ip)
      } else {
        otherIps.append(ip)
      }
    }

    return wifiOrEthernet + bridgeOrHotspot + vpnTunnels + otherIps
  }

  private static func buildSilentWavData(sampleRate: UInt32 = 8000, durationSeconds: UInt32 = 1) -> Data {
    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
    let dataSize: UInt32 = byteRate * durationSeconds
    let chunkSize: UInt32 = 36 + dataSize

    var data = Data(capacity: Int(44 + dataSize))
    func appendLE<T: FixedWidthInteger>(_ value: T) {
      var le = value.littleEndian
      withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    data.append(contentsOf: "RIFF".utf8)
    appendLE(chunkSize)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    appendLE(UInt32(16))
    appendLE(UInt16(1))
    appendLE(numChannels)
    appendLE(sampleRate)
    appendLE(byteRate)
    appendLE(blockAlign)
    appendLE(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    appendLE(dataSize)
    data.append(Data(count: Int(dataSize)))
    return data
  }
}
