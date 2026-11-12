# 流光 LiuGuang 手册

流光（LiuGuang）是 Anikumo 影视区使用的**自研纯 Dart 影视框架引擎**：
一个由 21 个包组成的 Monorepo，无 UI、无 Flutter 依赖、不起任何服务，
以进程内 API 的形式被宿主直接调用。它负责把宿主注册进来的内容源执行成统一的
搜索 / 详情 / 季集 / 播放源数据，并提供播放器抽象、历史、收藏、同步与下载等
一整套影视 App 所需的框架能力。

- 引擎本体：独立仓库（纯 Dart 包集合，`sdk: >=3.10.0 <4.0.0`），原名
  Aurora Media Engine，2026-11-11 更名流光。
- 在 Anikumo 中以 vendored 副本形式内置：`packages/liuguang_*` 共 21 包
  （入仓时剔除了各包的 `test/` 与 `example/`），影视区代码只通过
  `LiuGuangMediaEngine` 门面与它打交道。
- 本手册内容：普通用户视角、**工作原理与运行机制**、SDK 调用详解、
  调用数据存放位置、已知限制、开源信息。

---

## 一、这是什么

**流光（LiuGuang）是 Anikumo 作者自研的一个纯 Dart 影视引擎与框架**，
与小说区的「墨源 MoYuan」、漫画区的「MangaKit」平级互不侵入。
它和墨源最大的不同在形态：墨源是单文件 JS 引擎、靠宿主注入通道工作；
流光是原生的 Dart 包集合，宿主用 `path:` 依赖把它编进自己的进程，
直接调用 `LiuGuangMediaEngine` 的方法——没有服务器、没有跨进程桥、
没有序列化往返。

它负责的事情分两半：

- **内容链**：把宿主注册的资源源（`MediaSourceProvider`）统一成
  搜索 → 详情 → 季 → 集 → 播放源的标准链路，做多源聚合搜索、
  标题匹配与去重、元数据多方合并。
- **框架件**：播放器内核抽象（解码内核由宿主提供）、播放队列与续播、
  历史与收藏仓库、LRU 缓存、字幕解析、音轨选择策略、插件清单与权限、
  跨设备同步引擎、下载引擎（断点续传 + HLS 分片拼接）。

引擎本身不内置、不提供任何内容源与内容，源由宿主（或用户经宿主）注册，
内容版权归原站与原作者所有。全部包零第三方运行时依赖（只有
`liuguang_storage_hive` 依赖 `hive_ce`），其余只用 `dart:` 核心库。

主要能力：

- 多源并发聚合搜索（失败隔离、去重、按匹配度排序、分页、结果缓存）
- 统一媒体模型：Movie / TVSeries / Season / Episode / VideoSource，
  全部支持 JSON 往返
- 标题规范化与匹配打分（SxxExx 与「第X季/第X集」抽取、年份、别名、外部 id）
- 元数据聚合：多家提供方按字段优先级合并、跨源去重、自带 TMDB 适配器
- 播放器抽象：内核可注册替换，队列、自动下一集、从历史续播由控制器托管
- 同步与下载均为可选子系统：不注册就明确报错，绝不静默假装成功

---

## 二、在 Anikumo 里怎么用

普通观众不需要接触引擎本身，只需要接口配置：

1. **导入接口**：影视区 →「影视设置」→ 导入接口配置，或用仓库配置一键导入。
   App 不内置任何接口，导入什么就能看什么。
2. **找片**：精选、发现（题材 / 地区 / 年份 / 类型 / 接口五维筛选）、
   聚合搜索都走引擎的聚合链：多接口并发、结果去重后按匹配度排好序上屏，
   某个接口挂了只会在状态里标错，不拖垮整页。
3. **看片**：点进详情选集播放。播放器实际解码用的是 App 现成的 media_kit，
   它在引擎里注册为一个播放内核；续播点、播放历史、收藏都由引擎的
   仓库层统一管理。
4. **账户加成**：在影视设置「账户」里关联 TMDB / Bangumi 后，
   海报、评分、影评、角色等资料会经元数据合并层补齐；
   「我的云端片单」把两边的收藏拉到一页，点开自动找源。
5. **下载与追剧**：下载走引擎的下载管理器（支持断点续传与 HLS 分片拼接），
   任务在重启后恢复；追剧自动更新等扩展在影视区的插件仓库里按需安装。

影视区的扩展功能在插件仓库里安装（极速解析、线路测速优选、下载省空间、
追剧自动更新），没安装的功能在区内完全不存在——这与引擎的插件体系是两回事：
引擎插件（见 3.11）管的是清单校验与权限门禁，区内的功能包是 App 层的功能开关。

---

## 三、工作原理与运行机制

### 3.1 总览：它到底在做什么

一句话原理：**流光是一个「源接口 + 框架件」的集合——源只负责按统一接口
交出原始条目，聚合、匹配、合并、排序、缓存、队列、落盘全由框架层做**。
它自己不认识任何具体站点，不假设任何站点的页面或接口长什么样，
只认 `MediaSourceProvider` 这一个接口（见 4.4）。

分层结构（自下而上）：

