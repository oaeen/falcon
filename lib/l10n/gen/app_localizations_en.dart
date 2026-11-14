// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Falcon';

  @override
  String get tabGateway => 'Gateway';

  @override
  String get tabProviders => 'Providers';

  @override
  String get tabRouting => 'Routing';

  @override
  String get tabMonitor => 'Monitor';

  @override
  String get actionTestConsole => 'Test';

  @override
  String get actionSettings => 'Settings';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClose => 'Close';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionCopied => 'Copied';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionTest => 'Test';

  @override
  String get actionExport => 'Export';

  @override
  String get actionImport => 'Import';

  @override
  String get statusRunning => 'Running';

  @override
  String get statusStopped => 'Stopped';

  @override
  String get statusStarting => 'Starting';

  @override
  String get statusEnabled => 'Enabled';

  @override
  String get statusDisabled => 'Disabled';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusDisconnected => 'Disconnected';

  @override
  String get statusUnknown => 'Unknown';

  @override
  String get gatewayTitle => 'Gateway';

  @override
  String get gatewayHeroSubtitleRunning =>
      'Local routing & subscription proxy active';

  @override
  String get gatewayHeroSubtitleStopped =>
      'Start gateway to accept local API requests';

  @override
  String get gatewayActionStart => 'Start Gateway';

  @override
  String get gatewayActionStop => 'Stop Gateway';

  @override
  String get gatewayServiceSection => 'Service Status';

  @override
  String get gatewayServiceToggle => 'Gateway Service';

  @override
  String get gatewayUptime => 'Uptime';

  @override
  String get gatewayCorePid => 'Core PID';

  @override
  String get gatewayModelsCount => 'Models';

  @override
  String get gatewayProvidersCount => 'Active Providers';

  @override
  String get gatewayBadgeForeground => 'Foreground';

  @override
  String get gatewayBadgeWakeLock => 'WakeLock';

  @override
  String get gatewayBadgeWifiLock => 'Wi-Fi Lock';

  @override
  String get gatewayBadgeAudioKeepAlive => 'Audio Keep-Alive';

  @override
  String get gatewayBadgeScreenAwake => 'Screen Awake';

  @override
  String get gatewayBadgeDesktopProcess => 'Local Process';

  @override
  String get gatewayBatteryBannerTitle => 'Battery Optimization Active';

  @override
  String get gatewayBatteryBannerBody =>
      'Android may throttle local and LAN proxy sockets during sleep. Grant battery exemption to stay reachable.';

  @override
  String get gatewayBatteryGrant => 'Grant';

  @override
  String get gatewayNotifBannerTitle => 'Notifications Disabled';

  @override
  String get gatewayNotifBannerBody =>
      'Foreground service requires notification permission to keep running reliably in the background.';

  @override
  String get gatewayNotifGrant => 'Allow';

  @override
  String get gatewayEndpointsSection => 'Access Endpoints';

  @override
  String get gatewayLoopbackLabel => 'Loopback';

  @override
  String get gatewayLanUrlLabel => 'LAN Endpoint';

  @override
  String get gatewayLocalKeyless => 'Local Keyless Access';

  @override
  String get gatewayLocalKeylessHint =>
      'Requests from 127.0.0.1 bypass access key checks';

  @override
  String get gatewayLanAccess => 'LAN Access';

  @override
  String get gatewayLanAccessHint =>
      'Expose gateway port to devices on the same LAN';

  @override
  String get gatewaySecuritySection => 'Access Control';

  @override
  String get gatewayRequireAccessKey => 'Access Key Protection';

  @override
  String get gatewayRequireAccessKeyHint =>
      'Off for local or trusted LAN use; enable to require sk-flc- keys';

  @override
  String get gatewayLanRequireKey => 'Require access key on LAN';

  @override
  String get gatewayLanRequireKeyHint =>
      'Enforce sk-flc- key validation for remote LAN clients';

  @override
  String get gatewayLanNoIp => 'No active LAN IPv4 address detected';

  @override
  String get gatewayClientExamples => 'Client Setup Examples';

  @override
  String get gatewayClientExamplesTitle => 'Client Setup Examples';

  @override
  String get gatewayClientOpenAi => 'OpenAI Compatible';

  @override
  String get gatewayClientAnthropic => 'Anthropic Compatible';

  @override
  String get gatewayClientGemini => 'Gemini Compatible';

  @override
  String get gatewayClientCurl => 'cURL Verification';

  @override
  String get gatewayClientAuthNote =>
      'When access key protection is enabled, send a key via Authorization: Bearer or x-api-key.';

  @override
  String get gatewayClientKeylessNote =>
      'Access key protection is off. Clients can call the endpoints above directly.';

  @override
  String get gatewayKeysSection => 'Gateway Access Keys';

  @override
  String get gatewayKeysEmpty => 'No access keys configured';

  @override
  String get gatewayKeysEmptyHint =>
      'Create an sk-flc- key for LAN access or per-client quota limits.';

  @override
  String get gatewayKeyCreateTitle => 'New Access Key';

  @override
  String get gatewayKeyCreatedNotice =>
      'Copy and store this key now. The full secret will not be displayed again.';

  @override
  String get gatewayKeyNameLabel => 'Key Name';

  @override
  String get gatewayKeyNameHint => 'e.g. MacBook Dev';

  @override
  String get gatewayKeyModelsLabel => 'Allowed Models (empty for all)';

  @override
  String get gatewayKeyModelsHint =>
      'Comma-separated, e.g. gpt-4o, deepseek-chat';

  @override
  String get gatewayKeyDailyUsdLabel => 'Daily Budget Cap (USD, 0 = unlimited)';

  @override
  String get gatewayKeyMonthlyUsdLabel =>
      'Monthly Budget Cap (USD, 0 = unlimited)';

  @override
  String get gatewayKeyDailyReqsLabel => 'Daily Request Cap (0 = unlimited)';

  @override
  String get gatewayKeyRotate => 'Rotate Key';

  @override
  String get gatewayKeyRotateConfirm =>
      'Rotating invalidates the previous secret immediately. Continue?';

  @override
  String gatewayKeyDeleteConfirm(String name) {
    return 'Delete access key \"$name\"?';
  }

  @override
  String gatewayKeyUsageSummary(int reqs, String usd) {
    return '$reqs reqs today · $usd USD';
  }

  @override
  String get providersTitle => 'Providers';

  @override
  String get providersSegmentApi => 'API Providers';

  @override
  String get providersSegmentPlugins => 'Subscription Plugins';

  @override
  String get providersApiEmpty => 'No API providers configured';

  @override
  String get providersApiEmptyHint =>
      'Add OpenAI, Anthropic, DeepSeek, or a custom compatible endpoint.';

  @override
  String get providersAddFromPreset => 'Add Preset';

  @override
  String get providersAddCustom => 'Custom Provider';

  @override
  String get providersPresetTitle => 'Select Provider Preset';

  @override
  String get providersEditorAddTitle => 'Add API Provider';

  @override
  String get providersEditorEditTitle => 'Edit API Provider';

  @override
  String get providersNameLabel => 'Provider Name';

  @override
  String get providersProtocolLabel => 'Upstream Protocol';

  @override
  String get providersBaseUrlLabel => 'Base URL';

  @override
  String get providersKeysLabel => 'Upstream Key Pool';

  @override
  String get providersAddKey => 'Add Key';

  @override
  String get providersKeyLabelHint => 'Label (optional)';

  @override
  String get providersKeySecretHint =>
      'Enter secret (leave blank to keep existing)';

  @override
  String get providersKeyWeightLabel => 'Weight';

  @override
  String get providersFetchModels => 'Fetch Models';

  @override
  String get providersFetchingModels => 'Fetching models...';

  @override
  String providersModelsFetched(int count) {
    return 'Fetched $count models';
  }

  @override
  String providersSelectedModels(int count) {
    return 'Enabled Models ($count)';
  }

  @override
  String get providersManualModelHint =>
      'Add model IDs manually (comma-separated)';

  @override
  String get providersTestConnectivity => 'Connectivity Test';

  @override
  String get providersTesting => 'Testing...';

  @override
  String providersTestPass(int ms) {
    return 'OK · $ms ms';
  }

  @override
  String providersTestFail(int code) {
    return 'Failed · HTTP $code';
  }

  @override
  String providersDeleteConfirm(String name) {
    return 'Delete provider \"$name\"?';
  }

  @override
  String get pluginsDirectoryAction => 'Plugin Directory';

  @override
  String get pluginsRefreshQuotas => 'Refresh Quotas';

  @override
  String get pluginsEmpty => 'No subscription plugins installed';

  @override
  String get pluginsEmptyHint =>
      'Open the Plugin Directory to install authentication plugins and sync quotas.';

  @override
  String get pluginsSignIn => 'Sign In';

  @override
  String get pluginsSignOut => 'Sign Out';

  @override
  String pluginsSignOutConfirm(String label) {
    return 'Sign out account \"$label\"?';
  }

  @override
  String get pluginsCheckin => 'Check In';

  @override
  String pluginsCheckinResult(String outcome) {
    return 'Check-in: $outcome';
  }

  @override
  String pluginsAccountsCount(int count) {
    return '$count accounts';
  }

  @override
  String get pluginsMarketTitle => 'Plugin Directory';

  @override
  String get pluginsMarketSearchHint =>
      'Search plugin name, package, or provider';

  @override
  String get pluginsMarketChinaMirror => 'CN Mirror';

  @override
  String get pluginsMarketCategoryAll => 'All';

  @override
  String get pluginsMarketCategoryAuth => 'Auth';

  @override
  String get pluginsMarketCategoryMiddleware => 'Middleware';

  @override
  String get pluginsMarketInstall => 'Install';

  @override
  String get pluginsMarketRemove => 'Remove';

  @override
  String get pluginsMarketInstalled => 'Installed';

  @override
  String get pluginsMarketCustomSpecHint => 'Enter npm package or Git spec';

  @override
  String get pluginsSignInTitle => 'Plugin Sign-In';

  @override
  String get pluginsSignInPreparing => 'Preparing sign-in session...';

  @override
  String get pluginsSignInOpenBrowser => 'Complete sign-in in browser';

  @override
  String get pluginsSignInOpenBrowserHint =>
      'Open or copy the verification URL if the browser did not launch.';

  @override
  String get pluginsSignInReopenBrowser => 'Open Browser';

  @override
  String get pluginsSignInCopyUrl => 'Copy URL';

  @override
  String get pluginsSignInDeviceCode => 'Device Code';

  @override
  String get pluginsSignInDeviceCodeHint =>
      'Open the verification page and enter the code above.';

  @override
  String get pluginsSignInPasteCallback => 'Paste Callback URL or Code';

  @override
  String get pluginsSignInPasteHint =>
      'Paste the redirected callback URL or credential here';

  @override
  String get pluginsSignInSubmit => 'Submit';

  @override
  String get pluginsSignInSuccess => 'Signed in';

  @override
  String get pluginsSignInFailed => 'Sign-in incomplete';

  @override
  String get pluginsSelectModels => 'Models';

  @override
  String get pluginsModelsRowLabel => 'Models';

  @override
  String get pluginsActionSignInShort => 'Sign In';

  @override
  String get pluginsAuthMethodBrowser => 'Browser OAuth';

  @override
  String get pluginsAuthMethodApiKey => 'API Key';

  @override
  String pluginsSelectedModelsSummary(int count, int total) {
    return '$count / $total selected';
  }

  @override
  String pluginsAutoAllModels(int total) {
    return 'All $total active (Auto)';
  }

  @override
  String get pluginsTestInPlayground => 'Test';

  @override
  String get pluginsRefreshPlugin => 'Refresh';

  @override
  String get pluginsAddAccount => 'Add Account';

  @override
  String get pluginsAuthenticated => 'Signed in';

  @override
  String get pluginsNotAuthenticated => 'Sign in required';

  @override
  String get pluginsModelsTitle => 'Select Models';

  @override
  String get pluginsModelsSearchHint => 'Search model ID or name';

  @override
  String get pluginsModelsFilterAll => 'All';

  @override
  String get pluginsModelsFilterSelected => 'Selected';

  @override
  String get pluginsModelsFilterFree => 'Free';

  @override
  String get pluginsModelsSelectAll => 'All Models';

  @override
  String get pluginsModelsClearAuto => 'Clear (Auto)';

  @override
  String get pluginsModelsAutoBanner =>
      'When none are selected, all models from this provider remain enabled.';

  @override
  String get pluginsModelsCapReasoning => 'Reasoning';

  @override
  String get pluginsModelsCapTools => 'Tool Call';

  @override
  String get pluginsModelsCapFree => 'Free';

  @override
  String get pluginsModelsEmpty =>
      'No models loaded yet. Sign in or tap Refresh.';

  @override
  String get pluginsEditionLabel => 'Service Edition';

  @override
  String get pluginsEditionWorkbuddyCn =>
      'WorkBuddy China (copilot.tencent.com)';

  @override
  String get pluginsEditionWorkbuddyIntl =>
      'WorkBuddy Global (www.workbuddy.ai)';

  @override
  String get pluginsAuthMethodLabel => 'Sign-In Method';

  @override
  String get pluginsAuthOpenAutoHint =>
      'Authorization page opened. Complete sign-in in browser to sync automatically.';

  @override
  String get routingTitle => 'Routing';

  @override
  String get routingSegmentGroups => 'Groups';

  @override
  String get routingSegmentAliases => 'Aliases';

  @override
  String get routingGroupsEmpty => 'No routing groups configured';

  @override
  String get routingGroupsEmptyHint =>
      'Combine upstream models with ordered failover, round-robin, or lowest-TTFT routing.';

  @override
  String get routingGroupAdd => 'New Group';

  @override
  String get routingGroupEdit => 'Edit Group';

  @override
  String get routingGroupNameLabel => 'Group Name (exposed model ID)';

  @override
  String get routingGroupStrategyLabel => 'Routing Strategy';

  @override
  String get routingStrategyOrder => 'Ordered Failover (order)';

  @override
  String get routingStrategyRoundRobin => 'Round Robin (round_robin)';

  @override
  String get routingStrategyFastest => 'Lowest TTFT (fastest)';

  @override
  String get routingStrategyManual => 'Manual Pin (manual)';

  @override
  String get routingGroupPinnedLabel => 'Pinned Member';

  @override
  String get routingGroupMembersLabel => 'Members (provider/model)';

  @override
  String get routingGroupMembersHint =>
      'One per line or comma-separated, e.g. deepseek/deepseek-chat';

  @override
  String routingGroupDeleteConfirm(String name) {
    return 'Delete routing group \"$name\"?';
  }

  @override
  String routingMembersSummary(int count, String strategy) {
    return '$count targets · $strategy';
  }

  @override
  String get routingAliasesEmpty => 'No model aliases configured';

  @override
  String get routingAliasesEmptyHint =>
      'Rewrite incoming model IDs to specific upstream targets or groups.';

  @override
  String get routingAliasAdd => 'New Alias';

  @override
  String get routingAliasEdit => 'Edit Alias';

  @override
  String get routingAliasSourceLabel => 'Requested Model';

  @override
  String get routingAliasSourceHint => 'e.g. gpt-4o';

  @override
  String get routingAliasTargetLabel => 'Target Model or Group';

  @override
  String get routingAliasTargetHint => 'e.g. deepseek/deepseek-chat';

  @override
  String get monitorTitle => 'Monitor';

  @override
  String get monitorRangeToday => 'Today';

  @override
  String get monitorRange7d => '7 Days';

  @override
  String get monitorRange30d => '30 Days';

  @override
  String get monitorKpiRequests => 'Requests';

  @override
  String get monitorKpiTokens => 'Tokens';

  @override
  String get monitorKpiSpend => 'Est. Spend';

  @override
  String get monitorKpiTtft => 'Avg TTFT';

  @override
  String get monitorOpenPlayground => 'Playground';

  @override
  String get monitorLogsSection => 'Request Logs';

  @override
  String get monitorLogsEmpty => 'No requests recorded yet';

  @override
  String get monitorLogsClearConfirm => 'Clear all recorded request logs?';

  @override
  String get monitorSourceLocal => 'Local 127.0.0.1';

  @override
  String monitorSourceLan(String ip) {
    return 'LAN $ip';
  }

  @override
  String get monitorDetailTitle => 'Request Details';

  @override
  String get monitorDetailClientIp => 'Client IP';

  @override
  String get monitorDetailKey => 'Access Key';

  @override
  String get monitorDetailProtocol => 'Protocol';

  @override
  String get monitorDetailRoute => 'Model Route';

  @override
  String get monitorDetailStatus => 'HTTP Status';

  @override
  String get monitorDetailTiming => 'TTFT / Duration';

  @override
  String get monitorDetailTokens => 'Input / Output Tokens';

  @override
  String get monitorDetailFailovers => 'Failover Attempts';

  @override
  String get monitorDetailError => 'Error';

  @override
  String get playgroundTitle => 'Playground';

  @override
  String get playgroundModelLabel => 'Model or Group';

  @override
  String get playgroundKeyLabel => 'Access Key';

  @override
  String get playgroundKeyNone => 'Local Keyless';

  @override
  String get playgroundKeyNotRequired => 'Key protection off (open access)';

  @override
  String get playgroundKeyCustom => 'Enter Full Key';

  @override
  String get playgroundKeyCustomHint => 'Paste full sk-flc- access key';

  @override
  String get playgroundPromptLabel => 'Prompt';

  @override
  String get playgroundPromptDefault =>
      'Reply with one concise sentence confirming Falcon gateway connectivity.';

  @override
  String get playgroundSend => 'Send Request';

  @override
  String get playgroundSending => 'Streaming...';

  @override
  String get playgroundStop => 'Stop';

  @override
  String get playgroundOutputLabel => 'Streaming Response';

  @override
  String playgroundStreamRate(String rate, String sec) {
    return '$rate tok/s · $sec s';
  }

  @override
  String playgroundMetrics(int ttft, int total, int tokens) {
    return 'TTFT $ttft ms · Total $total ms · $tokens tokens';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsKeepAliveSection => 'Background Keep-Alive';

  @override
  String get settingsBatteryExemption => 'Battery Optimization Exemption';

  @override
  String get settingsBatteryGranted => 'Exempted';

  @override
  String get settingsBatteryNotGranted => 'Restricted';

  @override
  String get settingsAppBatterySettings => 'App Info & Battery Settings';

  @override
  String get settingsNotificationPermission => 'Notification Permission';

  @override
  String get settingsBootAutoStart => 'Start on Boot';

  @override
  String get settingsWakeLock => 'CPU WakeLock';

  @override
  String get settingsWifiLock => 'Wi-Fi Performance Lock';

  @override
  String get settingsIosBackgroundAudio => 'Background Keep-Alive (Audio Mix)';

  @override
  String get settingsIosBackgroundAudioHint =>
      'Uses AVAudioSession .mixWithOthers to keep loopback and LAN sockets alive in background for sideloaded builds';

  @override
  String get settingsIosKeepScreenAwake => 'Keep Screen Awake';

  @override
  String get settingsIosKeepScreenAwakeHint =>
      'Prevents device auto-lock while Falcon remains in the foreground';

  @override
  String get settingsIosLocalNetworkTitle => 'Local Network & Notifications';

  @override
  String get settingsIosLocalNetworkGuidance =>
      'iOS Guidance: Allow Local Network access when prompted to serve LAN clients. Keep background keep-alive enabled or connect power for extended sessions.';

  @override
  String get settingsDesktopProcessGuidance =>
      'Desktop builds run falcon-core as a local process. Configure listening port and LAN binding under Network & Security.';

  @override
  String get settingsPluginRuntimeMode => 'Plugin Runtime';

  @override
  String get settingsOemGuidance =>
      'OEM Background Guidance: On MIUI, ColorOS, OriginOS, or HarmonyOS, enable Auto-Start, Unrestricted Battery, and lock Falcon in Recents to prevent socket suspension.';

  @override
  String get settingsNetworkSection => 'Network & Security';

  @override
  String get settingsPort => 'Gateway Port';

  @override
  String get settingsPortHint => '1024 - 65535, default 18787';

  @override
  String get settingsAllowIps => 'IP / CIDR Allowlist';

  @override
  String get settingsAllowIpsHint => 'Comma-separated, empty allows all';

  @override
  String get settingsCorsOrigins => 'CORS Origins';

  @override
  String get settingsCorsOriginsHint =>
      'Comma-separated, e.g. * or https://app.example.com';

  @override
  String get settingsChinaMirror => 'Use China Mirror for Plugins';

  @override
  String get settingsBackupSection => 'Backup & Restore';

  @override
  String get settingsBackupExport => 'Export Config JSON';

  @override
  String get settingsBackupExportIncludeSecrets =>
      'Include plaintext secrets in export';

  @override
  String get settingsBackupImport => 'Import Config JSON';

  @override
  String get settingsBackupSheetTitle => 'Configuration Backup';

  @override
  String get settingsBackupPasteHint =>
      'Paste exported JSON configuration here to restore';

  @override
  String get settingsBackupImportSuccess => 'Configuration imported';

  @override
  String get settingsAppearanceSection => 'Appearance & Language';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get errorGatewayNotRunning =>
      'Gateway is stopped. Start the service on the Gateway tab first.';

  @override
  String errorRequestFailed(String message) {
    return 'Request failed: $message';
  }
}
