# MangaKit 手册

MangaKit 是 Anikumo 漫画区使用的**自研漫画 JavaScript 源框架引擎**：
独立项目、零依赖、单文件 bundle、宿主能力靠注入。它负责把漫画源定义
（自主 API 源，或经兼容层接入的旧框架风格源文件）执行成统一的
探索 / 搜索 / 详情 / 章节 / 图片数据，供 App 漫画区展示。

- 引擎本体：独立 JS 框架库（ES Modules 源码），当前版本 **0.1.0**，桥协议 **v1**。
- 在 Anikumo 中以单文件形式内置：`assets/mangakit/mangakit.js`（由框架源码打包生成，
  加载后全局名为 `MangaKit` 与 `Manga`），在 App 内置的 QuickJS 运行时中执行。
- 本手册内容：普通用户用法、**工作原理与运行机制**、SDK 调用详解、
  调用数据存放位置、兼容范围与已知边界、开源信息。

---

## 一、这是什么

**MangaKit 是 Anikumo 作者自研的一个漫画 JavaScript 源框架**，与小说引擎
墨源（MoYuan）同一种项目形态：独立目录、独立版本、独立测试集，先有独立框架、
后经宿主侧胶水层接入 Anikumo（漫画区自 B198 起以它为 JS 引擎，漫画设置里
可与旧引擎自由切换，两边共用同一份源数据与登录态）。

它与墨源的分工不同：墨源是「规则说明书执行器」（源是一组解析规则），
MangaKit 是「源代码托管框架」——**源本身就是一段 JS 程序**，框架负责
注册校验、生命周期、统一分发、数据归一化、网络治理与错误定界，
源只管按接口面写逻辑。框架本身不内置、不提供任何漫画源与内容，
源由用户自行导入，内容版权归原站与原作者所有。

主要能力：

- 自主源 API：`Manga.defineSource({...})` 一次定义搜索、探索、详情、章节、
  图片、分类、缩略图、账号与设置，框架统一分发与归一化
- 兼容层（独立模块）：旧框架风格源文件（`class X extends ComicSource`）
  可直接注册运行；不兼容面在注册诊断里明示，不静默吞
- 宿主靠注入：宿主只提供一个桥对象（http / store / cookies / ui / image / log），
  框架核心不 import 任何宿主代码，桥签名定死、协议带版本
- 网络治理：按站点限流闸、GET 短缓存与在途合并、探索分节并发与渐进上屏、
  刷新守卫、验证墙检测与「用户过墙后自动重放」
- 全套错误码与生命周期：源状态机、调用预算、诊断信息（状态 / 初始化错误 /
  调用与失败计数）都可经管理面读出

---

## 二、在 Anikumo 里怎么用

普通读者不需要接触框架本身，只需要漫画源：

1. **导入**：漫画区 → 源管理页导入源文件（旧框架风格源经兼容层注册，
   自主 API 源直接注册）。注册时框架先校验源清单再跑初始化，
   校验不过或初始化失败的源会停在 failed 状态并记录原因，不会半残运行。
2. **管理与设置**：源在定义里声明的设置项（线路、接口地址、画质等）由 App 渲染，
   在源管理页里就地改，改完即生效并持久化；带 callback 的设置项（如
   「清除设备信息」类按钮）也可直接触发。
3. **排查**：某个源搜不到、章节为空、图片打不开时，用诊断看该源的
   状态、初始化错误与最近一次调用错误——框架的错误都是带码的
   （如 `MK_INIT_FAILED`、`MK_VERIFICATION_REQUIRED`），反馈时附上错误码最有效。
4. **阅读**：图片页返回的不只是图片地址，还带每张图的请求头与钩子标记
   （字节变换 / 解扰 / 失败换线），阅读器的图片管线按标记执行；
   封面另有缩略图钩子通道，封面需要二次加工的源也能正确显示。
5. **撞墙时**：源站弹出人机验证时，App 会打开验证页让你本人完成验证，
   过关后框架带新 Cookie 自动重放刚才的请求，不用手动重进；
   框架本身永不自动代答验证码（无 OCR、无打码服务），这是定死的边界。

漫画区的扩展功能在「漫画设置 → 扩展功能」（功能仓库）里按需安装：
章节导出 CBZ、阅读滤镜、条漫自动滚动、深度预读都在那里，
没安装时对应入口在区内完全不存在。引擎切换在「漫画设置 → 漫画引擎」，
MangaKit（默认）与旧引擎共用同一持久化存档，切换不丢源与进度。

---

## 三、工作原理与运行机制

### 3.1 总览：它到底在做什么

一句话原理：**漫画源 = 一段实现了约定接口面的 JS 程序；MangaKit 是这段程序的
托管运行时**。它自己不存内容、不认识任何具体网站，只做五件事：
校验并激活源 → 接受宿主调用并分发 → 给源一个只能经桥出门的能力面（ctx）→
把源的返回值归一化成统一结构 → 把一切失败翻译成带码的错误。

分层结构（自下而上）：

| 层 | 职责 |
|---|---|
| 宿主注入层 | 宿主提供的桥对象六组函数（http / store / cookies / ui / image / log），框架不自带 |
| 桥层 | 桥协议 v1 信封编解码、通道超时、宿主缺失与失败的定界（`core/bridge.js`） |
| 网络层 | Cookie 附加/回存、GET 缓存与在途合并、按站点限流闸、验证墙检测与重放（`network/http.js`） |
| 解析层 | 内置 HTML 解析与选择器、Convert 编解码/哈希/AES（`parser/`） |
| 数据层 | 清单校验与全部返回值的归一化（`core/validate.js`） |
| 源执行层 | 注册表与生命周期状态机、统一分发器（预算、刷新守卫、分节并发）（`source/`） |
| 兼容层 | 旧框架风格源的全局垫片与形状翻译，独立模块、核心零感知（`compat/venera.js`） |

### 3.2 一次搜索的全过程

以在 Anikumo 里用某个源搜一部漫画为例，框架内部依次发生：