| 层 | 职责 | 代表包 |
|---|---|---|
| 基础层 | 统一数据模型、标题匹配、网络传输、存储接口、缓存、字幕解析 | models / matcher / network / storage / cache / subtitle |
| 源层 | 源接口契约（SDK）、源注册表与请求闸门、健康检查 | source_sdk / source_runtime |
| 聚合层 | 多源并发搜索、元数据提供方聚合与字段合并、去重 | search / metadata |
| 播放层 | 播放器内核抽象与注册表、播放队列控制器、音轨策略、平台能力矩阵 | player_api / audio / platform |
| 数据层 | 历史、收藏仓库；可选子系统：同步引擎、下载引擎 | history / favorites / sync / download |
| 生态层 | 插件清单校验、API 版本范围、权限门禁 | plugin_api / plugin_manager |
| 门面层 | `LiuGuangMediaEngine`：唯一对宿主的进程内集成面 | core |

依赖方向严格单向：上层依赖下层，同层不横向直连（例如 search 需要去重时
用的是 metadata 包里导出的 `MetadataDeduplicator`，而不是反过来）。

### 3.2 一次搜索的全过程

以在 Anikumo 里搜一部剧名为例，引擎内部依次发生：

1. **入口**：宿主调用 `engine.search(SearchRequest(keyword: …))`，
   未 `initialize()` 就调用会抛 `LiuGuangException(notInitialized)`。
2. **缓存先行**：聚合器先拿 `SearchRequest.cacheKey`
   （`关键词|页|页大小|类型|年份|源 id` 拼成）查结果缓存
   （门面内置的 LRU：64 条、TTL 2 分钟），命中直接返回。
3. **并发分发**：对注册表中**已启用**的源开并发池（`AggregatedSearch`
   默认并发 4），每个源带 10 秒超时单独跑；单源抛错只记进
   `SearchPage.perSourceStatus`（形如 `ok:12` / `error:…`），不影响其他源。
4. **闸门排队**：每个源的实际调用都过源运行时的 `RequestGate`
   （默认单源并发上限 3、两次启动最小间隔 20ms），防止单个源被打爆。
5. **合并去重**：所有源的结果汇总后过 `MetadataDeduplicator`——
   先按指纹（有外部 id 用 `ext:<id>:<类型>`，否则用
   「规范化标题 | 年份 | 类型」）分组，组内两两用 `TitleMatcher.score`
   复核（≥ 0.6 判定同一部），多条命中同一部的用 `MetadataMerger`
   按字段优先级合并成一条（见 3.5）。
6. **本地过滤与排序**：按请求的 `mediaType` 过滤；年份过滤容差 ±1 年；
   最后以关键词构造一个临时条目，逐条打匹配分降序排序。
7. **分页切片**：排序后的全量结果按 `page / pageSize` 切片返回
   （`totalResults` 是去重后的总数），并写回结果缓存。

详情、季、集是同一套「逐源问询」机制：门面按注册顺序逐个已启用源发问，
第一个给出非空结果的源胜出（问询同样过闸门）；播放源不同——它把**全部**
已启用源的结果汇总返回，线路齐全与否由宿主界面决定怎么呈现。

### 3.3 标题匹配与去重指纹

`TitleMatcher`（liuguang_matcher）是全引擎的同一性判定核心：

- **规范化** `normalize`：转小写、抹掉 `S01E02` 式标记与「第X季/第X集」、
  抹标点、去掉 season / series / the 等噪声词、折叠空白。
  所以《某剧 第二季》和 `某剧 S02` 能对上号。
- **抽取**：`extractSeasonEpisode` 认 `SxxExx` 与中文「第X季 / 第X集」
  （含中文数字一到十）；`extractYear` 取标题里第一个 19xx / 20xx。
- **打分** `score`：满分 1.0，`isMatch` 阈值 0.6。权重构成：
  类型不一致直接 0.1 出局；TMDB / IMDb / Bangumi 任一外部 id 相同直接 1.0；
  规范化标题全等 +0.6、互相包含 +0.35、词集合 Jaccard 相似 ×0.4、
  别名或原标题命中 +0.5；年份全等 +0.25、差 1 年 +0.1、差太多 −0.2；
  题材有交集 +0.05。每项加减都带一条 reason，打分全程可解释。
- **指纹** `fingerprint`：优先外部 id（`ext:` 前缀），否则
  `fp:规范化标题|年份|类型`——收藏去重、搜索分组、历史归并都用它。

### 3.4 源运行时：注册表、闸门与健康检查

`SourceRegistry`（liuguang_source_runtime）持有全部已注册源：

- **注册与启停**：`register` 按 `descriptor.id` 入册、默认启用；
  `setEnabled` 切换启停（对未知 id 抛 `StateError`）；门面的一切问询
  只遍历 `enabledProviders`。`unregister` 连启停状态一并移除。
- **请求闸门** `RequestGate`：按源 id 分别计数在途请求，超上限的排队等待，
  最小启动间隔自上一次**实际启动**时刻起算。
- **在途合并** `deduped(key, task)`：相同 key 的并发调用只真正执行一次，
  后来者共享同一个 Future——详情页与预加载撞车时不会重复打源。
- **健康检查** `healthCheckAll`：逐源调用各自的 `healthCheck()`，
  抛错的源被收成 `SourceHealth.fail(原因)`，永不向上抛。
  `SourceHealth` 自带耗时（latency），界面上的源状态与测速展示源于此。

### 3.5 元数据聚合与字段合并

`MetadataProvider`（liuguang_metadata）是与资源源平行的另一条供给线：
资源源给「能看的条目」，元数据提供方给「更全的资料」，接口只有两个：
`byId(外部 id)` 与 `byTitle(标题, {年份})`。

- **仓库** `MetadataRepository`：逐个提供方发问、失败隔离，
  结果汇总后同样过去重器；`byId` 多方都有结果时合并成一条。
