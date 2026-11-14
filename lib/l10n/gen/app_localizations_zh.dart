// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Falcon';

  @override
  String get tabGateway => '网关';

  @override
  String get tabProviders => '渠道';

  @override
  String get tabRouting => '路由';

  @override
  String get tabMonitor => '观测';

  @override
  String get actionTestConsole => '测试';

  @override
  String get actionSettings => '设置';

  @override
  String get actionRefresh => '刷新';

  @override
  String get actionAdd => '添加';

  @override
  String get actionEdit => '编辑';

  @override
  String get actionDelete => '删除';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionClose => '关闭';

  @override
  String get actionCopy => '复制';

  @override
  String get actionCopied => '已复制';

  @override
  String get actionCreate => '创建';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionRetry => '重试';

  @override
  String get actionClear => '清空';

  @override
  String get actionTest => '测试';

  @override
  String get actionExport => '导出';

  @override
  String get actionImport => '导入';

  @override
  String get statusRunning => '运行中';

  @override
  String get statusStopped => '已停止';

  @override
  String get statusStarting => '正在启动';

  @override
  String get statusEnabled => '已启用';

  @override
  String get statusDisabled => '已停用';

  @override
  String get statusConnected => '已连接';

  @override
  String get statusDisconnected => '未连接';

  @override
  String get statusUnknown => '未知';

  @override
  String get gatewayTitle => '网关';

  @override
  String get gatewayHeroSubtitleRunning => '本地模型路由与订阅代理已就绪';

  @override
  String get gatewayHeroSubtitleStopped => '点击启动以监听本地与订阅请求';

  @override
  String get gatewayActionStart => '启动网关';

  @override
  String get gatewayActionStop => '停止网关';

  @override
  String get gatewayServiceSection => '服务状态';

  @override
  String get gatewayServiceToggle => '网关服务';

  @override
  String get gatewayUptime => '运行时长';

  @override
  String get gatewayCorePid => '进程 PID';

  @override
  String get gatewayModelsCount => '可用模型';

  @override
  String get gatewayProvidersCount => '活跃渠道';

  @override
  String get gatewayBadgeForeground => '前台常驻';

  @override
  String get gatewayBadgeWakeLock => '唤醒锁';

  @override
  String get gatewayBadgeWifiLock => 'WLAN 锁';

  @override
  String get gatewayBadgeAudioKeepAlive => '后台混音保活';

  @override
  String get gatewayBadgeScreenAwake => '屏幕常亮';

  @override
  String get gatewayBadgeDesktopProcess => '本地进程';

  @override
  String get gatewayBatteryBannerTitle => '未忽略电池优化';

  @override
  String get gatewayBatteryBannerBody => '系统休眠后可能中断本地与局域网代理，建议授予忽略电池优化权限。';

  @override
  String get gatewayBatteryGrant => '立即授权';

  @override
  String get gatewayNotifBannerTitle => '未开启通知权限';

  @override
  String get gatewayNotifBannerBody => 'Android 前台服务需要通知权限以维持后台保活状态。';

  @override
  String get gatewayNotifGrant => '开启通知';

  @override
  String get gatewayEndpointsSection => '访问端点';

  @override
  String get gatewayLoopbackLabel => '本机端点';

  @override
  String get gatewayLocalKeyless => '本机免密访问';

  @override
  String get gatewayLocalKeylessHint => '仅 127.0.0.1 本机请求可免密钥访问';

  @override
  String get gatewayLanAccess => '局域网访问';

  @override
  String get gatewayLanAccessHint => '开放同局域网设备访问当前端口';

  @override
  String get gatewaySecuritySection => '访问鉴权';

  @override
  String get gatewayRequireAccessKey => '访问密钥保护';

  @override
  String get gatewayRequireAccessKeyHint => '本机或受信任局域网默认关闭；开启后将校验 sk-flc- 密钥';

  @override
  String get gatewayLanRequireKey => '局域网请求校验密钥';

  @override
  String get gatewayLanRequireKeyHint => '对来自局域网 IP 的客户端强制要求 sk-flc- 访问密钥';

  @override
  String get gatewayLanNoIp => '当前未检测到局域网 IPv4 地址';

  @override
  String get gatewayClientExamples => '客户端接入示例';

  @override
  String get gatewayClientExamplesTitle => '客户端接入示例';

  @override
  String get gatewayClientOpenAi => 'OpenAI 兼容接口';

  @override
  String get gatewayClientAnthropic => 'Anthropic 兼容接口';

  @override
  String get gatewayClientGemini => 'Gemini 兼容接口';

  @override
  String get gatewayClientCurl => 'cURL 验证示例';

  @override
  String get gatewayClientAuthNote =>
      '已开启访问密钥保护时，请在 Authorization 请求头或 x-api-key 中传入密钥。';

  @override
  String get gatewayClientKeylessNote => '当前未开启访问密钥保护，客户端可直接访问上述地址。';

  @override
  String get gatewayKeysSection => '访问密钥';

  @override
  String get gatewayKeysEmpty => '尚未创建访问密钥';

  @override
  String get gatewayKeysEmptyHint => '局域网接入或配额管控需创建 sk-flc- 前缀密钥。';

  @override
  String get gatewayKeyCreateTitle => '新建访问密钥';

  @override
  String get gatewayKeyCreatedNotice => '请立即复制并妥善保存完整密钥，关闭后将不再完整显示。';

  @override
  String get gatewayKeyNameLabel => '密钥名称';

  @override
  String get gatewayKeyNameHint => '例如：MacBook 开发机';

  @override
  String get gatewayKeyModelsLabel => '允许访问的模型（留空表示全部）';

  @override
  String get gatewayKeyModelsHint => '逗号分隔，如 gpt-4o, deepseek-chat';

  @override
  String get gatewayKeyDailyUsdLabel => '每日预算上限（USD，0 为不限）';

  @override
  String get gatewayKeyMonthlyUsdLabel => '每月预算上限（USD，0 为不限）';

  @override
  String get gatewayKeyDailyReqsLabel => '每日请求上限（0 为不限）';

  @override
  String get gatewayKeyRotate => '轮换密钥';

  @override
  String get gatewayKeyRotateConfirm => '轮换后旧密钥将立即失效，确认继续吗？';

  @override
  String gatewayKeyDeleteConfirm(String name) {
    return '确认删除访问密钥“$name”吗？';
  }

  @override
  String gatewayKeyUsageSummary(int reqs, String usd) {
    return '今日 $reqs 次 · $usd USD';
  }

  @override
  String get providersTitle => '渠道';

  @override
  String get providersSegmentApi => '接口渠道';

  @override
  String get providersSegmentPlugins => '订阅插件';

  @override
  String get providersApiEmpty => '尚未配置接口渠道';

  @override
  String get providersApiEmptyHint => '添加 OpenAI、Anthropic、DeepSeek 或自定义兼容上游。';

  @override
  String get providersAddFromPreset => '从预设添加';

  @override
  String get providersAddCustom => '自定义渠道';

  @override
  String get providersPresetTitle => '选择渠道预设';

  @override
  String get providersEditorAddTitle => '添加接口渠道';

  @override
  String get providersEditorEditTitle => '编辑接口渠道';

  @override
  String get providersNameLabel => '渠道名称';

  @override
  String get providersProtocolLabel => '上游协议';

  @override
  String get providersBaseUrlLabel => 'Base URL';

  @override
  String get providersKeysLabel => '上游密钥池';

  @override
  String get providersAddKey => '添加密钥';

  @override
  String get providersKeyLabelHint => '备注（可选）';

  @override
  String get providersKeySecretHint => '输入新密钥（留空保持不变）';

  @override
  String get providersKeyWeightLabel => '权重';

  @override
  String get providersFetchModels => '拉取模型';

  @override
  String get providersFetchingModels => '正在拉取模型...';

  @override
  String providersModelsFetched(int count) {
    return '已获取 $count 个模型';
  }

  @override
  String providersSelectedModels(int count) {
    return '启用模型（$count）';
  }

  @override
  String get providersManualModelHint => '手动添加模型 ID（逗号分隔）';

  @override
  String get providersTestConnectivity => '连通性测试';

  @override
  String get providersTesting => '测试中...';

  @override
  String providersTestPass(int ms) {
    return '正常 · $ms ms';
  }

  @override
  String providersTestFail(int code) {
    return '失败 · HTTP $code';
  }

  @override
  String providersDeleteConfirm(String name) {
    return '确认删除渠道“$name”吗？';
  }

  @override
  String get pluginsDirectoryAction => '插件目录';

  @override
  String get pluginsRefreshQuotas => '刷新额度';

  @override
  String get pluginsEmpty => '尚未安装订阅插件';

  @override
  String get pluginsEmptyHint => '打开插件目录安装社区认证插件并同步额度。';

  @override
  String get pluginsSignIn => '登录账号';

  @override
  String get pluginsSignOut => '退出登录';

  @override
  String pluginsSignOutConfirm(String label) {
    return '确认退出账号“$label”吗？';
  }

  @override
  String get pluginsCheckin => '签到';

  @override
  String pluginsCheckinResult(String outcome) {
    return '签到结果：$outcome';
  }

  @override
  String pluginsAccountsCount(int count) {
    return '$count 个账号';
  }

  @override
  String get pluginsMarketTitle => '插件目录';

  @override
  String get pluginsMarketSearchHint => '搜索插件名称、包名或模型服务';

  @override
  String get pluginsMarketChinaMirror => '国内镜像加速';

  @override
  String get pluginsMarketCategoryAll => '全部';

  @override
  String get pluginsMarketCategoryAuth => '订阅认证';

  @override
  String get pluginsMarketCategoryMiddleware => '请求中间件';

  @override
  String get pluginsMarketInstall => '安装';

  @override
  String get pluginsMarketRemove => '卸载';

  @override
  String get pluginsMarketInstalled => '已安装';

  @override
  String get pluginsMarketCustomSpecHint => '输入 npm 包名或 Git 规格安装';

  @override
  String get pluginsSignInTitle => '插件账号认证';

  @override
  String get pluginsSignInPreparing => '正在初始化认证会话...';

  @override
  String get pluginsSignInOpenBrowser => '在浏览器中完成登录';

  @override
  String get pluginsSignInOpenBrowserHint => '如果浏览器未自动打开，可手动打开或复制链接。';

  @override
  String get pluginsSignInReopenBrowser => '打开认证页面';

  @override
  String get pluginsSignInCopyUrl => '复制链接';

  @override
  String get pluginsSignInDeviceCode => '设备授权码';

  @override
  String get pluginsSignInDeviceCodeHint => '打开验证页面并输入上方授权码。';

  @override
  String get pluginsSignInPasteCallback => '输入回调 URL 或授权码';

  @override
  String get pluginsSignInPasteHint => '将浏览器跳转后的完整回调地址或凭证粘贴至此处';

  @override
  String get pluginsSignInSubmit => '提交验证';

  @override
  String get pluginsSignInSuccess => '认证已完成';

  @override
  String get pluginsSignInFailed => '认证未完成';

  @override
  String get pluginsSelectModels => '选择模型';

  @override
  String pluginsSelectedModelsSummary(int count, int total) {
    return '已选 $count / $total 个模型';
  }

  @override
  String pluginsAutoAllModels(int total) {
    return '全部 $total 个可用（自动）';
  }

  @override
  String get pluginsTestInPlayground => '在线测试';

  @override
  String get pluginsRefreshPlugin => '刷新状态';

  @override
  String get pluginsAddAccount => '添加账号';

  @override
  String get pluginsAuthenticated => '已认证';

  @override
  String get pluginsNotAuthenticated => '未登录';

  @override
  String get pluginsModelsTitle => '模型选择';

  @override
  String get pluginsModelsSearchHint => '搜索模型 ID 或名称';

  @override
  String get pluginsModelsFilterAll => '全部';

  @override
  String get pluginsModelsFilterSelected => '已选';

  @override
  String get pluginsModelsFilterFree => '免费';

  @override
  String get pluginsModelsSelectAll => '全选';

  @override
  String get pluginsModelsClearAuto => '清空（自动）';

  @override
  String get pluginsModelsAutoBanner => '未勾选特定模型时，网关将自动暴露当前服务商的全部可用模型。';

  @override
  String get pluginsModelsCapReasoning => '推理';

  @override
  String get pluginsModelsCapTools => '工具调用';

  @override
  String get pluginsModelsCapFree => '免费';

  @override
  String get pluginsModelsEmpty => '暂无可选模型，请先登录后刷新或手动刷新目录';

  @override
  String get pluginsEditionLabel => '服务版本 / 区域';

  @override
  String get pluginsEditionWorkbuddyCn => 'WorkBuddy 国内版 (copilot.tencent.com)';

  @override
  String get pluginsEditionWorkbuddyIntl => 'WorkBuddy 国际版 (www.workbuddy.ai)';

  @override
  String get pluginsAuthMethodLabel => '认证方式';

  @override
  String get pluginsAuthOpenAutoHint => '已在浏览器中打开授权页面，完成登录后将自动同步账号与模型。';

  @override
  String get routingTitle => '路由';

  @override
  String get routingSegmentGroups => '路由组';

  @override
  String get routingSegmentAliases => '模型映射';

  @override
  String get routingGroupsEmpty => '尚未配置路由组';

  @override
  String get routingGroupsEmptyHint => '将多个渠道模型组合，实现顺序回退、轮询或最低延迟调度。';

  @override
  String get routingGroupAdd => '新建路由组';

  @override
  String get routingGroupEdit => '编辑路由组';

  @override
  String get routingGroupNameLabel => '路由组名称（对外模型名）';

  @override
  String get routingGroupStrategyLabel => '调度策略';

  @override
  String get routingStrategyOrder => '顺序回退 (order)';

  @override
  String get routingStrategyRoundRobin => '轮询均衡 (round_robin)';

  @override
  String get routingStrategyFastest => '最低 TTFT (fastest)';

  @override
  String get routingStrategyManual => '手动指定 (manual)';

  @override
  String get routingGroupPinnedLabel => '锁定目标成员';

  @override
  String get routingGroupMembersLabel => '成员列表（provider/model）';

  @override
  String get routingGroupMembersHint => '每行一个或逗号分隔，如 deepseek/deepseek-chat';

  @override
  String routingGroupDeleteConfirm(String name) {
    return '确认删除路由组“$name”吗？';
  }

  @override
  String get routingAliasesEmpty => '尚未配置模型映射';

  @override
  String get routingAliasesEmptyHint => '将客户端请求的模型名重写为指定的上游渠道模型或路由组。';

  @override
  String get routingAliasAdd => '新建映射';

  @override
  String get routingAliasEdit => '编辑映射';

  @override
  String get routingAliasSourceLabel => '请求模型名';

  @override
  String get routingAliasSourceHint => '例如：gpt-4o';

  @override
  String get routingAliasTargetLabel => '目标模型或路由组';

  @override
  String get routingAliasTargetHint => '例如：deepseek/deepseek-chat';

  @override
  String get monitorTitle => '观测';

  @override
  String get monitorRangeToday => '今日';

  @override
  String get monitorRange7d => '7 日';

  @override
  String get monitorRange30d => '30 日';

  @override
  String get monitorKpiRequests => '总请求数';

  @override
  String get monitorKpiTokens => '总 Token';

  @override
  String get monitorKpiSpend => '估算费用';

  @override
  String get monitorKpiTtft => '平均 TTFT';

  @override
  String get monitorOpenPlayground => '在线测试';

  @override
  String get monitorLogsSection => '请求日志';

  @override
  String get monitorLogsEmpty => '暂无请求记录';

  @override
  String get monitorLogsClearConfirm => '确认清空所有历史请求日志吗？';

  @override
  String get monitorSourceLocal => '本机 127.0.0.1';

  @override
  String monitorSourceLan(String ip) {
    return '局域网 $ip';
  }

  @override
  String get monitorDetailTitle => '请求详情';

  @override
  String get monitorDetailClientIp => '来源地址';

  @override
  String get monitorDetailKey => '访问密钥';

  @override
  String get monitorDetailProtocol => '入口协议';

  @override
  String get monitorDetailRoute => '模型路由';

  @override
  String get monitorDetailStatus => '状态码';

  @override
  String get monitorDetailTiming => '首字 / 总耗时';

  @override
  String get monitorDetailTokens => '输入 / 输出 Token';

  @override
  String get monitorDetailFailovers => '故障转移次数';

  @override
  String get monitorDetailError => '错误信息';

  @override
  String get playgroundTitle => '在线测试';

  @override
  String get playgroundModelLabel => '选择模型或路由组';

  @override
  String get playgroundKeyLabel => '访问密钥';

  @override
  String get playgroundKeyNone => '本机免密';

  @override
  String get playgroundKeyNotRequired => '密钥保护已关闭（免鉴权）';

  @override
  String get playgroundKeyCustom => '手动输入密钥';

  @override
  String get playgroundKeyCustomHint => '粘贴完整 sk-flc- 访问密钥';

  @override
  String get playgroundPromptLabel => '测试提示词';

  @override
  String get playgroundPromptDefault => '请用一句话回复：Falcon 网关连通正常。';

  @override
  String get playgroundSend => '发送请求';

  @override
  String get playgroundSending => '生成中...';

  @override
  String get playgroundStop => '停止';

  @override
  String get playgroundOutputLabel => '流式响应';

  @override
  String playgroundStreamRate(String rate, String sec) {
    return '$rate tok/s · $sec s';
  }

  @override
  String playgroundMetrics(int ttft, int total, int tokens) {
    return 'TTFT $ttft ms · 总耗时 $total ms · $tokens tokens';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsKeepAliveSection => '后台保活';

  @override
  String get settingsBatteryExemption => '忽略电池优化';

  @override
  String get settingsBatteryGranted => '已授权';

  @override
  String get settingsBatteryNotGranted => '未授权';

  @override
  String get settingsAppBatterySettings => '系统应用设置';

  @override
  String get settingsNotificationPermission => '通知权限';

  @override
  String get settingsBootAutoStart => '开机自启动';

  @override
  String get settingsWakeLock => 'CPU 唤醒锁';

  @override
  String get settingsWifiLock => 'WLAN 性能锁';

  @override
  String get settingsIosBackgroundAudio => '后台静默保活（混音模式）';

  @override
  String get settingsIosBackgroundAudioHint =>
      '使用 AVAudioSession .mixWithOthers 保持本地与局域网监听端口在切入后台后持续活跃（适用于自签与测试分发）';

  @override
  String get settingsIosKeepScreenAwake => '防止锁屏休眠';

  @override
  String get settingsIosKeepScreenAwakeHint => '在前台运行网关期间保持屏幕常亮以防止系统挂起网络套接字';

  @override
  String get settingsIosLocalNetworkTitle => '本地网络与通知权限';

  @override
  String get settingsIosLocalNetworkGuidance =>
      'iOS 系统说明：首次开启局域网访问时请在系统弹窗中允许“本地网络”权限；若长期离线调用，建议开启后台静默保活或保持电源连接。';

  @override
  String get settingsDesktopProcessGuidance =>
      '桌面端以本地守护进程模式运行核心网关，可在网络与安全区调整监听端口与局域网绑定。';

  @override
  String get settingsPluginRuntimeMode => '插件运行时';

  @override
  String get settingsOemGuidance =>
      '厂商后台限制说明：小米、OPPO、vivo、华为等系统请在系统管家中将 Falcon 设为“允许后台高耗电 / 自启动 / 锁定后台任务”，以免锁屏后断连。';

  @override
  String get settingsNetworkSection => '网络与安全';

  @override
  String get settingsPort => '监听端口';

  @override
  String get settingsPortHint => '1024 - 65535，默认 18787';

  @override
  String get settingsAllowIps => 'IP / CIDR 白名单';

  @override
  String get settingsAllowIpsHint => '逗号分隔，留空允许全部来源';

  @override
  String get settingsCorsOrigins => 'CORS 允许来源';

  @override
  String get settingsCorsOriginsHint => '逗号分隔，如 * 或 https://app.example.com';

  @override
  String get settingsChinaMirror => '插件安装国内镜像';

  @override
  String get settingsBackupSection => '备份与恢复';

  @override
  String get settingsBackupExport => '导出配置 JSON';

  @override
  String get settingsBackupExportIncludeSecrets => '导出时包含明文密钥';

  @override
  String get settingsBackupImport => '导入配置 JSON';

  @override
  String get settingsBackupSheetTitle => '配置备份';

  @override
  String get settingsBackupPasteHint => '在此粘贴导出的 JSON 配置内容以恢复';

  @override
  String get settingsBackupImportSuccess => '配置导入成功';

  @override
  String get settingsAppearanceSection => '外观与语言';

  @override
  String get settingsThemeMode => '主题模式';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsLanguage => '显示语言';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get errorGatewayNotRunning => '网关服务未运行，请先在“网关”页启动服务。';

  @override
  String errorRequestFailed(String message) {
    return '请求失败：$message';
  }
}