1. **分发**：宿主调 `kit.call(key, 'search', { keyword, page })`，分发器先查
   刷新守卫（见 3.6）——2 秒内同参的重复调用直接复用同一次执行，不重复打站点。
2. **状态检查**：源不在 ready 状态直接拒绝：failed 给 `MK_INIT_FAILED`
   并附初始化错误原文，其他中间状态给 `MK_NOT_INITIALIZED`；
   每次调用分配一个 callId（形如 `源key#序号`），贯穿日志与错误对象。
3. **备 ctx**：为这次调用构造调用级 ctx（能力面见 3.5），设置快照、
   本源 key、callId 都就位。
4. **执行**：在该 kind 的时间预算内（search 为 30 秒，见 4.2）运行源的
   search 处理函数。源经 `ctx.http` 发的每个请求都过网络层：
   先过限流闸排队，再经桥到宿主传输，回程的 Set-Cookie 回存宿主 Cookie 罐。
5. **归一化**：源返回的列表（数组或 `{items|comics|list}` 等形状）逐条过
   `normalizeComic`：字段别名收敛、无 id 的条目丢弃、原始对象完整保留在 `raw` 里；
   形状整体不对不是返回空列表，而是抛 `MK_BAD_RESULT`——源写错了要能看出来。
6. **错误定界**：源抛出的任何值（字符串、Error）在分发器边界被包装成
   `MK_SOURCE_THROW` 并保留原文；消息像验证墙的会被归类为
   `MK_VERIFICATION_REQUIRED`，宿主据此统一走过墙流程。
7. **返回**：归一化后的 `{ items, hasMore, maxPage }` 交回宿主；
   调用计数、失败计数、最近错误同步记在源条目上，诊断随时可读。

详情、章节、图片、分类是同一套机制换 kind 与归一化器：
详情可同时带章节列表与推荐，章节支持分组形状展平（见 3.4），
图片页保留每张图的请求头与三个钩子标记原样透传给宿主图片管线。

### 3.3 源如何被校验与激活（生命周期）

源注册不是「登记即用」，要过两道门：

- **清单校验**：`Manga.defineSource(def)` 或 `engine.registerSource(def)` 时，
  先由 `validateManifest` 生成清单：`key` 必填且须匹配 `^[A-Za-z0-9_.-]+$`，
  `name` 缺省取 key，`version` 缺省 `0.0.0`；再按定义里实际存在的处理函数
  生成能力集（search / explore / details / chapters / pages / categories /
  category / thumbnails / settings / account / favorites / comments /
  imageOnResponse / imageModify / imageFallback）。清单不合格抛
  `MK_BAD_MANIFEST`；同 key 重复注册抛 `MK_SOURCE_EXISTS`。
- **初始化**：清单通过后执行源的 `init(ctx)`（若有），预算 **15 秒**；
  成功进 ready，失败或超时进 **failed** 并记录错误原文——源留在注册表里
  可诊断、可 `reinit(key)` 重试，而不是静默消失或半残运行。

状态机（实现态）：`registered → initializing → ready / failed → disposed`
（`removeSource` 后）。调用 failed 源得到 `MK_INIT_FAILED`，
其余依此类推，宿主与测试只认状态与错误码、不猜消息文本。

### 3.4 返回值如何被归一化

分发器是唯一出口：源返回什么形状是源的自由，**宿主拿到的永远是归一化结构**。
归一化器（`src/core/validate.js`）的口径：

- **comic（条目）**：`id` 依次取 `id / comicId / path_word / slug`，
  `title` 取 `title / name`，`cover` 取 `cover / coverUrl / thumb`，
  `author` 可为字符串或数组（数组以 `, ` 拼接），`description` 取
  `description / brief / intro`，`updatedAt` 取 `updatedAt / datetime_updated / lastUpdate`，
  `tags` 取 `tags / tagList / themes`（元素可为字符串或 `{name|title|id}`）。
  **没有 id 的条目被丢弃**；有 id 但标题为空的条目保留（个别源返回别名表、
  标题由宿主侧补）。原始对象完整保留在 `raw`，框架不认识字段不丢。
- **状态**：`status` 归一为 `ongoing / completed / hiatus / cancelled`——
  英文原词与中文「连载中 / 完结 / 已完 / 腰斩」等写法都会被识别。
- **分页**：数组、`{items|comics|list|results}`、带 `hasMore / maxPage / total`
  的对象均可；`hasMore` 可由 `total` 与已取条数推导。
- **章节**：扁平数组、`{章id: 标题}` 映射、分组对象
  `{组名: {章id: 标题} | [章]}` 都接受，分组展平时标注 `group` 并保序；
  章节字段含 `id`（别名 `epId / chapterId / key`）、`title`（缺省取 id）、
  `order`（缺省为序号）、`time`。
- **详情**：comic 字段 + 可选 `chapters`（别名 `eps / episodes`，同样过章节归一化）
  与 `recommendations`（别名 `recommend / related`）。
- **图片页**：`{images|pages|list}` 或裸数组；元素为字符串即 `{url, headers: {}}`，
  为对象时取 `url`（别名 `src`）、`headers`，并透传三个钩子标记
  `transformOf / modifyCode / fallbackOf`（含义见 4.9）。
- **分类**：`[{name|title, id|key|param, group}]`、纯字符串列表、
  分组对象 `{组名: [...]}` 都归一为 `{name, id, group}`（id 缺省取 name）。

### 3.5 ctx 能力面：源唯一的外出通道

源代码不得直接接触宿主——它能碰到的只有处理函数的第一个参数 `ctx`，
而 ctx 的每项能力最终都经桥出门（见 3.10 的信封）。能力面全表见 4.6，
这里强调三条纪律：

- **网络只有一条路**：`ctx.http` 经框架网络层（限流、缓存、Cookie、验证墙）
  再经桥到宿主传输；源自己拼的任何「捷径」不存在。
- **存储按源隔离**：`ctx.data`（源私有数据）与 `ctx.prefs`（源设置）经桥存储的
  两个桶读写，信封里强制带 sourceKey，宿主实现必须按它分桶——
  一源无法读写他源数据，这是桥的契约而不是约定俗成。