- **合并** `MetadataMerger`：按 `FieldPriority` 给出的来源优先级排序后逐字段取优——
  字符串与列表字段取排序后第一个非空值；评分取最高分那条；
  外部 id 逐家取第一个非空；人物按 `id:角色` 去重合并；别名取并集。
  合并只在同类型内进行，电影与剧集各走各的构造。
- **TMDB 适配器** `TmdbMetadataProvider`：仓库自带，`byTitle` 走
  TMDB 的多类型搜索、电影与剧集分别映射成 Movie / TVSeries，
  海报与背景图拼成 TMDB 图片地址，评分与外部 id 一并带回。
  **它需要用户自备的 API key**：没传 key 时任何调用直接抛
  `TmdbNotConfiguredException` 明说未配置，绝不返回编造的数据。

### 3.6 播放器抽象与播放控制器

引擎不带解码能力——解码是宿主的事。`PlayerEngine`（liuguang_player_api）
是内核要实现的接口：`initialize / open / play / pause / stop / seek /
setSpeed / setVolume / setMuted / selectSubtitle / selectAudio /
setSubtitleDelay / dispose`，加上 `stateStream`、`eventStream`
与 `currentState`；状态机为 `PlaybackStatus`
（idle / opening / buffering / playing / paused / ended / error）。
每个内核注册时声明 `PlayerCapabilities`（HDR、硬解、字幕、多音轨、
画中画、后台播放、支持的格式集合）。

- **注册表** `PlayerRegistry`：按 kernelId 存工厂函数；
  `createWithFallback([偏好序])` 逐个尝试，第一个能建出来的胜出。
  门面构造时预注册了一个 `memory` 内核兜底。
- **内存内核** `InMemoryPlayerEngine`：一个真能跑的假内核——用定时器
  按倍速推进 position、到时长自动转 ended，seek / 倍速 / 音量 /
  字幕音轨选择都真实生效。它是测试与无解码环境下的占位实现，
  也是宿主接真内核时的行为参照。
- **控制器** `PlaybackController`：托管队列（`openQueue` 打开、
  `next / previous` 切集），`autoNext` 为真时监听内核的 `ended`
  事件自动下一集；打开队列项前若注入了 `resumeResolver`，
  先问它要续播点再 `open`。门面 `createPlaybackController()`
  创建的控制器已把解析器接到引擎自己的历史仓库——
  所以「看过的集自动从上次位置续播」是开箱即用的。

### 3.7 存储层：一切落盘都过 StorageAdapter

`StorageAdapter`（liuguang_storage）是全引擎唯一的落盘面，
接口按「表 / 键 / JSON 值」建模：`put / get / all / delete /
clearTable / exportAll / importAll`。导出格式带版本号（当前 version 1），
版本不符的导入直接抛 `FormatException`，不硬吞。

三个现成实现：

- `MemoryStorageAdapter`：纯内存，测试与临时场景用；门面在宿主没给
  存储时默认用它（进程结束数据即清，属预期行为）。
- `JsonFileStorageAdapter`：整个库一个 JSON 文件，内存镜像 + 每次写后刷盘。
- `HiveStorageAdapter`（liuguang_storage_hive）：一表一个 Hive box
  （盒名 `liuguang_<表名>`），值存 JSON 字符串、免代码生成；
  这是仓库里唯一的第三方运行时依赖（`hive_ce ^2.16.0`）。

历史、收藏、同步、下载、音轨延迟——所有仓库都只认这个接口，
换实现不用改任何业务代码。各表的名字与内容见第五章。

### 3.8 同步引擎（可选子系统）

`SyncEngine`（liuguang_sync）解决多设备数据一致，设计要点：

- **传输留宿主**：引擎只认两方法的 `SyncTransport` 接口
  （`push(记录批)` / `pull(集合, {since})`），宿主拿 HTTP 接口、
  WebDAV 或任何通道实现它即可；仓库自带 `InMemorySyncTransport`
  供测试与单机回环（含离线 / 失败模拟开关）。
- **本地真相 + 发件箱**：本地数据存 `sync_records` 表；
  `applyLocal` 记一次本地变更（版本号 +1、打时间与设备戳）并把
  键写进 `sync_outbox` 表排队——重启后待推变更不丢。
- **一轮同步** `sync()`：先推发件箱（成功才清队），再逐集合按
  上次拉取水位（`sync_state` 表的 `lastPullAt`）增量拉取并逐条裁决；
  传输失败指数退避重试（默认最多 3 次、基数延迟可注入），
  耗尽后返回 `status=error` 的 `SyncState`，发件箱原样保留等下一轮。
- **按集合分型的冲突规则**：history 类「最新者胜」（时间同则比版本号、
  再同则远端胜）；favorites 类「并集」——存活记录永远压过删除墓碑，
  两边都存活时 JSON 载荷逐键合并（新者赢共享键），合并结果会重新入队
  推送以便两边收敛；settings 类按构造时配置的 `settingsPriority`
  （local / remote）整边胜出；其他集合按 history 规则。
- **删除靠墓碑**：`deleted` 标记随记录同步，删除才能传播、
  不会被旧数据「复活」。全程状态经 `states` 流广播
  （`SyncState{status, pushed, pulled, conflicts, pending}`）。

### 3.9 下载引擎（可选子系统）

`DownloadManager`（liuguang_download）是一个持久化下载队列：

