# 野果

> ⚠️ **免责声明**：本项目源码来自网上大名鼎鼎的**鱼佬**（原作者）。我只是把它拿来打包、测试着玩，方便自己用，**不保证任何可用性，随时可能删库**。

Flutter 多端独立红果短剧应用，现名「野果」，原名「红果鉴 / 短剧库 APP」。请求、解析、下载和播放均在设备上完成；版本检查单独查询更新后台。当前源码版本：**0.2.79+86**（开发快照，尚未集中验收）。

已在上游 `main`（`0e60928`）基础上合入 [PR #12](https://github.com/zhoufuweigg/guoapp/pull/12)（`4955f16`），修复其中残留的源码合并冲突，保留红果签名、播放模型兼容、流媒体识别和界面调整。

底部导航为「首页 / 排行榜 / 搜索 / 我的」。排行榜提升为一级页签，切换保留榜单分类、数据与滚动位置；手机底栏、电脑与电视导航同步提供入口。首页移除顶部分类栏，直接展示官方推荐流，支持下拉刷新、接近底部自动续页和失败重试；搜索独立成页，保留官方联想、最近搜索、排序筛选与批量下载。「我的」参照提供的官方 App 截图组织为账号头部、快捷卡片、内嵌片单标签与三列海报，提供历史全部 / 已看完 / 未看完筛选、片单搜索与编辑入口；设置、设备互联、内容管理等移入右上角菜单。账号资料、封面和片单使用实际数据，未接入的商城、游戏、关注和粉丝模块不展示。

本轮 `0.2.79+86` 接入自动发布和应用内更新，仍为开发快照：

- GitHub Actions 在 `main` / `master` 的 `pubspec.yaml` 变化时检测版本；功能版本和构建号同时高于已公开 Release 才构建。只生成 Android `arm64-v8a` APK，不构建其他架构、Windows 或 iOS；同版本跳过，不覆盖已公开附件。
- 使用本机 `Watermark.Release.keystore` 的 `temp` 发布证书，四项 Android 签名 Secrets 已配置到 `3egirlsdream/hongguo`。Actions 缺少签名或 APK 证书与指定 SHA-256 不符时直接失败。Flutter arm64 分包自动将 Android versionCode 设为 `2000 + pubspec 构建号`，Gradle 不再额外重复加偏移，避免旧包 `2084` 等构建号阻止覆盖升级；本版预期为 `2086`。打包脚本额外检查 APK 内部应用标识、版本和架构，避免旧构建产物被重命名为新版本；Actions 显式统一原生核心与 Flutter 插件的 NDK 版本和路径。
- 打包与证书核对成功后，先上传完整附件到草稿 Release，确认文件齐全后再公开为 latest。附件包含 APK、`update.json` 和 `SHA256SUMS.txt`；成功后按 Mac Explorer 同一后台协议写入独立 `Client=Yeguo`，保存完整版本、清单地址和更新说明，并独立回读确认。
- 「设置与备份 → 关于野果」增加开发者主页、当前源码仓库、始终指向最新 Release 的下载地址与检查更新。Android arm64 可点击「下载并安装更新」，显示进度、取消和失败重试；完整下载并核对大小 / SHA-256 后自动打开系统安装流程。首次需在系统设置允许安装此来源的应用，返回后继续安装。安装前还核对应用标识、正式证书与更高的构建号。下载任务在关于页退出后仍可继续，进程退出后需重新下载。
- 其他平台与架构本轮不发布更新包；iOS / Windows 关于页支持查看当前版本及打开仓库链接，不提供本轮自动安装包。Android TV 仅 arm64 设备有对应包，安装权限及遥控交互待实机确认。
- 本轮完成 3 个相关 Dart 文件的格式整理与定向静态分析（无问题）、Python / XML / 工作流 YAML 语法检查和源码差异空白检查，并执行收尾同步；自动化测试与设备回归继续暂停。2026-10-23 按用户要求提交当前源码到主分支，执行 Android arm64 的本地构建及 Actions 发布，并独立确认 Release 附件和后台版本；最终结果待本轮发布完成后补录。后台 `Yeguo` 在首个成功的 Release 后自动创建，安装升级仍待真机验收。

此前 `0.2.78+85` 优化点击后的取流等待并增加耗时日志，仍为待真机确认的开发快照：

- 在线取流顺序调整为 App 批量接口 → App 单集接口 → 官网 → 兼容网页域名 → 备用 API，成功即返回。App 批量 / 单集预算分别为 6 / 4 秒，App 总预算 10 秒；网页各 2 秒、备用 3 秒，取流阶段预算由此前约 53 秒缩短到约 17 秒，正常 resolve 请求总预算 20 秒。官网优先于会重定向到官网的兼容域名。播放请求签名重试间隔由 1 秒缩短到 150 毫秒，继续遵守管理员配置的最小请求间隔与源站退避；其他目录请求保留原重试间隔。
- 点击后的详情优先沿用已注册设备的官方接口，缓存有效时直接复用；App 详情预算 6 秒、网页兜底 3 秒，详情请求总预算 12 秒。资料保存与打开播放页并行，保留存储失败提示。下一集预加载继续沿用 15 秒总预算，优先执行 App 取流，避免先被网页消耗预算。自动画质及清晰度排序保持不变。
- 播放日记增加 `[PlayTiming]`，同次点击的详情、资料保存、播放器准备、请求排队、App 分接口 / 重试、网页 / 备用回退、本地代理建立、播放器配置、open 返回、视频参数和进度起跳使用同一 trace ID，记录阶段耗时与累计毫秒。首次创建视频控制器时通过 media_kit 的首帧回调记录 `first_frame`；同一控制器后续切集仅记录视频参数与进度起跳，不把它们冒充首帧。原生核心在应用支持目录 `logs/app.log` 以 `playback_timing` 记录同一 trace ID，并补充媒体响应头与首批媒体字节耗时；这两项发生在 resolve 返回后，只进入原生日志。日志不记录媒体 URL、密钥或账号凭证。
- 2026-10-23 按用户要求使用临时访客身份直连接口，独立检查详情、注册、相关季、两种 App 取流、两个网页、备用 API 与媒体 HEAD；未读取真实账号，未下载视频或请求图片。初次探测发现进程环境代理 `127.0.0.1:7897` 拒绝连接，后续探测显式移除该环境代理，未修改应用网络设置。样本为剧集 `7694653385668037657` 的前两集，本机结果如下，不能推断所有分集、地区和登录状态均可用：

  | 入口 | 本次直连结果 |
  | --- | --- |
  | 设备注册、当前官方详情、相关季 | 均返回有效数据；注册约 257ms，官方详情含注册约 695ms，相关季含详情约 1152ms |
  | App 批量取流 | 两集均返回有效 1080P 加密媒体，约 150 / 212ms，媒体 HEAD 均为 HTTP 200 / video/mp4 |
  | App 单集取流 | 两集均返回有效 1080P 加密媒体，约 274 / 192ms，媒体 HEAD 均为 HTTP 200 / video/mp4 |
  | 官网及兼容网页域名 | 第一集公开直链可用；第二集页面 HTTP 200，但没有公开媒体地址；兼容域名会 301 跳转官网 |
  | 备用 API | 两集均 HTTP 200，但未返回有效媒体或密钥，不能算可播放 |
  | 旧访客详情 | HTTP 200 空响应，当前正常点击使用已注册设备的官方详情接口 |
  | 优化后实际核心取流及本地代理 | 两集约 163 / 206ms，均直接由 App 批量接口成功，无网页或备用回退；本地代理媒体 HEAD 均 HTTP 200 |

- 已执行 Go / Dart 格式整理、上述单独 API 探测及本轮 5 个 Dart 文件的定向静态分析（无错误、无警告，保留 17 条既有风格 info）。自动化回归、集中全量检查及设备验证仍暂停，未生成新版 APK。API 取流耗时不包含手机解码、缓冲及画面展示；Android 手机 / Windows 优先验收点击到首帧、断网与超时回退、切集、续播、预加载和日志，Android TV 遥控与 iOS 随后验证。

此前 `0.2.77+84` 更名为「野果」，重新生成清新简约图标并调整首页与导航，仍为待真机确认的开发快照：

- 软件展示名统一为「野果」，导出安装包、备份与恢复文件前缀改为 `yeguo`；保留 Android 应用 ID、iOS Bundle ID、内部 Windows 目标名、用于定位数据的 Windows 产品标识、数据目录与备份格式，已有账号、观看记录和下载不因改名迁移或清空。Android 桌面、下载通知、应用内名称、Windows 窗口与文件描述、iOS 展示名和 Android TV 横幅同步更新。
- 使用内置 imagegen 生成图标母版 `assets/branding/app_icon.png`。设计提示：浅米白底、绿色野果与单叶、果实内融入留白播放三角，清新简约、无文字、适配小尺寸。生成提示（内置工具最终输入）：

  > Use case: logo-brand. Asset type: production app launcher icon, one square 1024 x 1024 image for a Chinese short-drama video app named 野果 (Wild Fruit). Primary request: fresh, clean, minimalist, original and memorable icon. Subject: a single friendly stylized wild berry / round fruit silhouette in soft fresh botanical green, topped with one small leaf; a tiny ivory negative-space play triangle is subtly integrated into the fruit. Keep the mark bold and legible even at 48 pixels. Style: refined flat vector-like brand illustration, crisp smooth curves, restrained modern geometric forms, generous breathing room, calm lively natural feeling. Background: a solid warm ivory square, full bleed, opaque. Composition: centered single emblem; essential fruit and leaf within the central 62 percent of the square so Android circular masks retain everything; no pre-rounded square boundary. No text, letters, Chinese characters, numerals, gradients, shiny 3D, shadows, texture, photographic fruit, frames, watermarks, mockup devices, alternate icon sheets or multiple variants. Deliver one finished square icon.

  统一母版导出 Android 五档尺寸与自适应图标、Windows 多尺寸 ICO、iOS 各尺寸图标及电视横幅；自适应图标预留安全区，`scripts/generate_brand_assets.py` 可重复导出，不再生成旧版图案。
- 首页首批及刷新默认展示 10 条，每次追加最多 10 条，官方多返回的内容留待后续批次。原自动续页触发范围为距底部 600 逻辑像素，容易在轻微滚动后提前扩充；现仅在用户主动向下滚动并接近底部时续页，布局变化、元数据刷新和程序恢复滚动位置不直接触发追加。官方去重后首批不足 10 条且仍有后续时，最多补取 3 次；获取失败保留已有内容，官方实际不足时不重复填充。
- 一级页签调整为「首页 / 排行榜 / 搜索 / 我的」，保留各页状态；排行榜首次进入才加载，隐藏时不自动续页。「我的」已有榜单快捷入口改为切换对应页签，不再叠加独立榜单路由。手机、电脑和电视统一导航顺序，保留返回首页与搜索、下载批量操作。
- 本轮完成资源导出与源码格式整理，更新了既有品牌断言；自动化、集中静态分析及设备回归继续暂停。新图标、导航及推荐批次行为仍需设备验收。
- 2026-10-23 已生成 `yeguo-0.2.77+84-arm64-v8a.apk`，30,270,278 字节（28.87 MiB），versionName 为 `0.2.77`、versionCode 为 `2084`。重新编译当前 Go 核心，使用 Flutter 3.47.4 / Dart 3.13.3、NDK 26.1.10909125 与既有依赖缓存，锁文件保持一致；使用指定 `Watermark.Win` 密钥签名，与 `0.2.76` 同证书，可覆盖安装。最终 APK 名称、新版五档桌面图标、自适应图标、电视横幅已核对，解码像素与源码资源一致；保留外屏准入及连续性声明、完整 Material 图标字体。APK v2 签名、ZIP CRC 与 16KB 对齐、全部 17 个原生库的 16KB ELF 对齐检查通过，核心与本轮合并 / 去符号输出一致。APK SHA-256：`7ff9cd05bf578e87b2189cfbebd0acfa3ce146d3c958924e730f015b829ea0f2`。未执行设备交互、集中静态分析或自动化回归；Windows / iOS 本轮只更新资源和品牌配置，未构建。

此前 `0.2.76+83` 针对 MIX Flip 2 / HyperOS 3 上“小窗可播，恢复完整应用要求到内屏打开”的反馈补充外屏启动准入，仍为待实机确认的开发快照：

- 上一版声明了 Android 通用小外屏与小米连续性，但遗漏小米外屏启动策略。根据[官方 Flip 文档的外屏启动说明](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2026)与 [MixFlipTool 的实际 Manifest](https://github.com/parallelcc/MixFlipTool/blob/79e84a7427e637494a5e1e3e35b9781fcdf3ca58/app/src/main/AndroidManifest.xml)，在 application 增加 `property miui.continuity.policy=5`；主 Activity 增加 `meta-data miui.supportFlipFullScreen=1`，选择系统应用区贴边显示。通用小外屏授权同步声明在 application 和 Activity；不新增单独外屏入口，不改变内屏布局与外屏等比例缩放。
- 按 [Android 官方 PiP 单 Activity 建议](https://developer.android.com/develop/ui/views/picture-in-picture#single_playback)改为 `singleTask`，重新打开应用复用原 Activity 和 Flutter 播放状态；处理 `onNewIntent` 刷新窗口信息，不重新建立播放器。明确 `excludeFromRecents=false`，恢复完整窗口时清除当前任务 Intent 中可能遗留的排除标志，保持既有空 taskAffinity。
- PiP 仅由现有小窗按钮主动进入，取消进入一次后持续启用系统自动进入的设置，避免退出小窗后普通页面切后台又自动变成 PiP。保留播放进度和恢复逻辑。
- “小窗播放时最近任务没有卡片”不能直接判定为进程退出：[Android RecentTasks 实现](https://github.com/aosp-mirror/platform_frameworks_base/blob/android16-release/services/core/java/com/android/server/wm/RecentTasks.java)会过滤 pinned / PiP 任务，也可能过滤不允许在主设备最近任务显示的显示屏任务。此轮不通过重复创建 Activity 伪造第二张卡片；完整应用恢复后卡片能否出现在 HyperOS 外屏 / 内屏列表，仍需实机确认。
- 2026-10-23 按用户要求打包 MIX Flip 2 验证版：重新编译当前 Android arm64 Go 核心，使用 Flutter 3.47.4 / Dart 3.13.3、NDK 26.1.10909125，保留完整 Material 图标字体。`hongguojian-0.2.76+83-arm64-v8a.apk` 为 29,991,846 字节（28.60 MiB），内部 versionName 为 `0.2.76`、versionCode 为 `2083`。使用 `Watermark.Win` 的 `temp` 密钥签名，证书 SHA-256 与 `AGENTS.md` 指定值及上一版 `0.2.75` 一致，可覆盖安装。依赖按现有缓存离线恢复，锁文件内容保持一致。APK v2 签名、ZIP CRC、ZIP 16KB 对齐与全部 17 个原生库的 16KB ELF 对齐检查通过，包内核心与本轮编译合并 / 去符号输出一致，完整 Material 字体为 1,645,184 字节。已从最终 APK 核对 `miui.continuity.policy=5`、贴边模式、连续性和通用小外屏声明、`singleTask` 与最近任务保留配置。APK SHA-256：`8368e60239ed1c21b1b5225973775716d783446334abb72566c932e2a04a30ca`。本轮只执行构建与安装包交付检查，未运行自动化测试、集中静态分析或真机交互回归，仍为开发验证包。
- 本机 ADB 当前无连接设备，尚不能读取手机的系统策略及 Activity 日志。待 MIX Flip 2 / HyperOS 3 实机验收：覆盖安装新版本，内屏冷启动一次，在「设置 → 外屏 → 应用管理」添加本应用（若列表提供），合盖后从小窗恢复完整应用，再核对内屏 / 外屏最近任务与播放位置。系统仍拦截时，可在连接实机后使用官方 `adb shell wm dump -setForceDisplayCompatMode com.duanju.duanju_app/.MainActivity allowstart` 进行单应用定向诊断；该调试策略重启后失效，不作为成品依赖。

此前 `0.2.75+82` 增加小米 MIX Flip 2 基础外屏支持，按用户要求复用内屏布局并等比例缩小，仍为待真机验收的开发快照：

- Android 声明支持小外屏、可调整窗口大小及内外屏连续性，沿用配置变更处理。参考[小米官方 Flip 适配说明](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2026)，使用系统提供的基础应用区，不扩展到摄像头和系统小部件区域。外屏启动入口及合盖接续仍受设备 HyperOS 的外屏应用管理影响，需要在 MIX Flip 2 实机确认。
- 使用小米 Flip 类型接口及实际窗口尺寸识别外屏；记录内屏逻辑尺寸，外屏使用同一页面树等比例缩放、完整显示并居中，点击坐标随画面同步转换，不单独精简或重排首页、播放页、选集、简介与下载布局。首次直接从外屏启动、尚无内屏尺寸记录时使用 393×852 的逻辑画布，展开后记录实际尺寸。界面缩放设置继续生效；键盘遮挡按缩放比例换算。
- 内外屏切换复用现有播放器与视频组件，窗口变化时取消未完成手势、保存观看位置并重置卡顿计时；短暂切换不立即暂停，真正进入后台仍按原规则暂停，回到前台恢复原播放意图。外屏暂不强制横屏，展开后重新应用原播放方向；画中画不套用整页等比缩放。
- Android 增加播放恢复快照，每秒及开合屏、生命周期、手动跳转时记录当前剧集、集数、位置与播放 / 暂停意图。仅在系统恢复原 Activity 时自动重建播放页，正常冷启动不自动播放。在线播放重新解析当前集；本地成品按媒体库 ID 回查文件；用户锁定或切换时不越权恢复。主动退出播放会清除快照，快照不包含账号凭据或媒体播放地址。系统重建时恢复到最近一次快照，不能视为已验证的零误差无缝切换。
- 完成源码格式整理和收尾同步。2026-10-23 按用户打包要求，重新编译当前 Go 核心并生成 Android arm64 release APK；Flutter 3.47.4 / Dart 3.13.3、NDK 26.1.10909125，使用既有依赖缓存离线构建，锁文件保持不变，保留完整 Material 图标字体。`hongguojian-0.2.75+82-arm64-v8a.apk` 为 29,991,374 字节（28.60 MiB），内部 versionName 为 `0.2.75`、versionCode 为 `2082`，使用 `Watermark.Win` 的 `temp` 密钥签名，证书 SHA-256 与 `AGENTS.md` 指定值一致。APK v2 签名、ZIP CRC、ZIP 对齐与全部 17 个原生库的 16KB ELF 对齐检查通过；核对包内核心与本轮合并 / 去符号输出一致，确认外屏声明已进入安装包。APK SHA-256：`5686262a35e34a6de2d8d8c830a482961e3abca0531548eb713bdca90bf3ad66`。未运行自动化测试、集中静态分析或设备回归，仍为待真机验收的预览包。待集中验收：MIX Flip 2 外屏直接启动、内屏播放后合盖 / 外屏播放后展开、连续多次开合、暂停状态保持、切换恰逢集末自动连播、画中画返回、键盘与触摸位置、系统重建后在线播放及本地视频的续播位置。

此前 `0.2.74+81` 按“先验证官方 API，再开发”的要求接通多季与预约，仍为未经过设备验收的开发快照：

- 先对照 [GitHub 中的相关作品协议实现](https://github.com/it00021hot/hongguo-desktop/blob/8b3daf3bdc9c830188e01beac1b75711d6118a32/crates/hongguo-api/src/detail/mod.rs) 和 [预约协议实现](https://github.com/it00021hot/hongguo-desktop/blob/8b3daf3bdc9c830188e01beac1b75711d6118a32/crates/hongguo-api/src/reservation/mod.rs)，再用本项目自己的匿名设备注册流程和真实登录会话直连官方服务验证。成品不使用第三方项目的共享设备身份、Cookie、签名服务或服务器。
- 多季来源确定为 `GET /reading/bookapi/plan/v` 的 `data[].cell_name=相关作品` → `video_data[]`，只接纳 `tag_info.text=第N季` 的条目，排除“同IP”和“猜你喜欢”；使用官方详情中的 `season_index` 确认当前季，按季号选择更大的最近一季，不能用数组下标或剧名相似度关联。`episode_cnt>0` 且未禁播才可播放；待上线且提供 `online_subscribed` 字段时提供预约。
- 详情入口改用当前用户的设备会话、现代签名和完整 `biz_param` 请求 `/novel/player/video_detail/v1/`，保留网页详情降级。读取相关作品前复用详情缓存；给 reading 系 GET 请求补齐 `Lc`、`X-Reading-Request`，预约继续使用 gzip JSON。
- 播放页独立异步加载多季数据，失败显示原因并允许重试；本季最后一集底部可同时展示已上线下一季和后续可预约新季。切季前保存进度、暂停旧播放器并替换路由；预约 / 取消预约提交后沿用官方列表回查，只有确认后更新按钮。
- 2026-10-23 API 验证通过：示例《一年升一境凡人修仙之外门杂役》第 3 季返回 320 集、下一季第 4 季可播；第 4 季返回 330 集、下一季第 5 季待上线可预约。真实账号完成“未预约 → 预约 → 独立列表确认 → 取消 → 独立列表确认”，已恢复原来的未预约状态。验证未请求站源图片或下载视频，登录凭据保存在源码目录外的本机临时验证目录。
- 已执行本次相关的 Go API 直连验证和多季解析检查；不恢复全量测试或设备回归，未生成新 APK。Android / Windows / Android TV 的底部入口布局、实际点击切季和播放器连续性仍待设备集中验收。

此前 `0.2.73+80` 为播放器优化开发快照，尚未集中验收：

- 首页、搜索、推荐、账号片单及详情播放入口增加同步占位，详情加载、VIP 确认和播放路由返回之前拦截重复点击；本地成品播放入口也增加拦截。
- 官方详情响应增加多季数据解析与传递，仅使用响应中的关联季列表或明确下一季信息。本季最后一集底部增加下一季播放及官方预约 / 取消预约操作；切季前暂停旧播放器并保存进度，使用替换路由进入下一季。预约提交后沿用官方列表回查确认，未登录或预约状态未确认时进入官方预约页面。该快照使用未经实证的字段适配；其多季解析已被 `0.2.74+81` 的独立相关作品接口替换，详见上方实测记录。
- 正常播放保留底栏一个全屏 / 退出按钮，移除顶部重复入口；返回键保留返回行为。左侧亮度手势仅在纵向移动超过 12 像素且以纵向为主时生效，轻触与横向移动不弹亮度条。
- 关闭视频组件自带的后台自动暂停，统一由播放页管理；大小窗和横竖屏切换复用同一视频组件，延迟确认真正进入后台后再暂停，保留播放意图，恢复时继续当前播放位置；过期的小窗状态响应不会覆盖较新的系统回调。
- 选集以播放箭头标识当前集、勾号标识已播放，普通数字标识未播放。按用户保存实际播放过的集号，不把跳过的集数推断为已播放；记录随历史清理，并纳入源码现有备份 / 恢复流程。旧版仅有最后一条观看进度，无法还原此前逐集记录。

`0.2.73+80` 当时仅整理 Dart / Go 源码格式并执行源码收尾同步，未运行静态分析、构建、自动化测试、回归或设备验证；Android、Windows、Android TV 和 iOS 行为均未验证，未生成新 APK。画中画恢复与进度一致性仍需 Android 真机集中验证。

此前 `0.2.72+79` 修复上一包图标字体缺失：保留 `uses-material-design: true`，按原锁文件离线重新生成依赖配置，使用 `--no-tree-shake-icons` 打包完整 Material 图标字体；导出脚本强制校验字体文件和 FontManifest 注册，避免遗漏字体的 APK 被交付。预约和上新预约改为直接复用历史页的筛选 / 编辑栏、三列海报、标题与副标题、搜索和下拉刷新，使用相同的嵌套滚动；待上线 / 已上线使用同款橙色选中标签，上新预约可按全部 / 已预约 / 未预约筛选。未上线卡片点击或长按可预约 / 取消，已上线卡片点击播放、长按管理。播放页取消官方进度排队失败的常驻横幅，继续保存本机进度并重试，失败信息仅记入播放日记；本机存储失败保留一次短暂提示。播放器空白处单击显示 / 隐藏控件，暂停和缓冲时也可手动隐藏，双击仍播放 / 暂停；手机底栏增加带文字的全屏 / 退出按钮，窄屏工具栏可换行。

此前四个变更页面格式整理和静态分析通过（无错误、无警告，保留 13 条既有风格 info），Python 导出脚本语法检查通过。2026-10-23 按用户要求，以当前 `0.2.72+79` 源码重新编译 Go 核心与 Android arm64 release，使用现有 NDK 26.1.10909125、完整 Material 图标字体及 `Watermark.Win` 签名密钥的 `temp` 别名。密钥位置记录在 `AGENTS.md`，口令仅存本机被 Git 忽略的签名配置。`hongguojian-0.2.72+79-arm64-v8a.apk` 为 29,959,422 字节（28.57 MiB），versionCode 2079；签名证书与指定密钥一致，通过 APK v2 签名、ZIP CRC、ZIP 对齐及 17 个原生库的 16KB ELF 对齐检查，包内完整 Material 字体为 1,645,184 字节。APK SHA-256：`08a30ecd2d557d607af9f0467060e45b70f8e9fd24385bac81fe4c3773bf91a3`。依赖版本与锁文件保持不变。本轮未运行自动化测试、回归或真机交互验证。签名与此前 debug 预览包不同，无法直接覆盖安装时需先备份应用数据，再卸载旧包重装。

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
| 浏览 | 首页直接浏览官方推荐流，下拉刷新、自动续页；搜索使用独立底部标签，排行榜为一级页签；批量下载等保留在「我的 → 右上角菜单」。搜索页支持默认、名称、自然季号、上线日期、热度、播放量排序及连载状态筛选。列表下滑接近底部自动加载下一页，底部「加载更多」为兜底 |
| 搜索 | 独立保留搜索词、结果和滚动位置，空白页不加载首页内容。红果合并官网与名称索引，输入停顿 300 毫秒显示最多 10 条联想。部分失败保留有效结果；最近 20 次搜索按用户保存 |
| 排行榜 | 通过一级「排行榜」页签查看官方榜单，切换榜单分类、刷新和加载更多；返回后保留当前榜单及滚动位置 |
| 推荐 | 首页使用官方 `/reading/bookapi/bookmall/cell/change/v` 推荐接口，保持服务端顺序、分页位置与去重；默认每批展示 10 条，切换页签保留列表与滚动位置；刷新开始新一轮推荐，失败保留已有列表 |
| 详情 | 普通点剧直接进入播放；下载和兜底入口保留详情页。详情页浏览封面、资料、追剧状态与可展开简介；底部固定「立即播放 / 继续播放」和下载入口。选集默认折叠，展开后每组 50 集，可切换范围、定位当前或输入集数跳转；宽屏与电视采用资料、选集分栏 |
| 追剧与历史 | 按想看 / 在看 / 已看 / 有更新筛选；红果已追剧发现新季后进入「有更新」。追剧和历史均可搜索。每个用户独立保存，每 5 秒及退出播放时记录真实进度 |
| 账号 | 「我的 → 登录账号 / 账号卡片」，支持中国大陆 +86 手机号验证码登录；若需要上行短信验证，显示本次号码和内容并检查验证结果 |
| 历史 | 「我的 → 历史」内嵌标签，打开时自动拉取最新官方历史，合并本机记录并续播；可同步云端进度，账号与同步页可手动上传登录前的本机历史。清空和删除本机历史不会删除云端记录 |
| 预约 | 「我的 → 预约 / 上新预约」查看、预约或取消预约；账号收藏合并到追剧页，预约仍可查看待上线 / 已上线内容。详情页「预约」可操作当前剧集 |
| 卡片与批量下载 | 卡片「更多」提供收藏、状态和下载选集；电脑右键，电视菜单键。搜索页长按卡片或点「我的 → 右上角菜单 → 批量下载」，一次最多 50 部 |
| 手机播放 | 上滑下一集、下滑上一集；长按 350 毫秒临时 3 倍速。点击播放器空白处显示 / 隐藏控件，双击播放 / 暂停；底栏「全屏」可进入 / 退出全屏。视频下方为「选集 / 简介 / 下载」Tab |
| 折叠外屏 | 小米 Flip 外屏复用内屏整页布局并等比例缩小，开合屏保留播放器；系统重建时从当前用户的最近播放快照恢复。MIX Flip 2 实机待验收 |
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
| Android 8.0+ | 已生成 `yeguo-0.2.77+84-arm64-v8a.apk`（28.87 MiB，versionCode 2084），名称与图标更为「野果」，沿用同一签名可覆盖安装；完整性、签名、图标资源和对齐检查通过，推荐首批 10 条、新排行页签及 MIX Flip 2 外屏连续播放仍待真机验证；armeabi-v7a / x86_64 本轮未构建 |
| Windows 10/11 x64 | 后续新包完整 ZIP 解压后运行 `yeguo.exe`（历史安装包仍为原文件名），保留所有 DLL 与 `data`；局域网原生发现依赖 Windows 10 1903+ |
| Android TV | 与手机共用源码，自动识别电视模式并保持横屏；待电视 / 盒子实机验收 |
| iOS 15.1+ | 已加入工程、Go 核心链接、媒体依赖、文件管理与构建脚本；iOS 播放页禁用 media_kit_video 硬件纹理加速以规避 libmpv 渲染崩溃；待 Xcode 构建与真机验收，无已签名 IPA |

`INSTALL_FAILED_NO_MATCHING_ABIS` 表示 APK 与设备架构不匹配，请更换对应架构安装包。

### GitHub Actions

工作流 **Release Yeguo**：推送主分支且 `pubspec.yaml` 变化时检测版本，也可手动运行；仅主分支可发布。与已有公开正式 Release 比较，`X.Y.Z` 和 `+构建号` 均提高才构建；同版本无操作、低版本报错。不会由 PR 或普通标签推送触发。

只构建 Android arm64：`python3 scripts/build_android.py --abi arm64-v8a`。Release 标签为 `app-vX.Y.Z-build`，包含 `yeguo-X.Y.Z+build-arm64-v8a.apk`、`update.json` 和 `SHA256SUMS.txt`。APK 必须使用指定发布证书；无正式签名时拒绝发布。Windows、iOS 和其他 Android 架构不参与本工作流。

仓库 Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`（`temp`）、`ANDROID_KEY_PASSWORD`。密钥与口令从本机指定签名资料读取后通过 Secrets 配置，不进入代码、日志或源码压缩包。证书 SHA-256 固定为 `2B:1F:9D:EC:18:0E:97:2D:6C:37:36:C5:EF:D5:2E:E7:95:2E:DE:41:55:EE:EC:DB:BC:23:EA:33:1F:FA:07:6E`。

后台沿用 [Mac Explorer 发布工作流](https://github.com/3egirlsdream/Mac-Explorer/blob/main/.github/workflows/release.yml) 的 `http://thankful.top:4396`，使用独立 `Client=Yeguo`，不写入 `MacExplorer`。`GET /api/CloudSync/GetVersion?Client=Yeguo` 查询；Release 成功后 `POST /api/CloudSync/SaveVersion` 写入 `{Client, Version, Path, Memo}`。`Version` 为完整 `X.Y.Z+build`，`Path` 为该 Release 的 HTTPS `update.json`。清单记录软件类型、版本、说明及 arm64 APK 的固定版本地址、大小和 SHA-256。应用只接受本仓库 HTTPS Release 清单和附件，再按设备架构匹配。

构建 / 上传失败不会上报后台；公开 Release 后后台同步失败，可重跑失败任务，或主分支手动运行并勾选 `sync_backend_only`，仅同步当前最高已发布版本，不重复构建。相同版本信息已一致时跳过写入；后台已有更高版本则拒绝回退。草稿失败重跑仅允许相同提交恢复上传，其他提交需提升版本。新类型记录只在实际 Release 公开后创建。

软件仓库：[3egirlsdream/hongguo](https://github.com/3egirlsdream/hongguo)；开发者：[3egirlsdream](https://github.com/3egirlsdream)；始终最新下载：[Latest Release](https://github.com/3egirlsdream/hongguo/releases/latest)。

本地 `android/key.properties` 继续保留在忽略规则内，不入库；本机签名路径与读取口令方式见 `AGENTS.md`。

## 开发与构建

Flutter `3.47.4`、Dart `3.13+`、Go `1.24.1+`、Python `3.10+`。Android 需要 JDK 17、SDK 36、NDK 默认 `28.2.13676358`；Windows 需要 Visual Studio C++ 桌面组件及 MinGW-w64 x64；iOS 需要 macOS、完整 Xcode 和 CocoaPods。

构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，同名环境变量可覆盖。

复用已有 Android SDK 时将 `ANDROID_HOME` 指向其目录。可用 `ANDROID_NDK_VERSION` 和 `ANDROID_NDK_HOME` 指定已安装的其他 NDK（主程序、插件与 Go 核心保持一致），无需替换默认发布配置；本次 Android arm64 测试包使用现有 NDK `26.1.10909125`。

~~~sh
python3 scripts/build_android.py                 # 野果
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

本地构建产物位于 `dist/android`、`dist/windows`、`dist/ios`，新生成文件均以 `yeguo-` 开头，历史包保留原文件名。

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