- **设置同步可读**：`ctx.setting(key)` / `ctx.settings` 是注册时就位的快照
  （架构默认值 ← 存储值覆盖），init 阶段就能读到正确值；
  `ctx.prefs.set` 写穿到存储并同步更新快照。

### 3.6 网络层怎么工作（提速与防封都在这层）

传输本身是宿主的事（桥 `http.request`，重定向由传输层跟随），
框架网络层（`src/network/http.js`）在传输之上加了四件套，
状态按桥共享——每次调用新建的 HttpClient 共用同一份缓存与闸门：

- **限流闸（RequestGate）**：同一站点（origin）同时在飞请求 ≤ **3**、
  全局 ≤ **12**、同源相邻请求启动间隔 ≥ **20ms**，超额 FIFO 公平排队
  （不跨站点队头阻塞）。突发并发是被站点 403/封禁的头号原因，闸只套
  网络交换本身，不套验证的人工等待。默认值可经
  `createMangaKit({ httpGate: { perOrigin, global, minIntervalMs } })` 调。
- **GET 短缓存**：只缓存无 body 的 GET、只缓存状态 200、正文 ≤ 512KB、
  缓存键 = 网址 + **全部请求头**（带不同 Cookie 的同一网址绝不共用条目）、
  **带 Set-Cookie 的响应永不缓存**（它在轮换会话，重放旧副本会让源拿到过期罐状态）；
  TTL **5 秒**、最多 64 条、超容淘汰最旧。
- **在途合并**：同一缓存键的并发请求只发一次，其余调用共享同一 Promise。
- **重试**：GET 在传输失败时自动重试 **1 次**（仅 GET、可用 `opts.retry: false` 关）。

分发器侧另有**刷新守卫**：explore / search / category 在 **2 秒**内同参重复调用
直接复用同一次执行（进行中或刚完成都算），宿主在真正的下拉刷新手势时
传 `refresh: true` 强制重跑；带 `onSection` 的流式探索不走守卫。
探索的分节形态（`explore` 写成 `[{title, load}]` 数组）由 **4 个并发工人**
分节加载、保序拼装，每节落地即经 `args.onSection(section, index)` 渐进回调
宿主上屏——探索页不用等最慢的一节。

宿主侧决定速度的另一条：**传输必须复用连接**（长-lived 客户端 / 连接池），
每请求新建客户端会让每次调用都付一次 TCP+TLS 握手。参考宿主已按此实现。

### 3.7 验证墙：检测、用户过墙、自动重放

站点越来越常把漫画页挡在 Cloudflare 挑战或验证码表单后面。框架的立场是
**只检测、只转交、永不代答**（无 OCR、无打码服务，定死的产品线）：

1. **检测**：响应落在 401 / 403 / 429 / 503 且正文前段命中墙标记
   （`cf-challenge`、`challenge-platform`、`just a moment`、`g-recaptcha`、
   `安全验证`、`请输入验证码`、`滑块验证` 等），或 200 但命中最强标记时，
   判定为验证墙并区分 `cloudflare` / `captcha` 两类。
2. **转交**：经桥 `ui.solveVerification({url, kind, status})` 请宿主打开
   WebView 让**用户本人**完成验证，宿主把过关后站点下发的 Cookie 种回
   自己的 Cookie 罐（即 `cookies.set` 那条路），返回 `{solved: true}`。
   同一站点 20 秒内不重复打扰（冷却窗）。
3. **重放**：过墙成功后框架带新 Cookie **自动重放原请求一次**（绕过缓存）；
   重放仍撞墙则抛 `MK_VERIFICATION_REQUIRED`。宿主没有实现该 UI 时，
   墙页原样交回源处理，源抛出的验证类错误在分发器边界同样被归类为
   `MK_VERIFICATION_REQUIRED`——宿主永远能用一个错误码统一处理。

### 3.8 兼容层怎么工作（旧框架风格源）

兼容层（`src/compat/venera.js`）是与核心解耦的独立模块，核心里没有它的任何概念：

1. **求值**：把源文件代码在装好兼容全局的环境里执行——
   `ComicSource / Network / Convert / HtmlDocument / APP / randomInt /
   createUuid / getRandomText / fetch` 都由兼容层提供并映射到 ctx 能力面；
   源 `class X extends ComicSource` 的实例被收集起来。
2. **翻译**：实例的字段与方法被包装成一个自主 API 定义
   （search / explore / details / chapters / pages / categories / category /
   thumbnails / account / 设置等逐项对应），再走与自主源完全相同的
   注册、校验、分发与归一化通道。
3. **诊断**：注册返回 `{ manifest, diagnostics }`，其中
   `diagnostics.unmappedSurfaces` 如实列出实例用到了但未映射的面
   （favorites、comments 等，见第六章）——不兼容摆在明面上，不静默吞。
4. **刻意的语义差异**（兼容层文件头写明）：`loadData / loadSetting` 在原 API 里
   是同步的，兼容层在注册时预载该源的数据桶与设置快照到内存、同步读、
   异步经桥落盘；`init()` 失败降级为**警告**而非注册失败（不少真源在 init 里
   探测域名）；Convert 的字节类结果返回 ArrayBuffer；Network 调用绑定到
   当前正在执行的源（与原运行时一致）。

Node 宿主有一个已知坑：兼容层会安装源侧 `fetch` 全局，宿主自己的传输
必须在注册任何源**之前**捕获原生 `fetch`，否则会递归进源侧 shim
（项目 `tests/mock_host.js` 即如此处理，文件头有注释）。

### 3.9 单文件打包原理

框架源码是十余个 ES Module 文件，QuickJS 宿主没有模块加载器，所以打包器
（`tools/build-bundle.mjs`）做了一次刻意小型的 **ESM → 模块注册表**改写：
每个源文件包成一个 `__define` 注册项、具名 import（含 `A as B` 别名）与
export 列表、re-export 改写为注册表查找；超出可处理写法的 import 形式
直接让构建报错——`src/` 的写法被约束在变换器能处理的子集内
（只用具名导入、顶层导出声明、导出列表）。产物 `dist/mangakit.js`
（约 140KB）无 import/export 残留、不假设 DOM / Node / `fetch`，
文件求值后在全局挂出 `MangaKit`（引擎 API）与 `Manga`（源侧命名空间）两个名字。
bundle 有独立测试锁定：在无 Node API 的裸 vm 上下文里能加载、
能注册源、能完成搜索。