- **队列与并发**：任务入队即落盘（`downloads` 表），默认并发 2；
  `pause / resume / cancel` 齐全，进度经 `updates` 流逐任务推送。
  重启 `restore()` 时发现上次停在 downloading 的任务一律泊为 paused。
- **普通文件**：先写 `<目标>.part`，凭已落盘长度发 Range 请求续传；
  服务器不认 Range（没回 206）就干净重下、绝不重复拼字节
  （任务上会标 `rangeFallback`）；下完校验总长度再改名为正式文件。
  失败有界重试（默认 2 次）。
- **HLS**：地址以 `.m3u8` 结尾即按 HLS 处理——拉媒体播放列表、
  逐分片下载后顺序拼成单个文件；分片计划（地址、各片长度、已完成数）
  存在 `download_segments` 表，暂停 / 重启后从未完成的分片接着下，
  分片级续传。字节传输走可注入的 `DownloadTransport`
  （默认 `IoDownloadTransport`），便于测试替换。
- **明确不支持**（抛 `DownloadException` 明说，不产出坏文件）：
  主播放列表（master playlist）、加密分片（`EXT-X-KEY`，
  典型即 **HLS AES-128**）、直播列表（无 `EXT-X-ENDLIST`）。
  m3u8 的解析在同包的 `parseM3u8` 里，只做分片提取与这三类识别。

### 3.10 字幕与音轨

- **字幕**（liuguang_subtitle）：`parseSubtitle(格式, 文本)` 按格式分发到
  `SrtParser / VttParser / AssParser`，统一产出
  `SubtitleTrackData`（按开始时间排序的 `SubtitleCue` 列表，
  带 start / end / text / style）。`cueAt(t)` 取某一时刻的字幕、
  `cuesIn(a, b)` 取区间内字幕，供界面渲染直接调用。
  ASS 会剥掉 `{...}` 样式标签、保留 Style 名；VTT 会剥掉内嵌 HTML 标签。
- **音轨选择**（liuguang_audio）：`AudioTrackSelector` 是一个确定性策略——
  给定音轨列表与语言偏好序打分排序：语言命中偏好第 n 位得
  `1000 − 100n` 分（按主语言子标签比，`zh` 能命中 `zh-CN`）、
  默认轨 +100、标签含 forced 的轨 −400（强制轨只作兜底）、
  声道数作小权重平局项；同分保持原列表顺序。`select` 返回首选
  与完整排名及每条的得分理由。
- **音轨延迟** `AudioDelayStore`：用户给某条音轨拨过的同步偏移按
  「媒体 id :: 音轨 id」存进 `audio_delays` 表，下次播放同集同轨自动恢复。
- **能力门禁** `audioCapability`：给 UI 用的纯函数——内核不支持多音轨
  或只有一条音轨时，明确给出不可选及原因文案，界面据此置灰。

### 3.11 插件体系：清单、版本范围与权限

引擎的插件是**声明式**的：一个插件先有一份 `PluginManifest`
（liuguang_plugin_api，JSON 往返），字段含 id / name / version /
type / apiRange / permissions / dependencies / entry；
type 分 source / player / metadata / search / storage / cache /
network / ui / theme / tool 十种，权限分 network / storage.read /
storage.write / clipboard / webview / filesystem 六种。

`PluginManager`（liuguang_plugin_manager）在注册时把三道门：

1. **清单校验**：id / name / version 缺失、type 未知、权限名不认识，
   `PluginManifest.fromJson` 直接抛 `FormatException` 并列出全部问题。
2. **版本范围**：宿主 API 版本（默认 `0.1.0`）必须落在插件声明的
   `apiRange`（默认 `>=0.1.0 <1.0.0`，支持 `>=` `<=` `>` `<` `^` 与精确等值）
   之内，否则拒绝注册；`versionInRange` 是这条规则的实现。
3. **依赖与权限**：声明的 dependencies 必须已注册；运行时经
   `requirePermission` / `guard` 检查——插件被禁用或没声明该权限，
   分别抛 `StateError` / `PermissionDeniedException`。

要注意口径：这一层管的是清单与权限账本，插件代码的加载与执行不在
引擎职责内（宿主决定怎么装载），引擎不做任意代码直装。

### 3.12 平台能力矩阵

`liuguang_platform` 回答「这台设备到底能用什么」：

- `PlatformInfo.current()` 按 `dart:io` 的操作系统名判定
  android / ios / windows / macos / linux / unknown。
- `PlatformCapabilities.defaultsFor` 给每个系统一份**保守**默认矩阵
  （如 Linux 默认不开硬解——发行版与驱动组合太多，宁可软解不黑屏；
  iOS 格式只报 mp4 / hls）。
- 宿主目录经 `HostPaths` 注入（cacheDir / dataDir / downloadDir），
  引擎不猜 App 的目录；默认实现 `IoHostPaths` 挂在系统临时目录的
  `liuguang/` 下，只适合工具与测试。
- `mergeCapabilities(engine:, platform:)` 求内核能力与平台矩阵的交集：
  画中画 / 后台 / 硬解取逻辑与，格式取两边集合交集——
  会话实际可用能力永远取「内核会的 ∩ 平台允许的」，不多报。

### 3.13 在 Anikumo 里的宿主结构

- 引擎副本：App 的 `packages/liuguang_*`（21 包 vendored，与独立仓库
  不自动同步，改引擎要先想清改哪边）；影视区服务层在
  `lib/services/liuguang/`，页面在 `lib/pages/liuguang/`。
