# 红果鉴

> ⚠️ **免责声明**：本项目源码来自网上大名鼎鼎的**鱼佬**（原作者）。我只是把它拿来打包、测试着玩，方便自己用，**不保证任何可用性，随时可能删库**。

Flutter 多端独立红果短剧应用，原名「短剧库 APP」。请求、解析、下载和播放均在设备上完成，不依赖自建服务。当前源码版本：**0.2.67+74**（开发快照，尚未集中验收）。

已在上游 `main`（`0e60928`）基础上合入 [PR #12](https://github.com/zhoufuweigg/guoapp/pull/12)（`4955f16`），修复其中残留的源码合并冲突，保留红果签名、播放模型兼容、流媒体识别和界面调整。

底部导航收敛为「发现 / 我的」，首页移除整条顶部工具栏，分类栏直接使用内容区顶部。「我的」集中提供追剧、预约、历史、下载，以及搜索、排序筛选、榜单、批量下载、内容更新、设备互联、用户、设置、界面模式与关于。

已清理来源切换、来源分组与多入口聚合、逐来源用户权限和按来源保存选项；内容维护改为单一「内容管理」页面，保留缓存更新、资料补齐及连接诊断。旧版剧目 ID、应用标识、数据目录和备份字段保持兼容，已有观看历史、追剧、用户 PIN 与下载文件不清空。旧来源记录仅作为存档保留，不能请求或播放。

追剧与账号收藏、观看历史、待上线预约和上新预约集中在「我的片单」二级页。本机和当前账号历史按剧目去重并取更新时间较新的进度，点击即可续播；切换账号会清除上一账号的页面数据。本机想看 / 在看 / 已看状态继续保留；详情、播放器和卡片菜单的追剧操作统一提交账号收藏，回查云端确认后再更新本机记录。未登录时只管理本机追剧，登录前的记录不会自动批量上传。

> 按 `AGENTS.md` 暂停测试与回归的约定，未执行自动化测试。本轮执行了 Go 核心主机构建与 Android arm64 核心编译、Go 测试代码编译（未执行）、Flutter 静态分析（含现有测试源码，未执行测试；无编译错误，保留既有 lint 提示）、Dart 格式整理、Python 语法检查和源码同步检查。已修复合并遗留的旧播放器引用，继续使用现有 media_kit 播放路径。已生成 Android arm64 release APK，并通过 APK v2 签名、ZIP 完整性、ZIP 对齐与 17 个原生库的 16KB ELF 对齐检查。未发送真实验证码，未验证真实账号登录、账号收藏同步、跨设备历史同步和官方预约效果；这些功能及界面效果仍待真机验证。

## 使用

| 功能 | 操作 |
| --- | --- |
| 浏览 | 排序与筛选、榜单、批量下载和搜索集中在「我的 → 浏览工具」。首页没有顶部工具栏，分类保持独立一行，内容区左右滑动切类；支持默认、名称、自然季号、上线日期、热度、播放量排序及连载状态筛选。列表下滑接近底部自动加载下一页，底部「加载更多」为兜底 |
| 搜索 | 红果合并官网与名称索引，输入停顿 300 毫秒显示最多 10 条联想。部分失败保留有效结果；最近 20 次搜索按用户保存 |
| 推荐 | 仅红果分类栏在「全部」后显示「推荐」，可切换真人剧、漫剧、AI 剧并分别记住位置 |
| 详情 | 普通点剧直接进入播放；下载和兜底入口保留详情页。详情页浏览封面、资料、追剧状态与可展开简介；底部固定「立即播放 / 继续播放」和下载入口。选集默认折叠，展开后每组 50 集，可切换范围、定位当前或输入集数跳转；宽屏与电视采用资料、选集分栏 |
| 追剧与历史 | 按想看 / 在看 / 已看 / 有更新筛选；红果已追剧发现新季后进入「有更新」。追剧和历史均可搜索。每个用户独立保存，每 5 秒及退出播放时记录真实进度 |
| 账号 | 「我的 → 登录账号 / 账号卡片」，支持中国大陆 +86 手机号验证码登录；若需要上行短信验证，显示本次号码和内容并检查验证结果 |
| 历史 | 「我的 → 历史」，合并显示本机与账号记录并续播；可同步云端进度，账号与同步页可手动上传登录前的本机历史。清空和删除本机历史不会删除云端记录 |
| 预约 | 「我的 → 预约 / 我的片单 → 上新预约」查看、预约或取消预约；账号收藏合并到追剧页，预约仍可查看待上线 / 已上线内容。详情页「预约」可操作当前剧集 |
| 卡片与批量下载 | 卡片「更多」提供收藏、状态和下载选集；电脑右键，电视菜单键。发现页长按卡片或点「我的 → 批量下载」，一次最多 50 部 |
| 手机播放 | 上滑下一集、下滑上一集；长按 350 毫秒临时 3 倍速。竖屏轻点播放 / 暂停，横屏轻点控制条，双击播放 / 暂停。视频下方为「选集 / 简介 / 下载」Tab |
| 画中画 | Android 手机 / 平板播放器接入画中画按钮；进入前隐藏自绘控制层与弹幕，小窗只保留画面。Android TV、Windows、iOS 暂未接入 |
| 画质增强 | 仅 Windows 桌面端显示并运行增强链路（关闭 / 自动 / 省电增强 / 清晰优先）；移动端与电视端隐藏 |
| 弹幕 | 红果在线播放默认开启；播放器侧边圆形「弹」字按钮可关闭、查看状态及失败重试。本地播放不加载弹幕 |
| 下载 | 播放页「下载」Tab 和详情页下载入口均可选择分集与画质；支持批量暂停、继续、重试、删除及清理任务但保留视频。「更新本剧」补新增或缺失分集 |
| 我的 | 下载和片单均为二级页；浏览工具、内容管理、设备互联、本地用户、设置与备份、界面模式、关于集中展示 |

红果提供真人剧、漫剧、AI 剧及分集，支持联网搜索与官网搜索联想。可用性、清晰度和区域限制取决于红果及网络；应用不解除源站 VIP 或其他授权限制。

### 账号与片单（已接入，待真实账号验证）

官方账号与当前本地用户绑定。手机号登录使用独立、持久化的设备注册与账号会话，通过红果接口发送验证码；支持取消、超时、退出与上行短信验证。图形验证等未接入的风控流程会提示失败，需要在官方 App 完成后重试，不会将匿名设备身份当作登录成功。

登录后立即同步，应用运行且当前本地用户已解锁时每 90 秒尝试同步历史与账号收藏。在线播放的进度先保存到当前官方账号的本机队列，拉取官方历史后按更新时间合并，再上传进度；请求失败保留队列供重试。账号历史与本机记录合并显示在「我的 → 历史」，可点击续播。登录前的本机历史仅在点击「上传本机历史」并确认后加入当前账号队列；删除本机记录不会删除云端记录。退出保留该账号历史与待上传队列，重新登录同一账号后继续；切换账号不会把上一账号的队列发给新账号。

「追剧」合并本机追剧与账号收藏，「预约」可切换待上线与已上线内容，「上新预约」支持分页。本机旧追剧不会在登录时批量上传；登录后新增、取消追剧及标记状态会先更新账号收藏，回查云端确认后保存本机变更。失败时提示重试，不显示已同步。想看 / 在看 / 已看状态保存在本机；账号收藏、预约和历史通过各自接口读取，使用同一登录会话。预约和取消请求提交后重新读取官方列表确认，只有确认后显示成功；超时或未确认时提示用户刷新，不假定操作已生效。

会话文件保存在应用支持目录的 `hongguo-accounts/<本地用户>/session.json`，历史与队列按官方 UID 分目录保存。令牌和 Cookie 仅存于设备文件，未使用系统钥匙串加密，不进入普通应用备份或局域网同步；短信验证码仅驻留内存，退出会清除账号凭证。账号请求使用现有代理配置、TLS 校验与超时，不记录登录凭证。

接口字段、签名和设备注册流程依据公开的 [hongguo-tv 账号同步实现说明](https://github.com/aston314/hongguo-tv/blob/b7074a86a8c836722b86b929b0df807548754eb3/docs/account-sync.md) 及其同版本实现独立接入，复用本项目 SM3；该资料不是官方开放 API 文档，服务端协议或风控变更可能导致失败。协议向量、会话隔离、取消和持久化检查代码已补充，目前仅编译，未执行。

### 网络与资源设置

管理员从「设置与备份 → 网络与资源」选择自动、直连或手动代理，手动地址支持 HTTP、HTTPS、SOCKS5 / SOCKS5h。代理地址默认遮蔽、不进入备份；设备内播放服务始终绕过代理。自动模式读取系统静态代理与排除列表，恢复前台及每 30 秒更新；代理不会关闭 TLS 校验。

目录请求并发可设 1–6、间隔 0–5000 毫秒（默认 3 / 250ms）；下载并发默认 2、可设 1–6。仍保留前台优先、后台让行、取消、退避及请求数量边界。

### 局域网互联：追剧同步与推送播放（已接入，待验证）

两台设备在同一局域网直连，自动同步追剧记录或接续播放，不依赖账号服务器。服务类型 `_zgj-link._tcp`（DNS-SD / mDNS），按设备 ID 合并多网卡地址，首次配对记录证书指纹，后续连接固定校验。

入口：「我的 → 设备互联」或「设置与备份 → 设备互联」。手动同步默认「双向合并」，可选覆盖对方 / 覆盖本机，先「查看预览」再执行；自动同步仅发送改动条目与删除标记，播放期间约每 10 秒发送进度。冲突记录保留候选，用户从同步页逐项处理。

## 安装包与平台状态

| 平台 | 包与状态 |
| --- | --- |
| Android 8.0+ | 本轮已生成 `hongguojian-0.2.67+74-arm64-v8a.apk`（29.4 MB，APK versionCode 2074），使用已有签名配置，待真机验证；构建脚本还支持 armeabi-v7a / x86_64，本轮未构建 |
| Windows 10/11 x64 | 完整 ZIP 解压后运行 `hongguojian.exe`，保留所有 DLL 与 `data`；局域网原生发现依赖 Windows 10 1903+ |
| Android TV | 与手机共用源码，自动识别电视模式并保持横屏；待电视 / 盒子实机验收 |
| iOS 15.1+ | 已加入工程、Go 核心链接、媒体依赖、文件管理与构建脚本；iOS 播放页禁用 media_kit_video 硬件纹理加速以规避 libmpv 渲染崩溃；待 Xcode 构建与真机验收，无已签名 IPA |

`INSTALL_FAILED_NO_MATCHING_ABIS` 表示 APK 与设备架构不匹配，请更换对应架构安装包。

### GitHub Actions

推送 `main` / `master`、`v*` 标签、提交 PR，或手动运行 **Build app packages**，使用红果单一构建配置。当前工作流仅启用 Android 打包；Windows 与 iOS 任务保持仓库原有禁用状态。检查任务与 Android 构建独立执行：

| 产物 | 内容 |
| --- | --- |
| `*-android` | 三种架构 APK 和 SHA256 |
| `*-windows` | 完整 ZIP 和 SHA256 |
| `*-ios-unsigned` | 未签名 `.app` ZIP 和 SHA256，不能直接当已签名 IPA 安装 |

Android 构建成功时，自动创建 / 更新 GitHub Release（tag `app-v{version}`）。发布新版本前需先在 `pubspec.yaml` 提升 `version`，否则会覆盖同名 tag 的 Release。

Android 正式发布使用同一签名并递增构建号，在仓库 Secrets 配置：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。未配置时生成 debug 签名预览包。

本地不入库的 `android/key.properties`：

~~~properties
storeFile=/absolute/path/zhenguojian-release.jks
storePassword=你的密码
keyAlias=zhenguojian
keyPassword=你的密码
~~~

## 开发与构建

Flutter `3.47.4`、Dart `3.13+`、Go `1.24.1+`、Python `3.10+`。Android 需要 JDK 17、SDK 36、NDK 默认 `28.2.13676358`；Windows 需要 Visual Studio C++ 桌面组件及 MinGW-w64 x64；iOS 需要 macOS、完整 Xcode 和 CocoaPods。

构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，同名环境变量可覆盖。

复用已有 Android SDK 时将 `ANDROID_HOME` 指向其目录。可用 `ANDROID_NDK_VERSION` 和 `ANDROID_NDK_HOME` 指定已安装的其他 NDK（主程序、插件与 Go 核心保持一致），无需替换默认发布配置；本次 Android arm64 测试包使用现有 NDK `26.1.10909125`。

~~~sh
python3 scripts/build_android.py                 # 红果鉴
python3 scripts/build_android.py --abi arm64-v8a
python3 scripts/build_android.py --cn-mirrors    # 国内镜像
~~~

~~~powershell
.\scripts\build_windows.ps1
.\scripts\build_windows.ps1 -ChinaMirrors
~~~

~~~sh
python3 scripts/build_ios.py
python3 scripts/build_ios.py --core-only [--simulator]
python3 scripts/build_ios.py --export-options /path/to/ExportOptions.plist
~~~

本地构建产物位于 `dist/android`、`dist/windows`、`dist/ios`，均以 `hongguojian-` 开头。

首次 Android 调试先编译对应架构核心，再运行：

~~~sh
python3 scripts/build_native.py --platform android --abi arm64-v8a
flutter pub get --enforce-lockfile
flutter run
~~~

播放器使用 [media_kit](https://github.com/media-kit/media-kit) / libmpv，合并和导出使用 [FFmpegKit min-gpl](https://github.com/sk3llo/ffmpeg_kit_flutter)（含 GPL 媒体组件）。FFmpegKit 不参与正常播放或下载的转码。

### 集中检查与真机回归

~~~sh
python3 -m unittest discover -s scripts -p 'test_*.py'
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
dart analyze --fatal-infos lib test integration_test test_driver
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
cd native
go test -race ./...
~~~

Android 设备回归（连接并授权 USB 调试、保持解锁）：

~~~sh
python3 scripts/create_test_media.py
python3 scripts/serve_test_media.py
adb reverse tcp:38473 tcp:38473
flutter drive --driver=test_driver/playback.dart --target=integration_test/playback_test.dart \
  --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=FIXTURE_BASE_URL=http://127.0.0.1:38473
~~~

结果在 `build/device-test/results/`；结束后停服务并 `adb reverse --remove tcp:38473`。

### 源码同步

~~~sh
python3 scripts/finish_task.py --message "本次实际完成的变更"
python3 scripts/sync_source.py --check
~~~

脚本只同步纯源码到同级 `../guoapp`，并生成 `真果·鉴-YYYYMMDDHHMM.zip` 源码压缩包；不执行 Git 提交、分支或推送。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `lib` | 页面、播放器、本地用户、FFI、下载和媒体处理 |
| `native/core`、`native/bridge` | 内容核心、缓存、下载、目录迁移及 C ABI |
| `android`、`windows`、`ios` | 平台工程与必要资源 |
| `assets/video_enhancement`、`packages/media_kit_libs_windows_video` | 增强 Shader 与许可、固定 Windows 媒体依赖插件 |
| `scripts`、`.github/workflows` | 构建、签名、验证、同步和版本快照 |
| `test`、`integration_test` | 自动化与设备回归 |

## 内容接口开发约定

红果播放接口位于 `native/core/provider_hongguo*.go`，官方账号、历史与预约位于 `native/core/hongguo_account*.go`；通用数据辅助函数位于 `provider_common.go`。浏览器和内容更新器均按单一内容库请求；保留 `hongguo` 作为存档与协议中的内部标识，初始化时校验原生核心配置。

注意：Go RE2 正则**不支持 lookahead**。解析多线路播放列表时不能用 `(?=...)` 做分段，否则非捕获组会消耗下一段开头；应改用显式字符串截断（从容器标记之后查找下一段标记）。