裸运行时还缺两样东西，bundle 侧由入口垫片补齐：QuickJS 没有 `setTimeout` 时，
`installTimerShim` 让框架定时器骑宿主桥的 `delay(ms)`；没有 `console` 时，
`installConsoleShim` 把 `console.*` 路由到宿主日志通道（源里随手写的
console.log 不会让运行时崩）。Node 环境两者都不动。

### 3.10 在 Anikumo 里的宿主结构

- 引擎文件：App 资源 `assets/mangakit/mangakit.js`（与框架仓库
  `dist/mangakit.js` 内容一致、md5 相同），由生产宿主
  `mangakit_host.dart`（`lib/services/manga/js/`）持有 QuickJS 运行时并加载；
  运行时在独立 isolate 中运行并带死亡自愈（B253）。
- 宿主在加载 bundle **之前**把桥对象挂到全局 `__mangakitHost`：
  http 走 App 自己的网络栈、store / cookies 背后是与旧引擎共用的
  KV / Cookie 持久化条目——源数据、设置与登录态从旧引擎无损沿用。
- 图片钩子的同步通道 `__mkImageSync` 由宿主的图片注册表实现
  （`mangakit_image_registry.dart`），解码后的图片留在宿主侧，
  兼容层的 `Image` 类经它做裁剪、旋转、叠合等操作（op 协议见 4.9）。
- 业务侧由 `MangaKitMangaSource`（`mangakit_source.dart`）把框架的统一调用面
  映射到 App 的 `MangaSource` 契约，漫画区其余代码只认契约、不认引擎；
  这也是旧引擎能与 MangaKit 并存切换的原因——两者实现同一契约、共用同一存档。

---

## 四、SDK 调用详解

### 4.1 初始化

宿主两种接法等价：加载 bundle 前设全局 `__mangakitHost`（bundle 自动以它建引擎），
或模块化导入后显式创建：

```js
import { createMangaKit } from 'mangakit/src/index.js';   // Node / 打包器
const kit = createMangaKit({ host, appVersion, platform, httpGate, refreshGuardMs });
```

| option | 说明 |
|---|---|
| `host` | 桥对象（见 4.10）；省略时取全局 `__mangakitHost`，再省略则为 null（用到桥的调用抛 `MK_HOST_MISSING`） |
| `appVersion` / `platform` | 透传给兼容层（源侧 `APP` 信息），自主源不用 |
| `httpGate` | 限流闸参数 `{ perOrigin = 3, global = 12, minIntervalMs = 20 }`，见 3.6 |
| `refreshGuardMs` | 刷新守卫窗口，默认 2000；设 0 关闭 |

`createMangaKit` 返回的 API 对象（bundle 模式下即全局 `MangaKit`）：

```js
kit.version                       // 框架版本 '0.1.0'
kit.engine                        // MangaKitEngine（管理面全量，见 4.5）
kit.compat                        // VeneraCompat（兼容层，见 4.11）
kit.call(key, kind, args)         // 统一调用（engine.call 的直达）
kit.registerSource(def, opts)     // 注册自主源 → Promise<manifest>
kit.registerVeneraSource(code)    // 注册兼容源 → Promise<{manifest, diagnostics}>
kit.listSources()                 // 已注册源清单（含状态与计数）
kit.diagnostics(key)              // 单源诊断（见 4.5）
kit.Convert / kit.parseHtml       // 工具直达（同 ctx.convert / ctx.html 的实现）
```

全局 `Manga` 只有两项：`Manga.defineSource(def)`（= `kit.registerSource(def)`，
供源文件自注册）与 `Manga.version`。

### 4.2 核心调用

一切业务调用都走 `kit.call(key, kind, args)`，返回 **Promise<归一化数据>**。
kind 全表（括号内为该 kind 的**调用预算**，超时抛 `MK_TIMEOUT`）：

| kind | args | 返回 |
|---|---|---|
| `search`（30s） | `{ keyword, page = 1, options = [], refresh? }` | `{ items, hasMore, maxPage }` |
| `explore`（30s） | `{ page = 1, onSection?, refresh? }` | `{ sections: [{ title, items }] }` |
| `details`（60s） | `{ id }` | comic 字段 + `chapters`（可为 null）+ `recommendations` |
| `chapters`（60s） | `{ id }` | `{ chapters: [...] }` |
| `pages`（60s） | `{ comicId, chapterId }` | `{ images: [...] }` |
| `categories`（30s） | `{}` | `{ categories: [{ name, id, group }] }` |
| `category`（30s） | `{ category, param, page = 1, options = [], refresh? }` | `{ items, hasMore, maxPage }` |
| `thumbnails`（30s） | `{ id }` | `{ images: [url, ...] }`（封面钩子通道） |
| `account`（15s） | `{}` | `{ hasLogin, hasLogout, isLoggedIn, registerWebsite }` |
| `login`（180s） | `{ username, password }` | `{ ok: true }` |
| `logout`（15s） | `{}` | `{ ok: true }` |
| `imageOnResponse`（60s） | `{ mode, of, id, ep, bytesB64 }` | `{ ok, bytesB64 }` |
| `imageModify`（60s） | `{ code, bytesB64 }` | `{ ok, bytesB64 }` |
| `imageFallback`（30s） | `{ of, id, ep }` | `{ image }`（归一化后的单图或 null） |

源没实现对应 kind 时抛 `MK_UNSUPPORTED_KIND`（`account` 例外：无 account 声明时
返回全 false 的能力面而不是抛错）。典型全链：

```js
const found = await kit.call('my_source', 'search', { keyword: '海贼王', page: 1 });
const detail = await kit.call('my_source', 'details', { id: found.items[0].id });
const chs = detail.chapters ?? (await kit.call('my_source', 'chapters', { id: detail.id })).chapters;
const pages = await kit.call('my_source', 'pages', { comicId: detail.id, chapterId: chs[0].id });
```