- 宿主门面是 `VideoEngineService`（`video_engine.dart`）：进程内单例，
  首次用时启动 `LiuGuangMediaEngine` 并完成全部注册——
  存储注入 App 侧的 Hive 实现、播放内核注册 media_kit、下载管理器注册。
- 适配走「宿主实现接口」的方式（设计文档里称 aurora_anikumo_adapter 这一层）：
  - `CmsApiSource implements MediaSourceProvider`：把用户导入的
    JSON 接口配置适配成引擎的源接口，影视区的内容源全由它供数
    （分类树、线路与分集的解析也在这里）；
  - `MediaKitPlayerEngine implements PlayerEngine`：把 App 现成的
    media_kit 播放器包成引擎内核，以 `mediakit` 为 kernelId 注册，
    声明硬解、字幕、多音轨与五种格式能力；
  - `AnikumoLiuguangStorage implements StorageAdapter`：架在 App
    已初始化的 Hive 之上（一表一盒、盒名 `liuguang_<表名>`），
    与仓库自带的 `HiveStorageAdapter` 同语义，区别只是复用 App 的
    Hive 实例而不是自己再 `Hive.init` 一次。
- **零耦合方向**：引擎包从不 import App 的任何代码；App 依赖引擎、
  引擎只认接口。换宿主时重写这一层适配即可，引擎本体不动——
  这也是流光能先独立交付、再嵌入 Anikumo 的原因。

---

## 四、SDK 调用详解

### 4.1 初始化

```dart
import 'package:liuguang_core/liuguang_core.dart';

final engine = LiuGuangMediaEngine(
  config: LiuGuangEngineConfig(
    storage: JsonFileStorageAdapter('/path/db.json'), // 不给则用内存存储
    deviceId: 'this-device',                          // 收藏与同步的设备戳
  ),
);
await engine.initialize();   // 未初始化就调业务方法抛 notInitialized
```

`liuguang_core` 是门面包：它转发导出 models / source_sdk / player_api
的全部类型，以及 sync 与 download 的主要类型，宿主通常只 import 它一个
（外加自己要实现的接口所在包）。构造时门面已经备好：历史仓库、收藏仓库、
源注册表、播放器注册表（含 `memory` 兜底内核）、插件管理器、
搜索结果缓存，并把历史仓库接上播放控制器的续播解析。

### 4.2 核心调用

```dart
engine.registerSource(mySource);                    // MediaSourceProvider，可注册多个
engine.registerMetadataProvider(myProvider);        // 可选，元数据提供方
engine.registerPlayerKernel('mediakit', () => MyEngine(), const PlayerCapabilities(...));

final page   = await engine.search(SearchRequest(keyword: '剧名', page: 1, pageSize: 20));
final detail = await engine.getDetail(page.items.first.id);          // MediaDetail?
final seasons  = await engine.getSeasons(detail!.item.id);
final episodes = await engine.getEpisodes(seasons.first.id);
final videos   = await engine.getPlaybackSources(
    PlaybackQuery(mediaId: detail.item.id, episodeId: episodes.first.id));
final controller = engine.createPlaybackController();   // 队列 / 自动下一集 / 续播
final player = await controller.openQueue(videos);
await engine.dispose();
```

`getDetail` 找不到任何源认领时返回 null（区别于抛错）；
`getSeasons / getEpisodes` 无结果返回空列表；`getPlaybackSources`
汇总全部已启用源。`engine.events` 是广播流，已有事件：
`initialized`、`search`（带关键词与条数）、`sync`、`downloadEnqueued`。

### 4.3 返回结构（统一数据契约）

```text
MediaItem（抽象基类）:
  { id, mediaType(movie|series), title, originalTitle, localizedTitles{}, aliases[],
    year, overview, genres[], countries[], studios[], people[](Person: 含 role/character),
    rating{score, votes, source}, artwork{poster, backdrop, logo, stills[]},
    externalIds{tmdb, imdb, bangumi}, sourceId, updatedAt, raw{} }
Movie extends MediaItem:    + runtime, releaseDate
TVSeries extends MediaItem: + seasons[], status, totalEpisodes
Season:  { id, seriesId, seasonNumber, title, episodes[], airDate }
Episode: { id, seasonId, seriesId, episodeNumber, title, still, airDate, runtime, overview }
VideoSource:
  { id, sourceId, mediaId, episodeId, url, quality, format(mp4|hls|dash|webm|mkv|unknown),
    headers{}, subtitles[](SubtitleTrack), audioTracks[](AudioTrack), expiresAt }
SearchPage:
  { items[], page, totalPages, totalResults, perSourceStatus{源id: 'ok:n'|'error:…'} }
MediaDetail: { item, seasons[] }
```

全部模型都有 `toJson / fromJson`；多态反序列化入口是
`TVSeries.mediaFromJson`（按 `mediaType` 分发到 Movie / TVSeries）。
`VideoSource.isExpired` 按 `expiresAt` 判断链接是否已过期。

### 4.4 写一个源：MediaSourceProvider

源接口（liuguang_source_sdk）只有七个成员，是全引擎最小的对接面：

