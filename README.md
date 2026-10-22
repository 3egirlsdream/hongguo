# 红果鉴

> ⚠️ **免责声明**：本项目源码来自网上大名鼎鼎的**鱼佬**（原作者）。我只是把它拿来打包、测试着玩，方便自己用，**不保证任何可用性，随时可能删库**。

Flutter 多端独立红果短剧应用，原名「短剧库 APP」。请求、解析、下载和播放均在设备上完成，不依赖自建服务。当前源码版本：**0.2.72+79**（开发快照，尚未集中验收）。

已在上游 `main`（`0e60928`）基础上合入 [PR #12](https://github.com/zhoufuweigg/guoapp/pull/12)（`4955f16`），修复其中残留的源码合并冲突，保留红果签名、播放模型兼容、流媒体识别和界面调整。

底部导航为「首页 / 搜索 / 我的」。首页移除顶部分类栏，直接展示官方推荐流，支持下拉刷新、接近底部自动续页和失败重试；搜索独立成页，保留官方联想、最近搜索、排序筛选与批量下载。「我的」参照提供的官方 App 截图组织为账号头部、快捷卡片、内嵌片单标签与三列海报，提供历史全部 / 已看完 / 未看完筛选、片单搜索与编辑入口；设置、设备互联、内容管理等移入右上角菜单。账号资料、封面和片单使用实际数据，未接入的商城、游戏、关注和粉丝模块不展示。

本轮 `0.2.72+79` 修复上一包图标字体缺失：保留 `uses-material-design: true`，按原锁文件离线重新生成依赖配置，使用 `--no-tree-shake-icons` 打包完整 Material 图标字体；导出脚本强制校验字体文件和 FontManifest 注册，避免遗漏字体的 APK 被交付。预约和上新预约改为直接复用历史页的筛选 / 编辑栏、三列海报、标题与副标题、搜索和下拉刷新，使用相同的嵌套滚动；待上线 / 已上线使用同款橙色选中标签，上新预约可按全部 / 已预约 / 未预约筛选。未上线卡片点击或长按可预约 / 取消，已上线卡片点击播放、长按管理。播放页取消官方进度排队失败的常驻横幅，继续保存本机进度并重试，失败信息仅记入播放日记；本机存储失败保留一次短暂提示。播放器空白处单击显示 / 隐藏控件，暂停和缓冲时也可手动隐藏，双击仍播放 / 暂停；手机底栏增加带文字的全屏 / 退出按钮，窄屏工具栏可换行。

本轮四个变更页面格式整理和静态分析通过（无错误、无警告，保留 13 条既有风格 info），Python 导出脚本语法检查通过。Android arm64 release APK 为 `hongguojian-0.2.72+79-arm64-v8a.apk`，30,292,642 字节（28.89 MiB），versionCode 2079。已确认包内 Material 字体为 SDK 完整版本（1,645,184 字节）、FontManifest 注册正确、原生播放核心对应当前编译输出，并通过 APK v2 签名、ZIP CRC、ZIP 对齐和 17 个原生库的 16KB ELF 对齐检查。沿用本机 debug 预览签名。APK SHA-256：`1a6407086c2b284ad46292f58f5a5c3e9eeba6afe2e7b405dd9fbf6984fdaa2d`。本轮未运行自动化测试、回归或真机交互验证，页面和播放器操作仍待真机确认。

此前 `0.2.70+77` 按第二张参考图调整「我的」页面：顶部工具栏高 44，头像直径 62，昵称改为 20 号中等字重，红果号及复制按钮合并为一行；统计字号与间距收紧，账号按钮缩小，快捷入口改为宽 80、最小高 56 的紧凑卡片。上半区使用浅色柔和背景，片单区为圆角白底；标签改为黑色选中、灰色未选中并取消下划线，片单搜索移到标签右侧，移除内嵌片单重复的状态 / 同步行。「全部 / 已看完 / 未看完」筛选与「筛选 / 编辑」置于同一行，三列海报间距缩为 8。保留真实账号及现有功能，未复制尚未接入的商城、粉丝等业务。以上为已实现布局，尚未进行 Android 真机视觉比对。

此前 `0.2.69+76` 修复页签状态和登录状态刷新：首页、搜索与「我的」使用保留组件的独立页签，切换时保留推荐列表、搜索词、搜索结果及滚动位置；搜索空白页只展示搜索入口和最近搜索，不再读取默认目录。官方推荐请求默认 10 条，首页首屏和每次续页最多新增 10 条；接口多返回的内容保留至下一批展示，隐藏页签停止自动续页。返回改用保持原始尺寸的横移 / 淡入转场，取消预测返回中的缩小效果。待上线、已上线及上新预约改为大海报卡片，底部展示剧名、接口提供的上线时间及预约操作；接口未提供时间时显示待公布。发送上行短信后恢复应用会自动检查验证结果，登录状态通过共享通知立即更新账号页、「我的」页头及片单，并避免旧状态请求覆盖登录成功结果。以上交互尚待 Android 真机确认。

此前 `0.2.71+78` 修复 HTTP 200 空响应导致的播放失败：App 优先使用 `/novel/player/multi_video_model/v1/`、1004 分集映射与 video_platform=1024，复用现有 Medusa / Helios / Gorgon 签名，保留旧单集接口与扩展签名回退；支持官方 `fallback_api`、key_seed 加密地址、平铺媒体参数及备用 URL 列表。官网兼容 `publicVideoSeo` 与 JSON-LD VideoObject，核对当前剧集、分集及 canonical 地址，避免读取推荐视频。在线播放、预加载、设备接力及新建下载任务携带本地用户标识，只为对应账号的 App 播放请求附加设备、Cookie 与 Token；官方片源 GET 和媒体请求不携带账号凭证，播放 POST 禁止重定向。既有备用入口补齐直接媒体 URL 响应兼容。协议结构对照 [hongguo-drama 的播放实现](https://github.com/jackotom/hongguo-drama/blob/41287cfc2effa8c0659c021e8b4bcaa9c74c4e9e/src/native/app-source.js) 与 [官网解析](https://github.com/jackotom/hongguo-drama/blob/41287cfc2effa8c0659c021e8b4bcaa9c74c4e9e/src/native/hongguo.js)。

此前按用户要求，于 2026-10-22 使用项目 Go 核心进行真实 API 探测：剧集 `7694653385668037657` 的前两集均由新批量 App 接口返回 HTTP 200 非空模型、1080P 媒体和 AES-128 内容密钥，两条媒体 HEAD 均返回 HTTP 200 / video/mp4；第一集官网公开直链 HEAD 也返回 HTTP 200，第二集未提供公开网页播放地址。既有备用接口两集均无有效媒体。这些请求使用临时访客身份，没有读取真实账号、下载视频或请求图片。定向播放解析检查及现有签名协议向量、画质选择、备用地址兼容检查通过；Go 核心 Windows 主机与 Android arm64 编译通过，Dart 桥接文件静态分析无错误、无警告，保留 2 条既有风格 info。真实账号授权、媒体解密播放及 Android / Windows 真机表现尚未验证，该版已生成包含播放修复的 Android arm64 release 预览包 `hongguojian-0.2.71+78-arm64-v8a.apk`，29,222,497 字节（27.87 MiB），versionCode 为 2078。使用 Flutter 3.47.4 / Dart 3.13.3 与 NDK 28.2.13676358 重新编译 Go 原生核心和应用；依赖按原锁文件离线固定，锁文件保持不变。已核对包内核心与该版编译输出一致，并通过 APK v2 签名、ZIP CRC 完整性、ZIP 对齐及全部 17 个原生库的 16KB ELF 对齐检查。使用与 0.2.70 相同的本机 debug 签名，未在真机安装验收。APK SHA-256：`266254a1d775d0052b67858a72c5737f1d9d6bf1b84e7cf156975d7c8a404ebe`。

追剧、历史、预约、上新预约在打开页面及切换标签时自动请求最新数据；恢复前台、从播放页或账号页返回时刷新当前片单。历史页先同步官方历史及当前账号的进度队列，再合并显示本机记录，失败保留已有记录并提示。账号网络操作串行，避免后台定时同步与打开页面相互抢占。

此前 `0.2.70+77` 已使用 Flutter 3.47.4 / Dart 3.13.3 完成 Android arm64 release 构建，执行当时三个页面文件格式整理和静态分析（无错误、无警告，保留 5 条既有代码风格 info）；Go 核心沿用前版构建。生成的 `hongguojian-0.2.70+77-arm64-v8a.apk` 为 29,755,874 字节（约 28.4 MiB），APK versionCode 为 2077；已通过 APK v2 签名、ZIP 完整性、ZIP 对齐及 17 个原生库的 16KB ELF 对齐检查。当前机器未配置正式发布密钥，使用与前版相同的本机 debug 签名生成预览包。按仓库约定未运行自动化测试、回归或真机验证；页面视觉效果、播放和真实账号操作仍待 Android 真机验收。

已清理来源切换、来源分组与多入口聚合、逐来源用户权限和按来源保存选项；内容维护改为单一「内容管理」页面，保留缓存更新、资料补齐及连接诊断。旧版剧目 ID、应用标识、数据目录和备份字段保持兼容，已有观看历史、追剧、用户 PIN 与下载文件不清空。旧来源记录仅作为存档保留，不能请求或播放。

追剧与账号收藏、观看历史、待上线预约和上新预约集中在「我的」内嵌片单；详情预约等入口仍可打开独立片单页。本机和当前账号历史按剧目去重并取更新时间较新的进度，点击即可续播；切换账号会清除上一账号的页面数据。本机想看 / 在看 / 已看状态继续保留；详情、播放器和卡片菜单的追剧操作统一提交账号收藏，回查云端确认后再更新本机记录。未登录时只管理本机追剧，登录前的记录不会自动批量上传。

> 以下为此前 **0.2.67+74** 的构建记录，不能代表本轮版本已经验证：按 `AGENTS.md` 暂停测试与回归的约定，未执行自动化测试。此前执行了 Go 核心主机构建与 Android arm64 核心编译、Go 测试代码编译（未执行）、Flutter 静态分析（含现有测试源码，未执行测试；无编译错误，保留既有 lint 提示）、Dart 格式整理、Python 语法检查和源码同步检查。已修复合并遗留的旧播放器引用，继续使用现有 media_kit 播放路径。已生成 Android arm64 release APK，并通过 APK v2 签名、ZIP 完整性、ZIP 对齐与 17 个原生库的 16KB ELF 对齐检查。未发送真实验证码，未验证真实账号登录、账号收藏同步、跨设备历史同步和官方预约效果；这些功能及界面效果仍待真机验证。

## 使用

| 功能 | 操作 |
| --- | --- |
| 浏览 | 首页直接浏览官方推荐流，下拉刷新、自动续页；搜索使用独立底部标签，榜单和批量下载等保留在「我的 → 右上角菜单」。搜索页支持默认、名称、自然季号、上线日期、热度、播放量排序及连载状态筛选。列表下滑接近底部自动加载下一页，底部「加载更多」为兜底 |
| 搜索 | 独立保留搜索词、结果和滚动位置，空白页不加载首页内容。红果合并官网与名称索引，输入停顿 300 毫秒显示最多 10 条联想。部分失败保留有效结果；最近 20 次搜索按用户保存 |
| 推荐 | 首页使用官方 `/reading/bookapi/bookmall/cell/change/v` 推荐接口，保持服务端顺序、分页位置与去重；默认每批展示 10 条，切换页签保留列表与滚动位置；刷新开始新一轮推荐，失败保留已有列表 |
| 详情 | 普通点剧直接进入播放；下载和兜底入口保留详情页。详情页浏览封面、资料、追剧状态与可展开简介；底部固定「立即播放 / 继续播放」和下载入口。选集默认折叠，展开后每组 50 集，可切换范围、定位当前或输入集数跳转；宽屏与电视采用资料、选集分栏 |
| 追剧与历史 | 按想看 / 在看 / 已看 / 有更新筛选；红果已追剧发现新季后进入「有更新」。追剧和历史均可搜索。每个用户独立保存，每 5 秒及退出播放时记录真实进度 |
| 账号 | 「我的 → 登录账号 / 账号卡片」，支持中国大陆 +86 手机号验证码登录；若需要上行短信验证，显示本次号码和内容并检查验证结果 |
| 历史 | 「我的 → 历史」内嵌标签，打开时自动拉取最新官方历史，合并本机记录并续播；可同步云端进度，账号与同步页可手动上传登录前的本机历史。清空和删除本机历史不会删除云端记录 |
| 预约 | 「我的 → 预约 / 上新预约」查看、预约或取消预约；账号收藏合并到追剧页，预约仍可查看待上线 / 已上线内容。详情页「预约」可操作当前剧集 |
| 卡片与批量下载 | 卡片「更多」提供收藏、状态和下载选集；电脑右键，电视菜单键。搜索页长按卡片或点「我的 → 右上角菜单 → 批量下载」，一次最多 50 部 |
| 手机播放 | 上滑下一集、下滑上一集；长按 350 毫秒临时 3 倍速。点击播放器空白处显示 / 隐藏控件，双击播放 / 暂停；底栏「全屏」可进入 / 退出全屏。视频下方为「选集 / 简介 / 下载」Tab |
| 画中画 | Android 手机 / 平板播放器接入画中画按钮；进入前隐藏自绘控制层与弹幕，小窗只保留画面。Android TV、Windows、iOS 暂未接入 |
| 画质增强 | 仅 Windows 桌面端显示并运行增强链路（关闭 / 自动 / 省电增强 / 清晰优先）；移动端与电视端隐藏 |
| 弹幕 | 红果在线播放默认开启；播放器侧边圆形「弹」字按钮可关闭、查看状态及失败重试。本地播放不加载弹幕 |
| 下载 | 播放页「下载」Tab 和详情页下载入口均可选择分集与画质；支持批量暂停、继续、重试、删除及清理任务但保留视频。「更新本剧」补新增或缺失分集 |
| 我的 | 片单直接内嵌展示，下载由快捷卡片进入；内容管理、设备互联、本地用户、设置与备份、界面模式、关于集中于右上角菜单 |

红果提供真人剧、漫剧、AI 剧及分集，支持联网搜索与官网搜索联想。可用性、清晰度和区域限制取决于红果及网络；应用不解除源站 VIP 或其他授权限制。

### 账号与片单（已接入，待真实账号验证）

官方账号与当前本地用户绑定。手机号登录使用独立、持久化的设备注册与账号会话，通过红果接口发送验证码；支持取消、超时、退出与上行短信验证。图形验证等未接入的风控流程会提示失败，需要在官方 App 完成后重试，不会将匿名设备身份当作登录成功。

登录后立即同步，应用运行且当前本地用户已解锁时每 90 秒尝试同步历史与账号收藏。在线播放的进度先保存到当前官方账号的本机队列，拉取官方历史后按更新时间合并，再上传进度；请求失败保留队列供重试。账号历史与本机记录合并显示在「我的 → 历史」，可点击续播。登录前的本机历史仅在点击「上传本机历史」并确认后加入当前账号队列；删除本机记录不会删除云端记录。退出保留该账号历史与待上传队列，重新登录同一账号后继续；切换账号不会把上一账号的队列发给新账号。

打开「我的」和切换片单标签会自动拉取当前账号的数据，恢复前台及返回播放后刷新当前列表；历史页先联网同步，再读取本机账号缓存。请求失败保留已有记录并显示失败原因。「追剧」合并本机追剧与账号收藏，「预约」可切换待上线与已上线内容，「上新预约」支持分页。本机旧追剧不会在登录时批量上传；登录后新增、取消追剧及标记状态会先更新账号收藏，回查云端确认后保存本机变更。失败时提示重试，不显示已同步。想看 / 在看 / 已看状态保存在本机；账号收藏、预约和历史通过各自接口读取，使用同一登录会话。预约和取消请求提交后重新读取官方列表确认，只有确认后显示成功；超时或未确认时提示用户刷新，不假定操作已生效。

会话文件保存在应用支持目录的 `hongguo-accounts/<本地用户>/session.json`，历史与队列按官方 UID 分目录保存。令牌和 Cookie 仅存于设备文件，未使用系统钥匙串加密，不进入普通应用备份或局域网同步；短信验证码仅驻留内存，退出会清除账号凭证。账号请求使用现有代理配置、TLS 校验与超时，不记录登录凭证。

官方推荐入口与播放网页兼容参考公开的 [hongguo-tv 推荐实现](https://github.com/aston314/hongguo-tv/blob/main/core/cmd/hongguotv/lists.go) 与 [hongguo-dl 播放实现](https://github.com/gybeyond1/hongguo-dl/blob/main/docker/hongguo_core.py)，独立适配到现有请求、分页和权限模型；这些项目提供的协议说明均非官方开放 API 文档。

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
| Android 8.0+ | 本轮已生成 `hongguojian-0.2.72+79-arm64-v8a.apk`（28.89 MiB，APK versionCode 2079），使用本机 debug 签名，安装包完整性与对齐检查通过，待真机验证；构建脚本还支持 armeabi-v7a / x86_64，本轮未构建 |
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

播放 API 可显式单独探测（默认跳过，不随普通测试访问网络；仅请求接口及媒体 HEAD）：

~~~powershell
cd native
$env:HONGGUO_API_PROBE = "1"
go test ./core -run "^TestHongguoAPILiveProbe$" -count=1 -v
Remove-Item Env:HONGGUO_API_PROBE
~~~

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