### 4.3 返回结构（统一数据契约）

```text
Comic（列表条目 / 详情基础）:
  { id, sourceKey, title, subtitle, author, cover, coverHeaders, coverTransformOf,
    description, status('' | ongoing | completed | hiatus | cancelled),
    tags[], rating(number | null), updatedAt, raw }
Details = Comic + { chapters: Chapter[] | null, recommendations: Comic[] }
Chapter:
  { id, title, group, order, time, raw }
PageImage:
  { url, headers, transformOf, modifyCode, fallbackOf, raw? }
    （字符串来源的图只有 url 与空 headers、无 raw）
Category:
  { name, id, group }
分页结果:
  { items: Comic[], hasMore, maxPage(number | null), raw }
```

`raw` 是源返回的原始对象原样保留：框架不认识的字段只进 `raw` 不丢失，
宿主需要源特有字段时从 `raw` 取。归一化口径（别名、丢弃规则）见 3.4。

### 4.4 约定与错误码

- 公开调用全部返回 Promise，成功即数据本身，不包装 `{ok, data}`。
- 一切跨分发器边界的失败都是 `MkError`：
  `{ name: 'MkError', code, message, sourceKey, callId, kind, cause }`
  （`toJSON()` 给出同形序列化，cause 只留消息摘要）。**断言与分支只认 code**。
- 源里抛出的任何值（字符串 / Error）都被包装为 `MK_SOURCE_THROW` 并保留原文；
  消息命中验证墙特征的改判 `MK_VERIFICATION_REQUIRED`。

| 错误码 | 含义 |
|---|---|
| `MK_BAD_MANIFEST` | 源定义不合格（非对象、key 非法等） |
| `MK_BAD_RESULT` | 源返回值形状不对（无列表、无图等），不静默返回空 |
| `MK_SOURCE_NOT_FOUND` | key 未注册（或已移除） |
| `MK_SOURCE_EXISTS` | 同 key 重复注册 |
| `MK_NOT_INITIALIZED` | 源不在 ready 状态（注册中 / 初始化中） |
| `MK_INIT_FAILED` | init 失败或超时（15s）；调用 failed 源也给此码并附 init 错误 |
| `MK_UNSUPPORTED_KIND` | 源未实现该 kind（或设置项无 callback） |
| `MK_SOURCE_THROW` | 源代码抛错的统一包装 |
| `MK_HOST_MISSING` | 宿主未提供所用到的桥函数（源不用的能力可以不实现） |
| `MK_HOST_CALL_FAILED` | 桥调用本身抛错的包装 |
| `MK_HTTP_FAILED` | 宿主 http 回复形状不对等传输层失败 |
| `MK_TIMEOUT` | 调用预算或桥通道超时 |
| `MK_CANCELLED` | 调用被取消（预留码） |
| `MK_COMPAT_INCOMPATIBLE` | 兼容层判定源不兼容 |
| `MK_VERIFICATION_REQUIRED` | 撞上验证墙且未能过墙（见 3.7） |

### 4.5 源管理（`kit.engine`）

```js
await kit.registerSource(def);                    // 校验 → 建快照 → 回填存储设置 → init
await engine.reinit(key);                         // 对 failed 源重试 init，返回新状态
engine.removeSource(key);                         // 标记 disposed 并注销，返回是否曾存在
kit.listSources();
   // [{ key, name, version, description, url, minFrameworkVersion, capabilities[],
   //    state, initError, callCount, failureCount, lastError }]
kit.diagnostics(key);
   // listSources 字段 + initializedAt + settingsSchema；未注册返回 null
engine.settingsSchema(key);                       // 该源的设置架构（见 4.7）
await engine.writeSetting(key, name, value);      // 落桥存储 → 改快照 → 触发 def.onSettingChange
await engine.invokeSettingCallback(key, name);    // 触发 callback 型设置项，返回 { ok: true }
engine.setHost(host);                             // 事后换/补桥对象
engine.logger.tail(100);                          // 框架日志（环形 500 条，见 4.12）
```

注册流程里设置快照的就位顺序是刻意的：**先建快照（架构默认值）→ 再用桥存储里
的用户值逐项覆盖 → 最后才跑 init**，保证 init 阶段读到的就是最终设置。

### 4.6 写一个自主源

源是一个 JS 对象（或在 QuickJS 宿主里以 `Manga.defineSource({...})` 自注册的文件）。
所有处理函数第一个参数都是 `ctx`；也可以写成 `{ load: async (...) => ... }` 形式
（explore 还可写成分节数组，见下）。

```js
Manga.defineSource({
  key: 'my_source',          // 必填，[A-Za-z0-9_.-]+
  name: '我的源',
  version: '1.0.0',
  description: '……',         // 可选；另有 url / minFrameworkVersion 可选字段

  settings: {                // 可选，设置架构见 4.7
    quality: { title: '画质', type: 'select',
               options: [{ value: '800', text: '低' }, { value: '1200', text: '高' }],
               default: '1200' },
  },
  account: {                 // 可选
    login: async (ctx, { username, password }) => {},
    logout: async (ctx) => {},
    isLoggedIn: async (ctx) => true,
    registerWebsite: 'https://…',
  },

  init:     async (ctx) => {},                                       // 可选，一次，15s 预算
  search:   async (ctx, { keyword, page, options }) => ({ items, hasMore }),
  explore:  async (ctx, { page }) => ({ '推荐': [comic], '热门': [comic] }),
            // 或分节数组 [{ title, load: async (ctx, { page }) => ... }]，分节并发+渐进回调
  details:  async (ctx, { id }) => ({ id, title, chapters }),
  chapters: async (ctx, { id }) => [{ id, title }],
  pages:    async (ctx, { comicId, chapterId }) => ({ images }),
  categories: async (ctx) => [{ name, id, group }],
  category: async (ctx, { category, param, page, options }) => ({ items, hasMore }),
  thumbnails: async (ctx, { id }) => [url, ...],
  onSettingChange: async (ctx, { key, value }) => {},                // 可选
});
```