```dart
class MySource implements MediaSourceProvider {
  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
        id: 'my-source', name: '我的源', version: '1.0.0',
        capabilities: SourceCapabilities(
          supportsSeasons: true, supportsPagination: true,
          supportsDirectPlayback: true,          // 其余默认：不需登录、不需 WebView 解析
        ),
      );

  @override
  Future<SearchPage> search(SearchRequest request, {SourceCancelToken? cancel}) async { … }
  @override
  Future<MediaDetail?> getDetail(String mediaId) async { … }
  @override
  Future<List<Season>> getSeasons(String seriesId) async { … }
  @override
  Future<List<Episode>> getEpisodes(String seasonId) async { … }
  @override
  Future<List<VideoSource>> getPlaybackSources(PlaybackQuery query) async { … }
  @override
  Future<SourceHealth> healthCheck() async => SourceHealth.ok(Duration.zero);
}
```

约定：`SearchRequest` 带 keyword / page / pageSize / mediaType / year /
sourceId；源只管按页交结果，跨源去重、重排与再分页由聚合层做。
`SourceCancelToken` 是协作式取消——源在长循环里自查 `isCancelled` 即可。
仓库附带一个完整示例源 `plugins/example_plugins/local_sample_source`
（内置 2 部电影 + 1 部 2 季剧集的样本目录，播放地址指向公开样本 MP4），
是写新源时最直接的参照；它的清单声明见 `SourceManifest`
（descriptor + kind + config 的 JSON 形状）。

### 4.5 历史与收藏（门面直达）

```dart
await engine.history.updateProgress(
  mediaId: '…', episodeId: '…', title: '…',
  position: Duration(minutes: 7), duration: Duration(minutes: 24),
);   // 进度 ≥95% 自动标 completed
final resume = await engine.history.resumePosition('…', episodeId: '…');
   // 已看完、或进度不足 5 秒时返回 null（不值得续）
final watching = await engine.history.continueWatching();  // 未看完列表

final fav = await engine.favorites.add(item);               // 带媒体快照与修订号
await engine.favorites.isFavorite(item.id);
final cols = await engine.favorites.createCollection('想看');
final list = await engine.favorites.list(collectionId: cols.id);
```

收藏条目自带 `revision / updatedAt / deviceId / mediaSnapshot`——
快照让收藏在源失效时仍能展示标题海报，修订号是同步合并的依据。
删收藏夹时里面的条目回落到 `default`，不连带删除。

### 4.6 元数据（可选接入）

```dart
engine.registerMetadataProvider(TmdbMetadataProvider(apiKey: userKey));
final repo = engine.metadataRepository;             // MetadataRepository
final hits = await repo.searchByTitle('剧名', year: 2024);  // 多方汇总、已去重合并
final one  = await repo.byId('12345');
final merged = MetadataMerger(priority: FieldPriority({'*': ['tmdb']})).merge(items);
```

自写提供方只需实现 `MetadataProvider`
（`providerId` + `byId` + `byTitle`）。提供方抛错被仓库隔离，
不会拖垮整次查询。

### 4.7 播放控制

```dart
final controller = engine.createPlaybackController();
final player = await controller.openQueue(videos, startIndex: 0, kernelPreference: 'mediakit');
   // 内核按偏好序带兜底创建；resume 默认开，续播点来自历史仓库
player.stateStream.listen((s) { /* PlaybackState: status/position/duration/speed/… */ });
await player.seek(Duration(minutes: 3));
await player.setSpeed(1.5);
await player.selectSubtitle('zh'); await player.selectAudio('ja');
await controller.next();                            // 或等 ended 事件自动切（autoNext）
await controller.dispose();
```

宿主写内核时实现 `PlayerEngine` 接口即可（见 3.6）；
能力声明 `PlayerCapabilities` 决定上层敢开放哪些按钮——
比如内核 `subtitles: false` 时选字幕会抛 `StateError` 明说不支持。
实际会话能力再与平台矩阵求交：`mergeCapabilities(engine: …, platform: …)`
（liuguang_platform）。

### 4.8 同步（可选子系统）

```dart
engine.registerSyncEngine(SyncEngine(
  storage: storage, transport: myTransport,           // SyncTransport 由宿主实现
  deviceId: 'this-device',
  settingsPriority: SyncPriority.remote,              // settings 冲突时远端胜
));
final sync = engine.requireSync();
await sync.applyLocal(collection: 'history', key: 'm1::e1', payloadJson: json);
final state = await engine.syncNow();   // SyncState{status, pushed, pulled, conflicts, pending}
sync.states.listen((s) { /* 状态广播 */ });
```

### 4.9 下载（可选子系统）

```dart
engine.registerDownloadManager(DownloadManager(storage: storage));
await engine.downloadManager!.restore();            // 先恢复上次的任务表
final task = await engine.enqueueDownload(url: url, targetPath: path);
await engine.startDownload(task.id);
engine.downloadManager!.updates.listen((t) { /* DownloadTask: status/progress */ });
await engine.downloadManager!.pause(task.id);       // resume / cancel 同理
```

同步与下载都是**注册才有**：没注册就调用 `syncNow()` /
`enqueueDownload()` / `startDownload()`，抛
`LiuGuangException(LiuGuangErrorCode.notEnabled)` 并写明要先注册什么；
`syncEnabled` / `downloadsEnabled` 可先行判断。这是刻意口径——
不做静默空转，不假装成功。

### 4.10 字幕、音轨与匹配工具（可独立使用）

```dart
final track = parseSubtitle('ass', assText);        // liuguang_subtitle
final cue = track.cueAt(Duration(seconds: 42));
final choice = AudioTrackSelector.select(video.audioTracks, // liuguang_audio
    languagePreferences: ['zh', 'ja']);
final score = TitleMatcher.score(itemA, itemB);     // liuguang_matcher
final se = TitleMatcher.extractSeasonEpisode('某剧 S02E05');
final http = LiuGuangHttpClient();                  // liuguang_network
final json = await http.getJson(url);               // 重试 / Cookie / 超时 / 取消
print(LiuGuangHttpClient.redactHeaders(headers));   // 日志前脱敏 Authorization 与 Cookie
```

