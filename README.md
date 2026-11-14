# Falcon

面向移动端与局域网的轻量 AI 网关及订阅插件反向代理应用（Flutter + Go Core）。

## 核心能力

- **本机与局域网服务**：默认开放本机回环端点（`127.0.0.1:18787`），按需开启局域网访问并支持可选访问密钥校验、IP/CIDR 白名单与 CORS origins 配置。
- **多协议兼容**：支持 OpenAI Chat Completions、OpenAI Responses、Anthropic Messages 与 Google Gemini 接口互转及实时流式响应。
- **Magpie 订阅插件生态**：内置嵌入式 Bun 运行时，支持 WorkBuddy（国内版 `copilot.tencent.com` / 国际版 `www.workbuddy.ai`）、Cursor、Qoder、ZCode、Kimi Code 等订阅插件认证及模型筛选。
- **路由与调度**：支持多渠道顺序故障回退、轮询、最低延迟路由组，以及模型别名映射与在线流式测试台。
- **后台保活与观测**：支持 Android 前台服务 / CPU 唤醒锁 / WLAN 性能锁、iOS 后台保活与请求耗时、Token 及估算费用统计。

## 仓库结构

- `lib/` — Flutter 客户端源码与中英文多语言资源（`lib/l10n/`）
- `core/` — Go 核心网关与插件托管服务（`github.com/falcon-gateway/falcon/core`）
- `android/`、`ios/`、`macos/` — 各平台原生工程与后台保活桥接代码
- `tooling/` — 工具链环境与构建脚本（`env-toolchain.sh`、`build-core.sh`、`build-apk.sh`、`build-ios.sh`）

## 本地开发与构建

```bash
source tooling/env-toolchain.sh
flutter pub get
flutter gen-l10n
go -C core test ./...
flutter test
./tooling/build-apk.sh --release
./tooling/build-ios.sh
```