返回值形状自由度与归一化口径见 3.4 / 4.3。官方示例在框架仓库 `examples/native_source.js`
（一个对 JSON API 的完整源：搜索 / 详情 / 章节 / 图片 + 画质设置）。

`ctx` 能力面全表：

| 能力 | 说明 |
|---|---|
| `ctx.http.get(url, opts)` / `post(url, opts)` / `request(method, url, opts)` | 经框架网络层与宿主桥发请求；Cookie 由宿主罐自动附加/回存。opts：`headers / data / bytes / cookies: false / timeout / retry: false / cache: false`。响应 `{ status, headers, body, text(), json(), bytes() }` |
| `ctx.http.fetchBytes(url, opts)` | 取二进制（响应经 base64 过桥），返回 Uint8Array |
| `ctx.html(html)` / `ctx.parseHtml(html)` | 内置 HTML 解析 + 选择器（tag / .class / #id / [attr] / 后代 / 子级 / :nth-child 等子集）；元素有 `text / innerHTML / outerHTML / attributes / classNames / getAttribute / querySelector(All) / getElementById` |
| `ctx.convert` | `encodeUtf8 / decodeUtf8 / encodeBase64 / decodeBase64 / hexEncode / hexDecode / encodeHtml / decodeHtml / md5 / sha1 / sha256 / hmac / hmacString / encryptAesEcb / decryptAesEcb / encryptAesCbc / decryptAesCbc`（全纯 JS 实现，字节为 Uint8Array） |
| `ctx.data.get/set/delete(k)` | 源私有持久数据（data 桶，按源隔离，异步，经桥存储，值走 JSON） |
| `ctx.prefs.get/set/delete(k)` | 源设置（settings 桶）；`set` 同步更新设置快照 |
| `ctx.setting(key)` / `ctx.settings` | 当前设置快照同步读 |
| `ctx.log(level, msg)` | 写框架日志（并转发宿主日志通道，失败不影响源） |
| `ctx.toast(msg)` | 宿主 UI 吐司（宿主可选实现，未实现时静默） |
| `ctx.key` | 本源 key |

### 4.7 设置架构

源在 `settings` 里以对象声明设置项（宿主只拿架构渲染、框架不含任何 UI）：

```js
settings: {
  quality: { title: '画质', type: 'select',           // 'select' | 'switch' | 'input' | 'callback'
             options: [{ value, text }], default: '1200',
             validator: '…', buttonText: '…',        // 可选
             callback: async (ctx) => {} },          // type 为 callback 时的动作
}
```

`engine.settingsSchema(key)` 返回可渲染的架构数组（每项
`{ key, title, type, options, default, validator, buttonText, hasCallback }`，
callback 函数本体不外泄）。写值走 `engine.writeSetting`：
先落桥存储的 settings 桶（JSON 字符串），再原地改快照（兼容层与存量 ctx 持有
同一引用、必须立刻看到新值），最后触发源的 `onSettingChange(ctx, { key, value })`。

### 4.8 账号

账号能力声明在定义的 `account` 对象里，分发器提供三个 kind（见 4.2）：

- `account`：只读能力面——`hasLogin / hasLogout` 按函数是否存在判定，
  `isLoggedIn` 调源的 `account.isLoggedIn(ctx)`（没声明时为 false），
  `registerWebsite` 原样带出。源没声明 account 时返回全 false，不抛错。
- `login`：把 `{ username, password }` 透传给 `account.login(ctx, {...})`，
  预算放宽到 180 秒（登录常带验证码人工环节）；凭据只透传给源逻辑，
  框架与日志均不记录其值。
- `logout`：调 `account.logout(ctx)`。两者未实现时抛 `MK_UNSUPPORTED_KIND`，
  成功统一返回 `{ ok: true }`。

登录态本身（Cookie / 令牌）活在宿主 Cookie 罐与源的 data 桶里（见第五章），
框架不另存凭据。

### 4.9 图片钩子

阅读器图片管线有两条钩子通道，分工不同：

- **标记透传（pages 结果）**：源给某张图带上 `transformOf`（字节变换的源图 id）、
  `modifyCode`（解扰代码）、`fallbackOf`（失败换线的原图 id）三个不透明标记，
  归一化原样保留，宿主图片引擎按标记执行——框架只负责保全信息、不执行变换。
  封面同理有 `coverTransformOf`，封面二次加工经 `thumbnails` kind 触发。
- **钩子执行（三个 kind）**：源若实现了 `imageOnResponse / imageModify / imageFallback`
  处理函数，宿主以 4.2 的三个 kind 驱动它们对图片字节做实际处理
  （入参/出参均为 base64 字节）。兼容层里这三个钩子对应旧框架风格源的
  onImageLoad / modifyImage / onLoadFailed，其 `Image` 类经同步通道
  `globalThis.__mkImageSync(json) -> json` 操作宿主侧的解码注册表，
  op 包括 `createFromBytes / encode / copyRange / copyAndRotate90 /
  fillImageAt / fillImageRangeAt / getWidth / getHeight / emptyImage / releaseAll`，
  回 `{ ok, v, fmt }`。**宿主未注入该同步通道时，钩子 kind 干净失败、
  不产出错误像素**——宁可无图，不可错图。

### 4.10 宿主桥协议（桥协议 v1）

框架与宿主之间只有一条通道：桥对象按组提供函数（可同步可异步，框架统一 await），
框架的每一次外部调用都以信封形式发出：

```text
{ protocol: 1, channel: 'http.request', id, callId, sourceKey, payload }
```

`channel` 是 `组.方法`，`id` 为桥内序号，`callId` 贯穿分发器日志与错误对象，
`sourceKey` 是单源隔离的契约字段。桥通道自带超时：http 30s、store 5s、
cookies 5s、ui 不限（用户节奏）、image 30s、log 1s；函数缺失抛
`MK_HOST_MISSING`，函数抛错包装为 `MK_HOST_CALL_FAILED`。