网络层 `LiuGuangHttpClient` 的口径：5xx 与传输错误指数退避重试
（默认 `maxRetries: 2`），4xx 立即抛 `NetworkException`（带 statusCode）；
Cookie 按主机存进 `CookieJar` 自动回带；传输面是 `HttpTransport`
接口，默认实现 `IoHttpTransport`（dart:io），测试可替换。

### 4.11 插件管理（门面直达）

```dart
final entry = engine.plugins.register(PluginManifest.fromJson(manifestJson));
engine.plugins.requirePermission('my-plugin', PluginPermission.network);
final value = engine.plugins.guard('my-plugin', PluginPermission.storageRead, () => read());
engine.plugins.disable('my-plugin');
```

### 4.12 错误约定

门面层统一抛 `LiuGuangException {code, message, cause}`，
`LiuGuangErrorCode` 取值：`notInitialized` 未初始化 ·
`notEnabled` 可选子系统未注册 · `sourceNotFound` · `sourceDisabled` ·
`playbackFailed` · `metadataFailed` · `cancelled` · `unknown`（兜底，
原始错误在 `cause` 里）。各包内部另有自己的异常类型，语义就地明确：
网络 `NetworkException / CancelledException`、下载 `DownloadException`、
同步 `SyncTransportException`、插件 `PermissionDeniedException`、
TMDB 未配 key 的 `TmdbNotConfiguredException`。共同口径是**不吞错、
不编造**：能力没有就抛错说明，数据拿不到就返回空或 null 并留状态痕迹。

### 4.13 Anikumo 桥接层（宿主对接面）

Anikumo 侧不需要桥接「协议」——同进程同语言，桥接就是实现接口：

| 引擎接口 | Anikumo 实现 | 职责 |
|---|---|---|
| `MediaSourceProvider` | `CmsApiSource` | 用户导入的 JSON 接口配置 → 引擎源（搜索 / 详情 / 季集 / 播放源） |
| `PlayerEngine` | `MediaKitPlayerEngine`（kernelId `mediakit`） | media_kit 解码内核 → 引擎播放抽象 |
| `StorageAdapter` | `AnikumoLiuguangStorage` | App 的 Hive → 引擎落盘（一表一盒） |
| `SyncTransport` | 未接 | Anikumo 的同步走 App 自己的 GitHub 同步，引擎同步子系统在 App 内未注册 |

影视区页面只对 `VideoEngineService` 编程，它内部持有
`LiuGuangMediaEngine` 并把上述注册一次做齐（见 3.13）。
因为源接口交回来的是引擎模型、页面要的是 App 的展示模型，
字段互转集中在服务层完成，页面不直接碰引擎类型。

---

## 五、调用数据在哪

引擎不自带落盘位置：**凡是要留下来的数据，都写进宿主注入的
`StorageAdapter`**。表名一览（排查问题时按图索骥）：

| 数据 | 表 | 键与内容 |
|---|---|---|
| 播放历史 | `history` | 键 `媒体 id::集 id`，值 PlaybackHistory JSON（含续播点、completed） |
| 收藏 | `favorites` | 键 = 媒体 id，值 Favorite JSON（含媒体快照、revision、deviceId） |
| 收藏夹 | `collections` | 键 = 收藏夹 id（`col-<微秒戳>`），值 Collection JSON |
| 音轨延迟 | `audio_delays` | 键 `媒体 id::音轨 id`，值含 delayMs |
| 同步本地真相 | `sync_records` | 键 `集合::键`，值 SyncRecord JSON（含墓碑标记） |
| 同步发件箱 | `sync_outbox` | 待推送的集合 / 键索引 |
| 同步水位 | `sync_state` | 键 = 集合名，值含 lastPullAt |
| 下载任务 | `downloads` | 键 = 任务 id（含状态、字节进度、isHls、rangeFallback） |
| HLS 分片计划 | `download_segments` | 键 = 任务 id，值含分片地址、各片长度、已完成数 |
| 搜索结果缓存 | （内存） | 门面内置 LRU 64 条 / TTL 2 分钟，不落盘 |
| 通用缓存 | （内存） | `LruCache` 按调用方自建，默认 128 条 / TTL 5 分钟，带命中统计 |

**在 Anikumo 中的对应落点：**

- 注入的是 `AnikumoLiuguangStorage`，背后是 App 的 Hive：
  每张表一个盒，盒名为 `liuguang_<表名>`，值是 JSON 字符串。
- 下载的**文件本体**不在存储里：任务只记目标路径，
  成品与 `.part` 临时文件都在宿主给的下载目录（App 的下载管理页
  管理它们），HLS 分片拼接后的成品也是单个文件。
- 同步子系统在 Anikumo 内未注册（见 4.13），三张 sync 表在 App 里不会出现。
- 影视的接口配置清单、收藏检查的片源状态、TMDB / Bangumi 的账户会话
  归 App 自己的服务层管理，不经过引擎存储。

---

## 六、已知限制

以下每条都以代码为准，是「明确不支持 / 明确留给宿主」，不是缺陷待修：

