import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'Falcon'**
  String get appName;

  /// No description provided for @tabGateway.
  ///
  /// In zh, this message translates to:
  /// **'网关'**
  String get tabGateway;

  /// No description provided for @tabProviders.
  ///
  /// In zh, this message translates to:
  /// **'渠道'**
  String get tabProviders;

  /// No description provided for @tabRouting.
  ///
  /// In zh, this message translates to:
  /// **'路由'**
  String get tabRouting;

  /// No description provided for @tabMonitor.
  ///
  /// In zh, this message translates to:
  /// **'观测'**
  String get tabMonitor;

  /// No description provided for @actionTestConsole.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get actionTestConsole;

  /// No description provided for @actionSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get actionSettings;

  /// No description provided for @actionRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get actionRefresh;

  /// No description provided for @actionAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get actionAdd;

  /// No description provided for @actionEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get actionEdit;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get actionClose;

  /// No description provided for @actionCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get actionCopy;

  /// No description provided for @actionCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get actionCopied;

  /// No description provided for @actionCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get actionCreate;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get actionConfirm;

  /// No description provided for @actionRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get actionRetry;

  /// No description provided for @actionClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get actionClear;

  /// No description provided for @actionTest.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get actionTest;

  /// No description provided for @actionExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get actionExport;

  /// No description provided for @actionImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get actionImport;

  /// No description provided for @statusRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get statusRunning;

  /// No description provided for @statusStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get statusStopped;

  /// No description provided for @statusStarting.
  ///
  /// In zh, this message translates to:
  /// **'正在启动'**
  String get statusStarting;

  /// No description provided for @statusEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get statusEnabled;

  /// No description provided for @statusDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get statusDisabled;

  /// No description provided for @statusConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get statusConnected;

  /// No description provided for @statusDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get statusDisconnected;

  /// No description provided for @statusUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get statusUnknown;

  /// No description provided for @gatewayTitle.
  ///
  /// In zh, this message translates to:
  /// **'网关'**
  String get gatewayTitle;

  /// No description provided for @gatewayHeroSubtitleRunning.
  ///
  /// In zh, this message translates to:
  /// **'本地模型路由与订阅代理已就绪'**
  String get gatewayHeroSubtitleRunning;

  /// No description provided for @gatewayHeroSubtitleStopped.
  ///
  /// In zh, this message translates to:
  /// **'点击启动以监听本地与订阅请求'**
  String get gatewayHeroSubtitleStopped;

  /// No description provided for @gatewayActionStart.
  ///
  /// In zh, this message translates to:
  /// **'启动网关'**
  String get gatewayActionStart;

  /// No description provided for @gatewayActionStop.
  ///
  /// In zh, this message translates to:
  /// **'停止网关'**
  String get gatewayActionStop;

  /// No description provided for @gatewayServiceSection.
  ///
  /// In zh, this message translates to:
  /// **'服务状态'**
  String get gatewayServiceSection;

  /// No description provided for @gatewayServiceToggle.
  ///
  /// In zh, this message translates to:
  /// **'网关服务'**
  String get gatewayServiceToggle;

  /// No description provided for @gatewayUptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时长'**
  String get gatewayUptime;

  /// No description provided for @gatewayCorePid.
  ///
  /// In zh, this message translates to:
  /// **'进程 PID'**
  String get gatewayCorePid;

  /// No description provided for @gatewayModelsCount.
  ///
  /// In zh, this message translates to:
  /// **'可用模型'**
  String get gatewayModelsCount;

  /// No description provided for @gatewayProvidersCount.
  ///
  /// In zh, this message translates to:
  /// **'活跃渠道'**
  String get gatewayProvidersCount;

  /// No description provided for @gatewayBadgeForeground.
  ///
  /// In zh, this message translates to:
  /// **'前台常驻'**
  String get gatewayBadgeForeground;

  /// No description provided for @gatewayBadgeWakeLock.
  ///
  /// In zh, this message translates to:
  /// **'唤醒锁'**
  String get gatewayBadgeWakeLock;

  /// No description provided for @gatewayBadgeWifiLock.
  ///
  /// In zh, this message translates to:
  /// **'WLAN 锁'**
  String get gatewayBadgeWifiLock;

  /// No description provided for @gatewayBadgeAudioKeepAlive.
  ///
  /// In zh, this message translates to:
  /// **'后台混音保活'**
  String get gatewayBadgeAudioKeepAlive;

  /// No description provided for @gatewayBadgeScreenAwake.
  ///
  /// In zh, this message translates to:
  /// **'屏幕常亮'**
  String get gatewayBadgeScreenAwake;

  /// No description provided for @gatewayBadgeDesktopProcess.
  ///
  /// In zh, this message translates to:
  /// **'本地进程'**
  String get gatewayBadgeDesktopProcess;

  /// No description provided for @gatewayBatteryBannerTitle.
  ///
  /// In zh, this message translates to:
  /// **'未忽略电池优化'**
  String get gatewayBatteryBannerTitle;

  /// No description provided for @gatewayBatteryBannerBody.
  ///
  /// In zh, this message translates to:
  /// **'系统休眠后可能中断本地与局域网代理，建议授予忽略电池优化权限。'**
  String get gatewayBatteryBannerBody;

  /// No description provided for @gatewayBatteryGrant.
  ///
  /// In zh, this message translates to:
  /// **'立即授权'**
  String get gatewayBatteryGrant;

  /// No description provided for @gatewayNotifBannerTitle.
  ///
  /// In zh, this message translates to:
  /// **'未开启通知权限'**
  String get gatewayNotifBannerTitle;

  /// No description provided for @gatewayNotifBannerBody.
  ///
  /// In zh, this message translates to:
  /// **'Android 前台服务需要通知权限以维持后台保活状态。'**
  String get gatewayNotifBannerBody;

  /// No description provided for @gatewayNotifGrant.
  ///
  /// In zh, this message translates to:
  /// **'开启通知'**
  String get gatewayNotifGrant;

  /// No description provided for @gatewayEndpointsSection.
  ///
  /// In zh, this message translates to:
  /// **'访问端点'**
  String get gatewayEndpointsSection;

  /// No description provided for @gatewayLoopbackLabel.
  ///
  /// In zh, this message translates to:
  /// **'本机端点'**
  String get gatewayLoopbackLabel;

  /// No description provided for @gatewayLanUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'局域网地址'**
  String get gatewayLanUrlLabel;

  /// No description provided for @gatewayLocalKeyless.
  ///
  /// In zh, this message translates to:
  /// **'本机免密访问'**
  String get gatewayLocalKeyless;

  /// No description provided for @gatewayLocalKeylessHint.
  ///
  /// In zh, this message translates to:
  /// **'仅本机 127.0.0.1 请求免密钥'**
  String get gatewayLocalKeylessHint;

  /// No description provided for @gatewayLanAccess.
  ///
  /// In zh, this message translates to:
  /// **'局域网访问'**
  String get gatewayLanAccess;

  /// No description provided for @gatewayLanAccessHint.
  ///
  /// In zh, this message translates to:
  /// **'允许同局域网设备连接'**
  String get gatewayLanAccessHint;

  /// No description provided for @gatewaySecuritySection.
  ///
  /// In zh, this message translates to:
  /// **'访问鉴权'**
  String get gatewaySecuritySection;

  /// No description provided for @gatewayRequireAccessKey.
  ///
  /// In zh, this message translates to:
  /// **'访问密钥保护'**
  String get gatewayRequireAccessKey;

  /// No description provided for @gatewayRequireAccessKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'启用后请求需携带访问密钥'**
  String get gatewayRequireAccessKeyHint;

  /// No description provided for @gatewayLanRequireKey.
  ///
  /// In zh, this message translates to:
  /// **'局域网请求校验密钥'**
  String get gatewayLanRequireKey;

  /// No description provided for @gatewayLanRequireKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'要求局域网客户端提供访问密钥'**
  String get gatewayLanRequireKeyHint;

  /// No description provided for @gatewayLanNoIp.
  ///
  /// In zh, this message translates to:
  /// **'当前未检测到局域网 IPv4 地址'**
  String get gatewayLanNoIp;

  /// No description provided for @gatewayClientExamples.
  ///
  /// In zh, this message translates to:
  /// **'客户端接入示例'**
  String get gatewayClientExamples;

  /// No description provided for @gatewayClientExamplesTitle.
  ///
  /// In zh, this message translates to:
  /// **'客户端接入示例'**
  String get gatewayClientExamplesTitle;

  /// No description provided for @gatewayClientOpenAi.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 兼容接口'**
  String get gatewayClientOpenAi;

  /// No description provided for @gatewayClientAnthropic.
  ///
  /// In zh, this message translates to:
  /// **'Anthropic 兼容接口'**
  String get gatewayClientAnthropic;

  /// No description provided for @gatewayClientGemini.
  ///
  /// In zh, this message translates to:
  /// **'Gemini 兼容接口'**
  String get gatewayClientGemini;

  /// No description provided for @gatewayClientCurl.
  ///
  /// In zh, this message translates to:
  /// **'cURL 验证示例'**
  String get gatewayClientCurl;

  /// No description provided for @gatewayClientAuthNote.
  ///
  /// In zh, this message translates to:
  /// **'已开启访问密钥保护时，请在 Authorization 请求头或 x-api-key 中传入密钥。'**
  String get gatewayClientAuthNote;

  /// No description provided for @gatewayClientKeylessNote.
  ///
  /// In zh, this message translates to:
  /// **'当前未开启访问密钥保护，客户端可直接访问上述地址。'**
  String get gatewayClientKeylessNote;

  /// No description provided for @gatewayKeysSection.
  ///
  /// In zh, this message translates to:
  /// **'访问密钥'**
  String get gatewayKeysSection;

  /// No description provided for @gatewayKeysEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未创建访问密钥'**
  String get gatewayKeysEmpty;

  /// No description provided for @gatewayKeysEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'局域网接入或配额管控需创建 sk-flc- 前缀密钥。'**
  String get gatewayKeysEmptyHint;

  /// No description provided for @gatewayKeyCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建访问密钥'**
  String get gatewayKeyCreateTitle;

  /// No description provided for @gatewayKeyCreatedNotice.
  ///
  /// In zh, this message translates to:
  /// **'请立即复制并妥善保存完整密钥，关闭后将不再完整显示。'**
  String get gatewayKeyCreatedNotice;

  /// No description provided for @gatewayKeyNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'密钥名称'**
  String get gatewayKeyNameLabel;

  /// No description provided for @gatewayKeyNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：MacBook 开发机'**
  String get gatewayKeyNameHint;

  /// No description provided for @gatewayKeyModelsLabel.
  ///
  /// In zh, this message translates to:
  /// **'允许访问的模型（留空表示全部）'**
  String get gatewayKeyModelsLabel;

  /// No description provided for @gatewayKeyModelsHint.
  ///
  /// In zh, this message translates to:
  /// **'逗号分隔，如 gpt-4o, deepseek-chat'**
  String get gatewayKeyModelsHint;

  /// No description provided for @gatewayKeyDailyUsdLabel.
  ///
  /// In zh, this message translates to:
  /// **'每日预算上限（USD，0 为不限）'**
  String get gatewayKeyDailyUsdLabel;

  /// No description provided for @gatewayKeyMonthlyUsdLabel.
  ///
  /// In zh, this message translates to:
  /// **'每月预算上限（USD，0 为不限）'**
  String get gatewayKeyMonthlyUsdLabel;

  /// No description provided for @gatewayKeyDailyReqsLabel.
  ///
  /// In zh, this message translates to:
  /// **'每日请求上限（0 为不限）'**
  String get gatewayKeyDailyReqsLabel;

  /// No description provided for @gatewayKeyRotate.
  ///
  /// In zh, this message translates to:
  /// **'轮换密钥'**
  String get gatewayKeyRotate;

  /// No description provided for @gatewayKeyRotateConfirm.
  ///
  /// In zh, this message translates to:
  /// **'轮换后旧密钥将立即失效，确认继续吗？'**
  String get gatewayKeyRotateConfirm;

  /// No description provided for @gatewayKeyDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认删除访问密钥“{name}”吗？'**
  String gatewayKeyDeleteConfirm(String name);

  /// No description provided for @gatewayKeyUsageSummary.
  ///
  /// In zh, this message translates to:
  /// **'今日 {reqs} 次 · {usd} USD'**
  String gatewayKeyUsageSummary(int reqs, String usd);

  /// No description provided for @providersTitle.
  ///
  /// In zh, this message translates to:
  /// **'渠道'**
  String get providersTitle;

  /// No description provided for @providersSegmentApi.
  ///
  /// In zh, this message translates to:
  /// **'接口渠道'**
  String get providersSegmentApi;

  /// No description provided for @providersSegmentPlugins.
  ///
  /// In zh, this message translates to:
  /// **'订阅插件'**
  String get providersSegmentPlugins;

  /// No description provided for @providersApiEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置接口渠道'**
  String get providersApiEmpty;

  /// No description provided for @providersApiEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'添加 OpenAI、Anthropic、DeepSeek 或自定义兼容上游。'**
  String get providersApiEmptyHint;

  /// No description provided for @providersAddFromPreset.
  ///
  /// In zh, this message translates to:
  /// **'从预设添加'**
  String get providersAddFromPreset;

  /// No description provided for @providersAddCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义渠道'**
  String get providersAddCustom;

  /// No description provided for @providersPresetTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择渠道预设'**
  String get providersPresetTitle;

  /// No description provided for @providersEditorAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加接口渠道'**
  String get providersEditorAddTitle;

  /// No description provided for @providersEditorEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑接口渠道'**
  String get providersEditorEditTitle;

  /// No description provided for @providersNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'渠道名称'**
  String get providersNameLabel;

  /// No description provided for @providersProtocolLabel.
  ///
  /// In zh, this message translates to:
  /// **'上游协议'**
  String get providersProtocolLabel;

  /// No description provided for @providersBaseUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'Base URL'**
  String get providersBaseUrlLabel;

  /// No description provided for @providersKeysLabel.
  ///
  /// In zh, this message translates to:
  /// **'上游密钥池'**
  String get providersKeysLabel;

  /// No description provided for @providersAddKey.
  ///
  /// In zh, this message translates to:
  /// **'添加密钥'**
  String get providersAddKey;

  /// No description provided for @providersKeyLabelHint.
  ///
  /// In zh, this message translates to:
  /// **'备注（可选）'**
  String get providersKeyLabelHint;

  /// No description provided for @providersKeySecretHint.
  ///
  /// In zh, this message translates to:
  /// **'输入新密钥（留空保持不变）'**
  String get providersKeySecretHint;

  /// No description provided for @providersKeyWeightLabel.
  ///
  /// In zh, this message translates to:
  /// **'权重'**
  String get providersKeyWeightLabel;

  /// No description provided for @providersFetchModels.
  ///
  /// In zh, this message translates to:
  /// **'拉取模型'**
  String get providersFetchModels;

  /// No description provided for @providersFetchingModels.
  ///
  /// In zh, this message translates to:
  /// **'正在拉取模型...'**
  String get providersFetchingModels;

  /// No description provided for @providersModelsFetched.
  ///
  /// In zh, this message translates to:
  /// **'已获取 {count} 个模型'**
  String providersModelsFetched(int count);

  /// No description provided for @providersSelectedModels.
  ///
  /// In zh, this message translates to:
  /// **'启用模型（{count}）'**
  String providersSelectedModels(int count);

  /// No description provided for @providersManualModelHint.
  ///
  /// In zh, this message translates to:
  /// **'手动添加模型 ID（逗号分隔）'**
  String get providersManualModelHint;

  /// No description provided for @providersTestConnectivity.
  ///
  /// In zh, this message translates to:
  /// **'连通性测试'**
  String get providersTestConnectivity;

  /// No description provided for @providersTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get providersTesting;

  /// No description provided for @providersTestPass.
  ///
  /// In zh, this message translates to:
  /// **'正常 · {ms} ms'**
  String providersTestPass(int ms);

  /// No description provided for @providersTestFail.
  ///
  /// In zh, this message translates to:
  /// **'失败 · HTTP {code}'**
  String providersTestFail(int code);

  /// No description provided for @providersDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认删除渠道“{name}”吗？'**
  String providersDeleteConfirm(String name);

  /// No description provided for @pluginsDirectoryAction.
  ///
  /// In zh, this message translates to:
  /// **'插件目录'**
  String get pluginsDirectoryAction;

  /// No description provided for @pluginsRefreshQuotas.
  ///
  /// In zh, this message translates to:
  /// **'刷新额度'**
  String get pluginsRefreshQuotas;

  /// No description provided for @pluginsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未安装订阅插件'**
  String get pluginsEmpty;

  /// No description provided for @pluginsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'打开插件目录安装社区认证插件并同步额度。'**
  String get pluginsEmptyHint;

  /// No description provided for @pluginsSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录账号'**
  String get pluginsSignIn;

  /// No description provided for @pluginsSignOut.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get pluginsSignOut;

  /// No description provided for @pluginsSignOutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认退出账号“{label}”吗？'**
  String pluginsSignOutConfirm(String label);

  /// No description provided for @pluginsCheckin.
  ///
  /// In zh, this message translates to:
  /// **'签到'**
  String get pluginsCheckin;

  /// No description provided for @pluginsCheckinResult.
  ///
  /// In zh, this message translates to:
  /// **'签到结果：{outcome}'**
  String pluginsCheckinResult(String outcome);

  /// No description provided for @pluginsAccountsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个账号'**
  String pluginsAccountsCount(int count);

  /// No description provided for @pluginsMarketTitle.
  ///
  /// In zh, this message translates to:
  /// **'插件目录'**
  String get pluginsMarketTitle;

  /// No description provided for @pluginsMarketSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索插件名称、包名或模型服务'**
  String get pluginsMarketSearchHint;

  /// No description provided for @pluginsMarketChinaMirror.
  ///
  /// In zh, this message translates to:
  /// **'国内镜像'**
  String get pluginsMarketChinaMirror;

  /// No description provided for @pluginsMarketCategoryAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get pluginsMarketCategoryAll;

  /// No description provided for @pluginsMarketCategoryAuth.
  ///
  /// In zh, this message translates to:
  /// **'订阅认证'**
  String get pluginsMarketCategoryAuth;

  /// No description provided for @pluginsMarketCategoryMiddleware.
  ///
  /// In zh, this message translates to:
  /// **'请求中间件'**
  String get pluginsMarketCategoryMiddleware;

  /// No description provided for @pluginsMarketInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get pluginsMarketInstall;

  /// No description provided for @pluginsMarketRemove.
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get pluginsMarketRemove;

  /// No description provided for @pluginsMarketInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get pluginsMarketInstalled;

  /// No description provided for @pluginsMarketCustomSpecHint.
  ///
  /// In zh, this message translates to:
  /// **'输入 npm 包名或 Git 规格安装'**
  String get pluginsMarketCustomSpecHint;

  /// No description provided for @pluginsSignInTitle.
  ///
  /// In zh, this message translates to:
  /// **'插件账号认证'**
  String get pluginsSignInTitle;

  /// No description provided for @pluginsSignInPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在初始化认证会话...'**
  String get pluginsSignInPreparing;

  /// No description provided for @pluginsSignInOpenBrowser.
  ///
  /// In zh, this message translates to:
  /// **'在浏览器中完成登录'**
  String get pluginsSignInOpenBrowser;

  /// No description provided for @pluginsSignInOpenBrowserHint.
  ///
  /// In zh, this message translates to:
  /// **'如果浏览器未自动打开，可手动打开或复制链接。'**
  String get pluginsSignInOpenBrowserHint;

  /// No description provided for @pluginsSignInReopenBrowser.
  ///
  /// In zh, this message translates to:
  /// **'打开认证页面'**
  String get pluginsSignInReopenBrowser;

  /// No description provided for @pluginsSignInCopyUrl.
  ///
  /// In zh, this message translates to:
  /// **'复制链接'**
  String get pluginsSignInCopyUrl;

  /// No description provided for @pluginsSignInDeviceCode.
  ///
  /// In zh, this message translates to:
  /// **'设备授权码'**
  String get pluginsSignInDeviceCode;

  /// No description provided for @pluginsSignInDeviceCodeHint.
  ///
  /// In zh, this message translates to:
  /// **'打开验证页面并输入上方授权码。'**
  String get pluginsSignInDeviceCodeHint;

  /// No description provided for @pluginsSignInPasteCallback.
  ///
  /// In zh, this message translates to:
  /// **'输入回调 URL 或授权码'**
  String get pluginsSignInPasteCallback;

  /// No description provided for @pluginsSignInPasteHint.
  ///
  /// In zh, this message translates to:
  /// **'将浏览器跳转后的完整回调地址或凭证粘贴至此处'**
  String get pluginsSignInPasteHint;

  /// No description provided for @pluginsSignInSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交验证'**
  String get pluginsSignInSubmit;

  /// No description provided for @pluginsSignInSuccess.
  ///
  /// In zh, this message translates to:
  /// **'认证已完成'**
  String get pluginsSignInSuccess;

  /// No description provided for @pluginsSignInFailed.
  ///
  /// In zh, this message translates to:
  /// **'认证未完成'**
  String get pluginsSignInFailed;

  /// No description provided for @pluginsSelectModels.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get pluginsSelectModels;

  /// No description provided for @pluginsModelsRowLabel.
  ///
  /// In zh, this message translates to:
  /// **'可用模型'**
  String get pluginsModelsRowLabel;

  /// No description provided for @pluginsActionSignInShort.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get pluginsActionSignInShort;

  /// No description provided for @pluginsAuthMethodBrowser.
  ///
  /// In zh, this message translates to:
  /// **'浏览器授权登录'**
  String get pluginsAuthMethodBrowser;

  /// No description provided for @pluginsAuthMethodApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API 密钥接入'**
  String get pluginsAuthMethodApiKey;

  /// No description provided for @pluginsSelectedModelsSummary.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count}/{total}'**
  String pluginsSelectedModelsSummary(int count, int total);

  /// No description provided for @pluginsAutoAllModels.
  ///
  /// In zh, this message translates to:
  /// **'全部 {total} 个'**
  String pluginsAutoAllModels(int total);

  /// No description provided for @pluginsTestInPlayground.
  ///
  /// In zh, this message translates to:
  /// **'在线测试'**
  String get pluginsTestInPlayground;

  /// No description provided for @pluginsRefreshPlugin.
  ///
  /// In zh, this message translates to:
  /// **'刷新状态'**
  String get pluginsRefreshPlugin;

  /// No description provided for @pluginsAddAccount.
  ///
  /// In zh, this message translates to:
  /// **'添加账号'**
  String get pluginsAddAccount;

  /// No description provided for @pluginsAuthenticated.
  ///
  /// In zh, this message translates to:
  /// **'已认证'**
  String get pluginsAuthenticated;

  /// No description provided for @pluginsNotAuthenticated.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get pluginsNotAuthenticated;

  /// No description provided for @pluginsModelsTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型选择'**
  String get pluginsModelsTitle;

  /// No description provided for @pluginsModelsSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型 ID 或名称'**
  String get pluginsModelsSearchHint;

  /// No description provided for @pluginsModelsFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get pluginsModelsFilterAll;

  /// No description provided for @pluginsModelsFilterSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选'**
  String get pluginsModelsFilterSelected;

  /// No description provided for @pluginsModelsFilterFree.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get pluginsModelsFilterFree;

  /// No description provided for @pluginsModelsSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get pluginsModelsSelectAll;

  /// No description provided for @pluginsModelsClearAuto.
  ///
  /// In zh, this message translates to:
  /// **'清空（自动）'**
  String get pluginsModelsClearAuto;

  /// No description provided for @pluginsModelsAutoBanner.
  ///
  /// In zh, this message translates to:
  /// **'未勾选特定模型时，网关将自动暴露当前服务商的全部可用模型。'**
  String get pluginsModelsAutoBanner;

  /// No description provided for @pluginsModelsCapReasoning.
  ///
  /// In zh, this message translates to:
  /// **'推理'**
  String get pluginsModelsCapReasoning;

  /// No description provided for @pluginsModelsCapTools.
  ///
  /// In zh, this message translates to:
  /// **'工具调用'**
  String get pluginsModelsCapTools;

  /// No description provided for @pluginsModelsCapFree.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get pluginsModelsCapFree;

  /// No description provided for @pluginsModelsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无可选模型，请先登录后刷新或手动刷新目录'**
  String get pluginsModelsEmpty;

  /// No description provided for @pluginsEditionLabel.
  ///
  /// In zh, this message translates to:
  /// **'服务版本 / 区域'**
  String get pluginsEditionLabel;

  /// No description provided for @pluginsEditionWorkbuddyCn.
  ///
  /// In zh, this message translates to:
  /// **'WorkBuddy 国内版 (copilot.tencent.com)'**
  String get pluginsEditionWorkbuddyCn;

  /// No description provided for @pluginsEditionWorkbuddyIntl.
  ///
  /// In zh, this message translates to:
  /// **'WorkBuddy 国际版 (www.workbuddy.ai)'**
  String get pluginsEditionWorkbuddyIntl;

  /// No description provided for @pluginsAuthMethodLabel.
  ///
  /// In zh, this message translates to:
  /// **'认证方式'**
  String get pluginsAuthMethodLabel;

  /// No description provided for @pluginsAuthOpenAutoHint.
  ///
  /// In zh, this message translates to:
  /// **'已在浏览器中打开授权页面，完成登录后将自动同步账号与模型。'**
  String get pluginsAuthOpenAutoHint;

  /// No description provided for @routingTitle.
  ///
  /// In zh, this message translates to:
  /// **'路由'**
  String get routingTitle;

  /// No description provided for @routingSegmentGroups.
  ///
  /// In zh, this message translates to:
  /// **'路由组'**
  String get routingSegmentGroups;

  /// No description provided for @routingSegmentAliases.
  ///
  /// In zh, this message translates to:
  /// **'模型映射'**
  String get routingSegmentAliases;

  /// No description provided for @routingGroupsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置路由组'**
  String get routingGroupsEmpty;

  /// No description provided for @routingGroupsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'将多个渠道模型组合，实现顺序回退、轮询或最低延迟调度。'**
  String get routingGroupsEmptyHint;

  /// No description provided for @routingGroupAdd.
  ///
  /// In zh, this message translates to:
  /// **'新建路由组'**
  String get routingGroupAdd;

  /// No description provided for @routingGroupEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑路由组'**
  String get routingGroupEdit;

  /// No description provided for @routingGroupNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'路由组名称（对外模型名）'**
  String get routingGroupNameLabel;

  /// No description provided for @routingGroupStrategyLabel.
  ///
  /// In zh, this message translates to:
  /// **'调度策略'**
  String get routingGroupStrategyLabel;

  /// No description provided for @routingStrategyOrder.
  ///
  /// In zh, this message translates to:
  /// **'顺序回退 (order)'**
  String get routingStrategyOrder;

  /// No description provided for @routingStrategyRoundRobin.
  ///
  /// In zh, this message translates to:
  /// **'轮询均衡 (round_robin)'**
  String get routingStrategyRoundRobin;

  /// No description provided for @routingStrategyFastest.
  ///
  /// In zh, this message translates to:
  /// **'最低 TTFT (fastest)'**
  String get routingStrategyFastest;

  /// No description provided for @routingStrategyManual.
  ///
  /// In zh, this message translates to:
  /// **'手动指定 (manual)'**
  String get routingStrategyManual;

  /// No description provided for @routingGroupPinnedLabel.
  ///
  /// In zh, this message translates to:
  /// **'锁定目标成员'**
  String get routingGroupPinnedLabel;

  /// No description provided for @routingGroupMembersLabel.
  ///
  /// In zh, this message translates to:
  /// **'成员列表（provider/model）'**
  String get routingGroupMembersLabel;

  /// No description provided for @routingGroupMembersHint.
  ///
  /// In zh, this message translates to:
  /// **'每行一个或逗号分隔，如 deepseek/deepseek-chat'**
  String get routingGroupMembersHint;

  /// No description provided for @routingGroupDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认删除路由组“{name}”吗？'**
  String routingGroupDeleteConfirm(String name);

  /// No description provided for @routingMembersSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个目标 · {strategy}'**
  String routingMembersSummary(int count, String strategy);

  /// No description provided for @routingAliasesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置模型映射'**
  String get routingAliasesEmpty;

  /// No description provided for @routingAliasesEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'将客户端请求的模型名重写为指定的上游渠道模型或路由组。'**
  String get routingAliasesEmptyHint;

  /// No description provided for @routingAliasAdd.
  ///
  /// In zh, this message translates to:
  /// **'新建映射'**
  String get routingAliasAdd;

  /// No description provided for @routingAliasEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑映射'**
  String get routingAliasEdit;

  /// No description provided for @routingAliasSourceLabel.
  ///
  /// In zh, this message translates to:
  /// **'请求模型名'**
  String get routingAliasSourceLabel;

  /// No description provided for @routingAliasSourceHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：gpt-4o'**
  String get routingAliasSourceHint;

  /// No description provided for @routingAliasTargetLabel.
  ///
  /// In zh, this message translates to:
  /// **'目标模型或路由组'**
  String get routingAliasTargetLabel;

  /// No description provided for @routingAliasTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：deepseek/deepseek-chat'**
  String get routingAliasTargetHint;

  /// No description provided for @monitorTitle.
  ///
  /// In zh, this message translates to:
  /// **'观测'**
  String get monitorTitle;

  /// No description provided for @monitorRangeToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get monitorRangeToday;

  /// No description provided for @monitorRange7d.
  ///
  /// In zh, this message translates to:
  /// **'7 日'**
  String get monitorRange7d;

  /// No description provided for @monitorRange30d.
  ///
  /// In zh, this message translates to:
  /// **'30 日'**
  String get monitorRange30d;

  /// No description provided for @monitorKpiRequests.
  ///
  /// In zh, this message translates to:
  /// **'总请求数'**
  String get monitorKpiRequests;

  /// No description provided for @monitorKpiTokens.
  ///
  /// In zh, this message translates to:
  /// **'总 Token'**
  String get monitorKpiTokens;

  /// No description provided for @monitorKpiSpend.
  ///
  /// In zh, this message translates to:
  /// **'估算费用'**
  String get monitorKpiSpend;

  /// No description provided for @monitorKpiTtft.
  ///
  /// In zh, this message translates to:
  /// **'平均 TTFT'**
  String get monitorKpiTtft;

  /// No description provided for @monitorOpenPlayground.
  ///
  /// In zh, this message translates to:
  /// **'在线测试'**
  String get monitorOpenPlayground;

  /// No description provided for @monitorLogsSection.
  ///
  /// In zh, this message translates to:
  /// **'请求日志'**
  String get monitorLogsSection;

  /// No description provided for @monitorLogsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无请求记录'**
  String get monitorLogsEmpty;

  /// No description provided for @monitorLogsClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认清空所有历史请求日志吗？'**
  String get monitorLogsClearConfirm;

  /// No description provided for @monitorSourceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本机 127.0.0.1'**
  String get monitorSourceLocal;

  /// No description provided for @monitorSourceLan.
  ///
  /// In zh, this message translates to:
  /// **'局域网 {ip}'**
  String monitorSourceLan(String ip);

  /// No description provided for @monitorDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'请求详情'**
  String get monitorDetailTitle;

  /// No description provided for @monitorDetailClientIp.
  ///
  /// In zh, this message translates to:
  /// **'来源地址'**
  String get monitorDetailClientIp;

  /// No description provided for @monitorDetailKey.
  ///
  /// In zh, this message translates to:
  /// **'访问密钥'**
  String get monitorDetailKey;

  /// No description provided for @monitorDetailProtocol.
  ///
  /// In zh, this message translates to:
  /// **'入口协议'**
  String get monitorDetailProtocol;

  /// No description provided for @monitorDetailRoute.
  ///
  /// In zh, this message translates to:
  /// **'模型路由'**
  String get monitorDetailRoute;

  /// No description provided for @monitorDetailStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态码'**
  String get monitorDetailStatus;

  /// No description provided for @monitorDetailTiming.
  ///
  /// In zh, this message translates to:
  /// **'首字 / 总耗时'**
  String get monitorDetailTiming;

  /// No description provided for @monitorDetailTokens.
  ///
  /// In zh, this message translates to:
  /// **'输入 / 输出 Token'**
  String get monitorDetailTokens;

  /// No description provided for @monitorDetailFailovers.
  ///
  /// In zh, this message translates to:
  /// **'故障转移次数'**
  String get monitorDetailFailovers;

  /// No description provided for @monitorDetailError.
  ///
  /// In zh, this message translates to:
  /// **'错误信息'**
  String get monitorDetailError;

  /// No description provided for @playgroundTitle.
  ///
  /// In zh, this message translates to:
  /// **'在线测试'**
  String get playgroundTitle;

  /// No description provided for @playgroundModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型或路由组'**
  String get playgroundModelLabel;

  /// No description provided for @playgroundKeyLabel.
  ///
  /// In zh, this message translates to:
  /// **'访问密钥'**
  String get playgroundKeyLabel;

  /// No description provided for @playgroundKeyNone.
  ///
  /// In zh, this message translates to:
  /// **'本机免密'**
  String get playgroundKeyNone;

  /// No description provided for @playgroundKeyNotRequired.
  ///
  /// In zh, this message translates to:
  /// **'密钥保护已关闭（免鉴权）'**
  String get playgroundKeyNotRequired;

  /// No description provided for @playgroundKeyCustom.
  ///
  /// In zh, this message translates to:
  /// **'手动输入密钥'**
  String get playgroundKeyCustom;

  /// No description provided for @playgroundKeyCustomHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴完整 sk-flc- 访问密钥'**
  String get playgroundKeyCustomHint;

  /// No description provided for @playgroundPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'测试提示词'**
  String get playgroundPromptLabel;

  /// No description provided for @playgroundPromptDefault.
  ///
  /// In zh, this message translates to:
  /// **'请简短回复：Falcon 网关连通正常。'**
  String get playgroundPromptDefault;

  /// No description provided for @playgroundSend.
  ///
  /// In zh, this message translates to:
  /// **'发送请求'**
  String get playgroundSend;

  /// No description provided for @playgroundSending.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get playgroundSending;

  /// No description provided for @playgroundStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get playgroundStop;

  /// No description provided for @playgroundOutputLabel.
  ///
  /// In zh, this message translates to:
  /// **'流式响应'**
  String get playgroundOutputLabel;

  /// No description provided for @playgroundStreamRate.
  ///
  /// In zh, this message translates to:
  /// **'{rate} tok/s · {sec} s'**
  String playgroundStreamRate(String rate, String sec);

  /// No description provided for @playgroundMetrics.
  ///
  /// In zh, this message translates to:
  /// **'TTFT {ttft} ms · 总耗时 {total} ms · {tokens} tokens'**
  String playgroundMetrics(int ttft, int total, int tokens);

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsKeepAliveSection.
  ///
  /// In zh, this message translates to:
  /// **'后台保活'**
  String get settingsKeepAliveSection;

  /// No description provided for @settingsBatteryExemption.
  ///
  /// In zh, this message translates to:
  /// **'忽略电池优化'**
  String get settingsBatteryExemption;

  /// No description provided for @settingsBatteryGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get settingsBatteryGranted;

  /// No description provided for @settingsBatteryNotGranted.
  ///
  /// In zh, this message translates to:
  /// **'未授权'**
  String get settingsBatteryNotGranted;

  /// No description provided for @settingsAppBatterySettings.
  ///
  /// In zh, this message translates to:
  /// **'系统应用设置'**
  String get settingsAppBatterySettings;

  /// No description provided for @settingsNotificationPermission.
  ///
  /// In zh, this message translates to:
  /// **'通知权限'**
  String get settingsNotificationPermission;

  /// No description provided for @settingsBootAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启动'**
  String get settingsBootAutoStart;

  /// No description provided for @settingsWakeLock.
  ///
  /// In zh, this message translates to:
  /// **'CPU 唤醒锁'**
  String get settingsWakeLock;

  /// No description provided for @settingsWifiLock.
  ///
  /// In zh, this message translates to:
  /// **'WLAN 性能锁'**
  String get settingsWifiLock;

  /// No description provided for @settingsIosBackgroundAudio.
  ///
  /// In zh, this message translates to:
  /// **'后台静默保活（混音模式）'**
  String get settingsIosBackgroundAudio;

  /// No description provided for @settingsIosBackgroundAudioHint.
  ///
  /// In zh, this message translates to:
  /// **'使用 AVAudioSession .mixWithOthers 保持本地与局域网监听端口在切入后台后持续活跃（适用于自签与测试分发）'**
  String get settingsIosBackgroundAudioHint;

  /// No description provided for @settingsIosKeepScreenAwake.
  ///
  /// In zh, this message translates to:
  /// **'防止锁屏休眠'**
  String get settingsIosKeepScreenAwake;

  /// No description provided for @settingsIosKeepScreenAwakeHint.
  ///
  /// In zh, this message translates to:
  /// **'在前台运行网关期间保持屏幕常亮以防止系统挂起网络套接字'**
  String get settingsIosKeepScreenAwakeHint;

  /// No description provided for @settingsIosLocalNetworkTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地网络与通知权限'**
  String get settingsIosLocalNetworkTitle;

  /// No description provided for @settingsIosLocalNetworkGuidance.
  ///
  /// In zh, this message translates to:
  /// **'iOS 系统说明：首次开启局域网访问时请在系统弹窗中允许“本地网络”权限；若长期离线调用，建议开启后台静默保活或保持电源连接。'**
  String get settingsIosLocalNetworkGuidance;

  /// No description provided for @settingsDesktopProcessGuidance.
  ///
  /// In zh, this message translates to:
  /// **'桌面端以本地守护进程模式运行核心网关，可在网络与安全区调整监听端口与局域网绑定。'**
  String get settingsDesktopProcessGuidance;

  /// No description provided for @settingsPluginRuntimeMode.
  ///
  /// In zh, this message translates to:
  /// **'插件运行时'**
  String get settingsPluginRuntimeMode;

  /// No description provided for @settingsOemGuidance.
  ///
  /// In zh, this message translates to:
  /// **'厂商后台限制说明：小米、OPPO、vivo、华为等系统请在系统管家中将 Falcon 设为“允许后台高耗电 / 自启动 / 锁定后台任务”，以免锁屏后断连。'**
  String get settingsOemGuidance;

  /// No description provided for @settingsNetworkSection.
  ///
  /// In zh, this message translates to:
  /// **'网络与安全'**
  String get settingsNetworkSection;

  /// No description provided for @settingsPort.
  ///
  /// In zh, this message translates to:
  /// **'监听端口'**
  String get settingsPort;

  /// No description provided for @settingsPortHint.
  ///
  /// In zh, this message translates to:
  /// **'1024 - 65535，默认 18787'**
  String get settingsPortHint;

  /// No description provided for @settingsAllowIps.
  ///
  /// In zh, this message translates to:
  /// **'IP / CIDR 白名单'**
  String get settingsAllowIps;

  /// No description provided for @settingsAllowIpsHint.
  ///
  /// In zh, this message translates to:
  /// **'逗号分隔，留空允许全部来源'**
  String get settingsAllowIpsHint;

  /// No description provided for @settingsCorsOrigins.
  ///
  /// In zh, this message translates to:
  /// **'CORS 允许来源'**
  String get settingsCorsOrigins;

  /// No description provided for @settingsCorsOriginsHint.
  ///
  /// In zh, this message translates to:
  /// **'逗号分隔，如 * 或 https://app.example.com'**
  String get settingsCorsOriginsHint;

  /// No description provided for @settingsChinaMirror.
  ///
  /// In zh, this message translates to:
  /// **'插件安装国内镜像'**
  String get settingsChinaMirror;

  /// No description provided for @settingsBackupSection.
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get settingsBackupSection;

  /// No description provided for @settingsBackupExport.
  ///
  /// In zh, this message translates to:
  /// **'导出配置 JSON'**
  String get settingsBackupExport;

  /// No description provided for @settingsBackupExportIncludeSecrets.
  ///
  /// In zh, this message translates to:
  /// **'导出时包含明文密钥'**
  String get settingsBackupExportIncludeSecrets;

  /// No description provided for @settingsBackupImport.
  ///
  /// In zh, this message translates to:
  /// **'导入配置 JSON'**
  String get settingsBackupImport;

  /// No description provided for @settingsBackupSheetTitle.
  ///
  /// In zh, this message translates to:
  /// **'配置备份'**
  String get settingsBackupSheetTitle;

  /// No description provided for @settingsBackupPasteHint.
  ///
  /// In zh, this message translates to:
  /// **'在此粘贴导出的 JSON 配置内容以恢复'**
  String get settingsBackupPasteHint;

  /// No description provided for @settingsBackupImportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'配置导入成功'**
  String get settingsBackupImportSuccess;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In zh, this message translates to:
  /// **'外观与语言'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get settingsThemeMode;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'显示语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @errorGatewayNotRunning.
  ///
  /// In zh, this message translates to:
  /// **'网关服务未运行，请先在“网关”页启动服务。'**
  String get errorGatewayNotRunning;

  /// No description provided for @errorRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求失败：{message}'**
  String errorRequestFailed(String message);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