| 组 | 函数 | payload → 返回 |
|---|---|---|
| `http` | `request(env)` | `{method, url, headers, data, bytes}` → `{status, headers, body, bodyB64?}`。`bytes: true` 时正文以 base64 回传；重定向由传输层跟随；`set-cookie` 以数组放在 `headers['set-cookie']` |
| `store` | `get(env)` | `{kind: 'data' \| 'settings', key}` → 字符串或 null（框架按 JSON 存取） |
| | `set(env)` / `delete(env)` | `{kind, key, value?}` → 任意 |
| | `all(env)`（可选） | `{kind}` → `{key: 字符串}`；兼容层注册时预载 data 桶用它。缺失时兼容层只能读到本会话写入的数据 |
| `cookies` | `get(env)` | `{url}` → Cookie 头字符串（宿主侧罐按 URL/域名管理） |
| | `set(env)` | `{url, cookies: [原始 set-cookie 串]}` |
| | `delete(env)` | `{url}` 清除该站 Cookie |
| `ui` | `toast(env)`（可选） | `{message}` |
| | `solveVerification(env)`（可选） | `{url, kind: 'cloudflare' \| 'captcha', status}` → `{solved: boolean}`，过墙流程见 3.7 |
| `image` | —（同步通道） | 不走异步桥：宿主注入同步函数 `globalThis.__mkImageSync`，见 4.9 |
| `log` | `write(env)`（可选） | `{level, message}` |
| （顶层） | `delay(ms)`（可选） | 裸运行时没有 setTimeout 时供框架定时器骑乘（见 3.9） |

安全约定：桥是唯一对外通道，宿主可以在桥上做 URL 白名单、流量审计与限速；
框架日志对 Cookie / Authorization 等头按名脱敏（见 4.12），宿主日志也应遵守
同一规则。单源数据按 `sourceKey` 隔离是桥的契约——store / cookies 的实现
必须以 `env.sourceKey` 分桶。

### 4.11 兼容层调用（旧框架风格源）

```js
const { manifest, diagnostics } = await kit.registerVeneraSource(codeText);
// diagnostics.unmappedSurfaces: ['favorites', 'comments', ...]（该源用到但未映射的面）
```

兼容层（`VeneraCompat`）给源侧装的全局与语义差异见 3.8。补充三点：

- 兼容源与自主源在注册表里无区别：同样的状态机、错误码、诊断与设置通道
  （设置经 `settingsRef` 机制：快照对象先建、注册时原地填入，init 之前就位，
  因为兼容源在 init 里就要同步读设置）。
- 兼容层内部同样经框架网络层发请求（源侧 `Network` 与 `fetch` 都落到
  `ctx.http` 同一条路），限流、缓存、验证墙对兼容源一视同仁。
- 注册即给结论：能映射多少、缺哪些面，当场在 diagnostics 里说清；
  运行期缺面同样以 `MK_COMPAT_INCOMPATIBLE` / `MK_UNSUPPORTED_KIND` 明示。

### 4.12 日志

框架日志是定长环形缓冲（`MkLogger`，默认 **500 条**），字段
`{ seq, at, level, tag, message, extra? }`，宿主经 `engine.logger.tail(n)` 取尾部；
分发、桥、网络、源（`source:<key>`）都有各自 tag，callId 贯穿。
写日志前对请求头按名脱敏：`cookie / set-cookie / authorization / x-api-key / token`
一律替换为 `<redacted>`——日志里永远出现不了 Cookie 与凭据值。
源的 `ctx.log` 与裸运行时的 `console.*` 都汇入同一通道（并转发宿主 `log.write`，
转发失败被吞掉，日志永不拖垮源）。

---

## 五、调用数据在哪

框架本体只在内存里持有注册表、设置快照、缓存与日志；**凡是要留下来的数据，
都经桥写到宿主侧**。逐项落点：

| 数据 | 存放位置 |
|---|---|
| 源定义（注册表） | 引擎内存；持久化由宿主负责——Anikumo 侧源文件与清单存在 App 的漫画源存档里（与旧引擎共用同一份，引擎切换不丢） |
| 源设置（用户值） | 桥存储的 `settings` 桶：键为设置项名、值为 JSON 字符串；注册时回填快照，`writeSetting` / `ctx.prefs.set` 写穿 |
| 源私有数据（`ctx.data`、兼容层 `loadData`） | 桥存储的 `data` 桶（按 sourceKey 隔离）：兼容层注册时经 `store.all` 整桶预载到内存供同步读，写时内存同步更新、异步落盘 |
| Cookie | **宿主侧 Cookie 罐独占**：框架只经 `cookies.get/set/delete` 按 URL 读写，JS 侧不存全量罐；Anikumo 侧罐与旧引擎共用条目，登录态无损沿用 |
| GET 短缓存 / 在途合并表 / 限流闸状态 | 框架内存（按桥共享），TTL 5 秒、进程结束即清，不落盘 |
| 刷新守卫备忘 | 分发器内存，窗口 2 秒，不落盘 |
| 框架日志 | 内存环形 500 条；同时转发宿主 `log.write` 通道，落不落盘由宿主定 |
| 账号凭据 | 框架不存：login 时只透传给源逻辑；登录态以 Cookie（宿主罐）与源 data 桶的形式存在 |
| 收藏 / 阅读进度 / 历史 | **不经过框架**，归宿主 App 自己管理 |

---

## 六、兼容范围与已知边界

### 6.1 自主 API

自主源 API 即框架本体：4.6 的接口面就是全部契约，处理函数可写函数或
`{ load }` 形式、explore 可写分节数组。没有「部分支持」的接口面——
源没实现的 kind 明确给 `MK_UNSUPPORTED_KIND`，宿主据此隐藏对应入口即可。

### 6.2 兼容层（旧框架风格源）

兼容层目标是让旧框架风格源文件**原样**注册运行：类式定义、全局对象、
设置与账号形状都由垫片承接（机制见 3.8）。口径如下：

- **已映射**：探索（含分节）、搜索（含 loadNext 式令牌分页）、详情、章节、
  图片页、分类、缩略图、账号登录/注销、设置（含 multi-select 等复合值）、
  图片钩子（onImageLoad / modifyImage / onLoadFailed，经 4.9 的标记与 kind 通道）。