- **HLS 加密分片不支持**：播放列表带 `EXT-X-KEY`（典型为 AES-128）时
  下载直接抛 `DownloadException` 并写明加密方式；主播放列表（master）
  与直播列表（无 `EXT-X-ENDLIST`）同样明确拒绝，不产出坏文件。
- **没有原生播放内核**：仓库只有 `PlayerEngine` 抽象与内存实现；
  mpv / Media3 / VLC 等真内核不在仓库内，嵌入时由宿主把自己现成的
  播放器适配进来（Anikumo 用 media_kit，见 4.13）。
- **同步不管传输**：`SyncEngine` 只做本地真相、发件箱、冲突裁决与重试；
  真实网络传输是宿主实现 `SyncTransport` 的事，引擎不内置任何
  HTTP / WebDAV 同步通道。
- **没有 UI**：本仓库不含任何界面与 Flutter 包；主题、页面、交互
  全部由宿主自理。插件体系里的 ui / theme 只是清单类型，不含组件。
- **插件不管装载执行**：plugin_api / plugin_manager 只做清单校验、
  版本范围、依赖与权限门禁；插件代码怎么打包、加载、运行由宿主决定，
  引擎不提供任意代码直装通道。
- **TMDB 适配器要自备 key**：无 key 抛 `TmdbNotConfiguredException`；
  适配器只映射电影 / 电视剧的基本资料与评分，不含季集端点。
- **匹配是启发式**：`TitleMatcher` 的 0.6 阈值与权重是经验值，
  冷门标题、同名异片仍可能误判；分数带 reasons 可查，
  宿主可在其上再加人工纠错。
- **存储版本**：导出 / 导入格式当前为 version 1，跨大版本迁移
  未做（版本不符直接抛错）；`JsonFileStorageAdapter` 是整库单文件，
  只适合小数据量，正式宿主应使用 Hive 实现。

---

## 七、目录结构与运行环境

```text
packages/
  liuguang_models/         媒体数据模型与搜索契约（Movie/TVSeries/Season/Episode/VideoSource…）
  liuguang_matcher/        标题规范化、季集抽取、匹配打分、去重指纹
  liuguang_network/        HttpClient 传输（重试/超时/Cookie 罐/取消/头脱敏）
  liuguang_subtitle/       SRT / VTT / ASS 解析为统一字幕时间轴
  liuguang_storage/        StorageAdapter 接口 + 内存 / JSON 文件实现
  liuguang_storage_hive/   Hive（hive_ce）实现，一表一盒
  liuguang_history/        播放历史与续播点仓库
  liuguang_favorites/      收藏与收藏夹仓库
  liuguang_cache/          LRU + TTL 缓存（命中统计）
  liuguang_source_sdk/     MediaSourceProvider 接口、描述符、清单
  liuguang_source_runtime/ 源注册表、请求闸门、健康检查、在途合并
  liuguang_metadata/       元数据聚合、字段优先级合并、去重、TMDB 适配器
  liuguang_search/         多源并发聚合搜索
  liuguang_player_api/     PlayerEngine 抽象、注册表、播放控制器、内存内核
  liuguang_audio/          音轨选择策略、音轨延迟存储、能力门禁
  liuguang_platform/       平台检测、能力矩阵、宿主路径注入、能力求交
  liuguang_plugin_api/     插件清单、版本范围、权限模型
  liuguang_plugin_manager/ 插件注册、启停、权限守卫
  liuguang_sync/           同步引擎（发件箱/增量/冲突规则/墓碑/重试）
  liuguang_download/       下载引擎（队列/Range 续传/HLS 分片拼接/持久化）
  liuguang_core/           LiuGuangMediaEngine 门面（唯一集成面）+ 全链示例
plugins/
  example_plugins/local_sample_source/   示例资源源（样本目录，可直接注册运行）
docs/
  API.md                   进程内 API 速览
```

运行环境：纯 Dart（`sdk: >=3.10.0 <4.0.0`），凡能跑 Dart 的地方都能用——
命令行工具、服务端、测试环境，以及经 Flutter 宿主嵌入移动 / 桌面 App。
除 `liuguang_storage_hive` 依赖 `hive_ce` 外，全部包零第三方运行时依赖。

在本仓库（Anikumo）中的位置：

- 引擎副本：`packages/liuguang_*`（21 包 vendored；副本与独立仓库
  不自动同步）
- App 侧宿主与适配：`lib/services/liuguang/`
  （`video_engine.dart` / `cms_api_source.dart` /
  `mediakit_player_engine.dart` / `liuguang_hive_storage.dart` 等）

构建与自检（引擎仓库内）：

```bash
for p in packages/* plugins/example_plugins/local_sample_source; do
  (cd $p && dart pub get && dart analyze && dart test)
done
cd packages/liuguang_core/example && dart pub get && dart run main.dart
   # 全链示例：搜索 → 详情 → 季集 → 播放源 → 内存内核播放 → 续播 → 收藏
```

---

## 八、开源信息

- 流光 LiuGuang 独立仓库未单独附许可证文件；在 Anikumo 中以 vendored
  副本形式随应用一同分发，Anikumo 应用整体采用 **GPL-3.0** 开源，
  见仓库根目录 `LICENSE`。
- 引擎只做接口适配、数据聚合与框架服务，不托管、不分发任何受版权
  保护的内容；使用者导入的接口配置与访问的内容由其自行负责，
  详见《免责手册》。
- 界面中展示影视元数据时对数据来源有署名（见 App 内「致谢」与官网说明）；
  TMDB 适配器需要使用者自备 API key，并遵守 TMDB 的使用条款。