- **明确未映射**（注册诊断 `unmappedSurfaces` 里明示，不静默吞）：
  **收藏、评论、WebView 登录、like / 评分**。用到这些面的源，其余功能照常，
  这几面在 Anikumo 里不生效（漫画区侧的收藏/评论走 App 自己的实现，与源无关）。
- **33 源兼容扫测**（2026-11-11，框架仓库 docs/SWEEP_REPORT.md）：33 个真源
  注册进同一引擎实例逐源走全链，12 源全链通、基线主力源数字与旧引擎实测
  基线对齐（见 6.3）；其余源的卡点逐个定界均为源/站侧原因（403、需登录、
  站方页面漂移、自托管未配置、网络不可达），无一例卡在框架缺面；
  扫测逼出的 13 类框架缺口已全部修复并加了回归测试。

### 6.3 活验基线（0.1.0）

一份真实源文件 `copy_manga.js`（v1.4.3）全链活验通过，
关键数字与旧引擎已验证基线一致：

| 环节 | 结果 |
|---|---|
| explore | 7 个分节有内容（推荐 / 热门 / 最新 / 完结 / 今日 / 本周 / 本月排行） |
| search「海贼王」 | **21 条**，首条《海贼王》 |
| details + chapters | **402 章** |
| pages（第一章） | **209 张图** |

同一源在真实 QuickJS（Dart 参考宿主）上复现搜索 21 条；
框架自带测试见第七章。

### 6.4 已知边界（诚实清单）

- **GBK 未内置**：`ctx.convert` 只有 UTF-8 系编解码（外加 base64 / hex /
  HTML 实体 / 哈希 / AES），没有 GBK 解码——需要 GBK 的源会失败在解码处，
  这是 0.1.0 的已知缺口（旧引擎有专门支持，本框架未移植）。
- **图片钩子的实际执行在宿主侧**：兼容层的钩子在框架内只做 URL/headers
  映射与标记透传，字节变换与解扰由宿主图片管线执行（4.9）；
  参考宿主未实现该管线、未验；Anikumo 生产宿主已实现同步图片注册表。
- **验证码永不代答**：框架只检测与转交用户过墙（3.7），这是定死的线，
  不会加入任何自动解题能力。
- **未验项**（0.1.0 测试报告口径）：长期运行、并发压测、内存上限触发行为未测；
  参考宿主只在桌面 QuickJS 探针台跑过，框架层面的 Android 真机行为以
  Anikumo 接入后的真机验证为准。
- 我们**不宣称与旧框架生态完全兼容**：兼容层是行为映射，
  未映射面与语义差异（3.8）都写在明处，注册诊断就是判定依据。

---

## 七、目录结构与运行环境

框架源码按职责分目录（宿主只需要认识打包后的单文件，这里供二次开发者参考）：

```text
src/index.js          入口：createMangaKit / installGlobals、定时器与 console 垫片
src/core/             桥客户端、错误码、日志（脱敏/环形）、校验与归一化、工具、验证墙检测
src/network/          HTTP 客户端：Cookie 经桥、GET 缓存/在途合并、限流闸、验证墙重放
src/parser/           HTML 解析与选择器、Convert（编解码/哈希）、AES
src/source/           注册表与清单、生命周期、ctx 能力面、统一分发器、引擎门面
src/compat/           兼容层（独立模块，核心零感知）
```

项目其余部分：

```text
dist/mangakit.js      单文件 bundle（npm run build 由 tools/build-bundle.mjs 生成）
examples/             自主 API 示例源（native_source.js）
tests/                Node 测试（逻辑档 + bundle 档）、真源活验、参考模拟宿主 mock_host.js
host_reference/       独立 Dart 参考宿主（flutter_qjs）：单原生函数承接全部桥调用的示范实现
docs/                 架构、宿主分析、源开发、宿主适配、扫测与测试报告
tools/                bundle 构建、33 源扫测（sweep.mjs）、单源调试（debug_one.mjs）
```

运行环境：QuickJS 类运行时（主目标）/ Node / 浏览器打包器均可；
缺什么能力就抛对应的码（`MK_HOST_MISSING` 等），不假装支持。

在本仓库（Anikumo）中的位置：

- 打包后的引擎：`assets/mangakit/mangakit.js`
- App 侧宿主与映射：`lib/services/manga/js/`
  （`mangakit_host.dart` 生产宿主 / `mangakit_source.dart` 契约映射 /
  `mangakit_image_registry.dart` 图片同步注册表）

构建与自检（框架仓库内）：

```bash
npm test                  # 逻辑档 + bundle 档（当前 23 例，含限流/性能/验证墙/图片钩子专项）
npm run build             # 生成 dist/mangakit.js
npm run test:live         # 真源活验（需要网络；源为 venera-configs 的 copy_manga.js）
cd host_reference && LD_LIBRARY_PATH=/tmp/qjsbuild flutter test   # 真 QuickJS 档
```

逻辑档构成：`core.test.js`（哈希向量含 HMAC-SHA-256 RFC 4231 用例、base64/UTF-8
往返、HTML 解析与选择器、归一化、日志脱敏与环形上限）、`native_source.test.js`
（自主源全链、设置跨引擎实例持久化、错误码）、`bundle.test.js`（裸 vm 加载
bundle 并完成注册 + 搜索）、`compat_units.test.js`（AES 向量、Comic 全局类、
令牌分页、复合设置值），以及 `rate_limit.test.js`、`perf_verification.test.js`、
`image_hooks.test.js` 三个专项。真引擎档（host_reference，flutter test）证明
bundle 在真实 QuickJS + Dart 宿主桥上跑通自主源全链与兼容源活验搜索。

---

## 八、开源信息

- MangaKit 本体采用 **GPL-3.0** 开源（见框架仓库 `package.json` 的 license 字段）。
- Anikumo 应用整体采用 **GPL-3.0** 开源，见仓库根目录 `LICENSE`。
- 框架只做源程序托管、数据聚合与形状归一，不托管、不分发任何受版权保护的内容；
  使用者导入的源与访问的内容由其自行负责，详见《免责手册》。
