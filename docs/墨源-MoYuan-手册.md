# 墨源 MoYuan 使用手册

墨源（MoYuan）是 Anikumo 小说区使用的**自研纯 JavaScript 小说聚合引擎**：
零依赖、单文件、模块化设计。它负责把用户导入的书源定义执行成统一的
搜索 / 详情 / 目录 / 正文数据，供 App 小说区展示。

- 引擎本体：独立 SDK（ES Modules 源码），许可证 **MIT**。
- 在 Anikumo 中以单文件形式内置：`assets/moyuan/moyuan.js`（由 SDK 源码打包生成，
  加载后全局名为 `MoYuan`，`JsNovelEngine` 为兼容别名），
  在 App 内置的 QuickJS 运行时中执行。
- 本手册内容：普通用户用法、**工作原理与运行机制**、SDK 调用详解、
  调用数据存放位置、兼容范围、开源信息。

---

## 一、这是什么

**墨源（MoYuan）是 Anikumo 作者自研的一个纯 JavaScript 小说聚合引擎**，从 1.0.2 起
作为小说区的唯一引擎运行。它零依赖、不绑定任何平台 API，网络、存储、解码都由宿主
（Anikumo）注入，打包为单个 JS 文件，在 App 内置的 QuickJS 运行时中执行。

它负责的事情只有一件：**按用户导入的书源规则，去解析搜索、发现、详情、目录与正文**，
把不同站点的页面变成统一的书籍数据。引擎本身不内置、不提供任何书源与内容，
源由用户自行导入，内容版权归原站与原作者所有。

主要能力：

- 多源聚合搜索与发现分类（可动态生成的分类同样支持）
- 详情、目录、正文的规则解析（CSS / XPath / JSONPath / 正则 / JS 规则与模板）
- 章节正文的严格分型（文字段落与图片分开处理，支持图片型「漫画书」与音频型有声书源）
- 订阅源（RSS 格式的文章列表与正文阅读）
- 引擎内缓存与并发控制、整本下载、插件钩子、单源诊断与全源健康巡检

---

## 二、在 Anikumo 里怎么用

普通读者不需要接触引擎本身，只需要书源：

1. **导入**：小说区 →「书源」页 → 从 URL 导入 / 粘贴导入 / 从文件导入 /
   从 GitHub 仓库挑选导入。也可以导入订阅源（RSS 格式），订阅源会单独分流管理。
2. **管理**：点任意书源一行会展开它的信息面板（源链接、分组、源自带说明），
   带登录声明的源有「打开源登录/设置」入口——源的登录表单在 App 内填写提交，
   不用去源的网站。
3. **排查**：某个源搜不到书、目录为空、正文不对时，用书源管理页里的「源诊断」跑一遍，
   报告会写明卡在哪一步（搜索、详情、目录还是正文），反馈问题时附上诊断结论最有效。
4. **阅读**：章节与正文有会话内缓存，读过的章节来回翻是即时的；读当前章时下一章会
   在后台预取，翻页不用等。

小说区的扩展功能在「小说设置 → 扩展功能」（功能仓库）里按需安装：
语音朗读（系统 TTS、读完自动下一章）与本地书籍（EPUB / TXT 导入）都在那里，
没安装时对应入口在区内完全不存在。

---

## 三、工作原理与运行机制

### 3.1 总览：它到底在做什么

一句话原理：**书源定义 = 一组「去哪个网址、用什么规则从返回页面里抠出哪些字段」的
说明书；墨源是一个说明书执行器**。它自己不存内容、不认识任何具体网站，
只做四件事：渲染网址 → 发请求拿页面 → 按规则抠字段 → 把结果整理成统一结构。

分层结构（自下而上）：

| 层 | 职责 |
|---|---|
| 宿主注入层 | 宿主（如 Anikumo）提供的传输、键值存储、文本解码三个通道，引擎不自带 |
| 网络层 | 超时、重试、按域名限流、charset 探测与解码、Cookie 罐 |
| 解析层 | HTML 解析 + CSS / XPath / JSONPath / 正则 / JS 五种规则求值、模板渲染 |
| 源执行层 | 按书源定义驱动「搜索 → 详情 → 目录 → 正文」全链，处理翻页跟随与登录检查 |
| 聚合层 | 多源并行搜索、失败隔离、去重排序；缓存、下载、插件、事件 |
| 数据契约层 | 统一的 Book / Chapter / Content 结构，以及与宿主互转的桥接层 |

### 3.2 一次搜索的全过程

以在 Anikumo 里搜一本书名为例，引擎内部依次发生：

1. **分发**：聚合器把启用的书源列表交给一个并发池（默认并发 5），逐源发出
   `search:progress` 事件（开始 / 成功 / 失败），界面上的逐源进度就是这么来的。
2. **备料**（每个源第一次运行时）：加载该源的 `jsLib`（源自带的 JS 工具库），
   并预取规则里声明的同步请求（见 3.8），让后面的 JS 规则能同步拿到数据。
3. **拼网址**：把关键词、页码代入源的 `searchUrl` 模板（`{{key}}`、`{{page}}`
   与任意 `{{表达式}}`），网址尾部若带 `,{...}` 形式的选项 JSON，一并解析出
   请求方法、请求体、请求头与 charset。
4. **发请求**：经网络层发出（带该源的请求头与 Cookie），拿到响应后按
   Content-Type → 页面 `<meta charset>` 的顺序探测编码，非 UTF-8 时解码（如 GBK）。
5. **抠列表**：用 `ruleSearch.bookList` 规则从页面里框出每条结果，再对每条分别用
   `name / author / coverUrl / kind / lastChapter / bookUrl` 等字段规则抠值；
   支持翻页时按 `nextTocUrl` 式逻辑跟随下一页。
6. **登录检查**：源声明了 `loginCheckJs` 时在结果回来后执行，判断会话是否失效。
7. **规范化**：每条结果整理成统一 Book 结构（见 4.3），带上来源 id 与名称。
8. **合并**：所有源的结果汇总，按「书名 + 作者」去重、按源优先级排序后返回；
   **单个源失败不影响整体**——失败只发 `source:error` 事件，搜索照常返回其余结果。
9. **入缓存**：整次搜索结果按缓存键存入缓存（键里含各源变量指纹，源切换线路后
   指纹变化、旧结果自动作废），短时间内重复搜索直接命中。

详情、目录、正文是同一套机制换规则组：详情用 `ruleBookInfo` 并产出目录地址，
目录用 `ruleToc` 并沿 `nextTocUrl` 逐页跟随（上限 50 页）成完整章节列表，
正文用 `ruleContent` 并沿 `nextContentUrl` 跟随拼全一章（上限可配）。

### 3.3 书源定义如何被规范化

导入的每条书源在注册时先过一遍规范化，之后的执行只面对统一形状：

- **字段归一**：`bookSourceUrl` 成为源的唯一 id，`bookSourceName` 为显示名；
  `header` 解析为请求头对象；五组规则（`ruleSearch / ruleExplore / ruleBookInfo /
  ruleToc / ruleContent`）逐字段转字符串、丢空值。
- **旧式扁平格式合成**：带 `ruleSearchList` 等扁平字段的早期格式会被识别并
  合成成标准嵌套规则（`searchKey` 占位替换为 `{{key}}` 等），缺什么补什么，
  已经是标准形状的定义原样通过。
- **源种类判定**：分三种——`custom`（程序化自定义源，见 4.6）、
  `legado`（有规则面可执行）、`webview-html`（整源只有一个网页、无任何规则面，
  规则引擎无法执行，只识别分类并如实标注不支持，交宿主的 WebView 处理）。
- **内容类型**：`bookSourceType` 决定正文形态——0 文字、1 音频（有声书）、
  2 图片（漫画书），正文分块随之产出 text / audio / image 三种块。

### 3.4 规则是怎么求值的

一条规则字符串会被解析成一条**求值管线**，从左到右逐步收窄：

- **选择器链**：`class.list@li@text` 这样以 `@` 连接——先按 CSS 选元素，
  再逐级下钻，最后一段是取值方式（`text` / `href` / `src` / `html` 等）；
  规则开头的类型标记决定解析器：默认 CSS、`@XPath:`、`$.` 开头走 JSONPath、
  正则规则走正则提取；列表规则支持索引与区间（如 `[0]`、`[!0:2]`、负索引）。
- **组合符**：`||` 是**顶层**兜底（前一段取不到才用后一段，不会在 `@js:` 内部切分）；
  `&&` 是拼接（多段结果合并）；字段规则之间互不干扰。
- **正则清洗**：规则尾部的 `##正则##替换` 在取值后做一次正则替换，
  常用于去掉标题里的杂质。
- **模板拼装**：字段值里的 `{{...}}` 不是简单占位——引擎先逐段求值再拼装
  （Legado 的 makeUpRule 语义），所以 `https://站点/书/{{$.book_id}}` 这类
  「网址里嵌 JSONPath」能正确工作。
- **JS 变换**：规则以 `@js:` 开头表示整条规则就是一段 JS；写在普通规则尾部的
  `@js:` 是后处理变换，对前面取到的值再加工；`<js>...</js>` 段同理。
  JS 执行有超时（默认 5 秒），超时按失败处理。

### 3.5 JS 规则与 `java.*` 对象

规则里的 JS 运行时，引擎会注入一组宿主对象，其中最重要的是 `java`：

- `java.ajax(url)` / `java.get(url, headers)` / `java.post(url, body, headers)`：
  **同步**发请求并直接返回结果（这是该格式的既定语义，规则代码按同步书写）。
- `java.put(key, value)` / `java.get(key)`：源级变量存取（切换线路、记住令牌等靠它），
  变量存放在引擎的源变量表里，Anikumo 侧会随源一起持久化。
- 还有编码、加解密（内置一个轻量加密子集：SHA / HMAC / AES 等）、
  时间、日志等工具方法。
- 同步请求走「同步响应缓存」：命中直接返回；未命中且宿主没提供同步通道时，
  引擎发 `source:unsupported` 事件如实上报该能力不可用——**不假装、不静默吞**。
- 源自带的 `jsLib` 在源首次运行前加载一次，其函数供该源全部规则调用。

### 3.6 网络层怎么工作

- **传输靠注入**：引擎不假设 `fetch` 存在。运行时有 `fetch` 时用它兜底；
  QuickJS 类宿主必须注入传输函数（Anikumo 的注入方式见 3.10）。
- **重试**：429 与 5xx 抛错后指数退避重试（尊重 `Retry-After`），其他 4xx 立即失败；
  POST 默认不重试。每次尝试带超时与取消信号，排队未发出的请求在取消时直接丢弃。
- **限流**：可按域名设最小请求间隔，间隔自请求**实际发出**时刻起算，
  不被排队时间偷占。
- **编码**：显式 charset 优先，其次 Content-Type、再其次页面 meta 探测；
  非 UTF-8 且拿得到原始字节时经宿主解码钩子或内置 GBK 表解码，解码失败不抛错、
  保留原文继续（宁可乱码不中断）。
- **Cookie 罐**：引擎自带 Cookie 罐（带 Domain / Path / Expires 基本语义）；
  注入了存储时，罐子持久化到存储键 `moyuan:cookies`（变更后节流 500ms 落盘），
  所以登录态在重启后还在。源可声明关闭自己的 Cookie 罐。

### 3.7 缓存与并发

- **聚合并发**：搜索是多源并行 + 单源隔离（见 3.2）；全局请求另有并发上限
  （默认 6），超出的排队。
- **缓存分层**：搜索引擎结果、书籍、目录、正文自动走缓存，
  键前缀分别为 `search:` / `book:` / `toc:` / `content:`；
  内存层是真 LRU（默认 200 条，超容淘汰最久未用），带 TTL（默认 1 小时）；
  任何调用加 `noCache` 可绕过。诊断模式永远绕过缓存直查源。
- **取消**：`engine.createTask()` 生成任务令牌，搜索与请求带上它即可中途取消
  （`task.abort()`），已发出的请求靠取消信号收尾。

### 3.8 同步请求的挂起—重放（Anikumo 宿主机制）

这是墨源在 Anikumo 里最特殊的一环。规则 JS 里的 `java.ajax` 要求**同步**返回，
但 Flutter 的 JS 通道是异步的、Dart 的网络请求也是异步的——同步等异步会死锁。
Anikumo 的宿主（`MoyuanHost`）这样化解：

1. 宿主注入的同步通道 `novelHostRequestSync` 从不内联回答：它**记录**这次请求
   （方法、网址、请求体），然后抛出一个带标记的「挂起」异常，整段规则调用随之中止。
2. 宿主在 Dart 侧用真正的异步网络把这次请求发出去，拿到响应后按请求指纹
   预填引擎的同步响应缓存。
3. 宿主把刚才整段调用**从头重放**：这次 JS 里的 `java.ajax` 直接命中缓存、
   同步拿到真实响应，规则一路跑完。
4. 一段规则里若有多个同步请求，重复以上过程逐个补齐（有轮次上限防死循环）；
   规则自己用 try/catch 包住 `java.ajax` 的探测型写法同样能被恢复：
   挂起被规则吞掉后，宿主仍按记录把数据补上再重放一轮。

代价是慢路径要多跑几遍规则（规则必须是可重入的纯计算，这正是该格式的通行假设）；
好处是成千上万条按同步语义写成的现成规则不用改一个字。

### 3.9 单文件打包原理

SDK 源码是几十个 ES Module 文件，QuickJS 宿主没有模块加载器，所以打包器
（`tools/build-bundle.mjs`）做了一次刻意小型的 **ESM → 模块注册表**改写：
把每个源文件包成一个注册项、把 import/export 改写为注册表查找，排除
Node / Browser 等运行时专属适配器，最后拼成一个无 import/export 残留、
不假设 DOM / Node / `fetch` 的单文件。文件求值后在全局挂出
`MoYuan`（全部导出）、`Novel`（门面）、`createNovelEngine` 三个名字。
打包产物有沙箱测试锁定：在无 DOM、无 Node 全局的空环境里能加载、能搜索。

### 3.10 在 Anikumo 里的宿主结构

- 引擎文件：App 资源 `assets/moyuan/moyuan.js`，由 `MoyuanHost`
  （`lib/services/novel/moyuan_host.dart`）持有 QuickJS 运行时并加载。
- 宿主在求值引擎前注册三个通道：`novelHostRequest`（异步传输，走 App 自己的
  网络栈，GBK 在 Dart 侧解码）、`novelHostStorage*`（键值存储，背后是专用
  Hive 存储盒）、`novelHostRequestSync`（同步通道，机制见 3.8）。
- 异步通道不直通 Promise：宿主用一套小的 JS Promise 注册表
  （`__moyuanHostCall / __moyuanComplete`）与结果槽（`__moyuanSlot`）在
  Dart 与 JS 之间对接完成时机。
- 业务侧由 `MoyuanEngine`（`moyuan_engine.dart`）把桥接层包成 App 的
  `NovelSource` 接口，小说区其余代码只认接口、不认引擎。

---

## 四、SDK 调用详解

### 4.1 初始化选项

| option | 说明 |
|---|---|
| `request` | 异步传输：`async (url, {method, headers, body, charset, timeout, signal}) => {status, headers, body, url, bytes?}`；超时/取消后 `signal.aborted` 为真 |
| `requestSync` | 同步传输（规则 JS 里 `java.ajax` 的实时通道）：`(url, {method, headers, body}) => {status, headers, body, url} \| string`；QuickJS 宿主亦可提供全局 `novelHostRequestSync(url, optionsJson)` |
| `jsEvaluator` | 自定义 JS 求值器 `(code, scope, lib) => value`；注入后 JS 时限由宿主负责 |
| `storage` | 键值存储 `{get, set, delete, keys, clear}`（同步/异步、Map、普通对象都行），缺省内存存储 |
| `decodeText` | `(bytes, charset) => string` 编码钩子（GBK 等） |
| `config` | `{timeout:15000, concurrency:5, retries:2, retryDelay:400, cacheTTL:3600000, cacheMaxEntries:200, jsTimeoutMs:5000, userAgent, maxContentPages, maxTocPages:50}` |
| `sources` | 初始化即注册的书源定义数组 |
| `logger` | 日志对象（默认 console） |

### 4.2 核心调用

```js
const { results, total, sourcesQueried } = await engine.search('书名', {
  sources: [/* 可选：只查这些源 id */], concurrency: 5, page: 1, noCache: false,
});
const book = await engine.getBookInfo(results[0]);       // 传结果对象或 id 都行
const chapters = await engine.getChapters(book);         // 目录分页已自动跟随、去重
const content = await engine.getChapterContent(chapters[0].id);
// 或一步到位：engine.getChapterContentFor(book, chapter)
const categories = await engine.discover(sourceId);      // 发现分类（可为 @js: 动态生成）
const list = await engine.explore(sourceId, categories[0], { page: 1 });
const hit = await engine.parseUrl('https://…');          // 按 bookUrlPattern 反查 {book, sourceId} | null
```

### 4.3 返回结构（统一数据契约）

```text
Book（搜索结果/详情）:
  { id, title, author, cover, description, sourceId, sourceName, url,
    latestChapter, updateTime, tags[], kind, wordCount, tocUrl(详情), metadata }
Chapter:
  { id, bookId, title, index, url, sourceId, isVip, isPay, webView, metadata }
Content:
  { id, bookId, chapterId, title, text, content(同 text), html,
    blocks: [{type:'text', text} | {type:'image', url, headers} | {type:'audio', url, headers}],
    images[], sourceId, metadata }
```

### 4.4 约定、事件与错误码

- 所有公开 API 返回 **Promise<数据>**，不包装 `{ok, data}`。
- 失败 reject `NovelError {name:'NovelError', code, message, sourceId}`。
- 多源搜索是唯一例外：单源失败不影响整体（见 3.2 第 8 步）。
- 事件经 `engine.on(name, fn)` 订阅（返回取消订阅函数）：

| 事件 | 载荷 |
|---|---|
| `search:progress` | `{keyword, sourceId, status, done, total}` |
| `source:error` | `{sourceId, stage, error}` |
| `source:unsupported` | `{sourceId, feature}`（如同步 ajax 无通道、webJs 无处理器） |
| `source:registered / unregistered` | 源增删 |
| `download:*` | 下载任务生命周期 |
| `plugin:error` | 插件钩子抛错（被隔离，不中断引擎） |
| `health:suspect` | `{sourceId, status, failures, threshold}` |
| `debug:step` | 仅追踪窗口内发出的单步记录（见 4.9） |

错误码：`E_NETWORK` 网络失败 · `E_HTTP` HTTP 错误状态（details 带 status/url） ·
`E_TIMEOUT` 超时 · `E_ABORTED` 已取消 · `E_PARSE` 解析失败 ·
`E_SOURCE_NOT_FOUND` · `E_SOURCE_INVALID` · `E_BOOK_NOT_FOUND` ·
`E_CHAPTER_NOT_FOUND` · `E_PLUGIN` · `E_STORAGE` ·
`E_UNSUPPORTED` 环境不支持的能力 · `E_VALIDATION` 参数校验。

### 4.5 书源管理（`engine.sourceManager` / `engine.sourceAPI`）

```js
engine.sourceManager.register(def);                 // 注册单个（对象或 JSON 文本）
engine.sourceManager.registerMany(defs, { replace: true });
engine.sourceManager.importFromText(jsonText);      // 批量导入，逐条报告成功/失败
await engine.sourceManager.importFromUrl(url);      // 远程导入
engine.sourceManager.list();                        // 已注册源（含启停状态）
engine.sourceManager.enable(id); engine.sourceManager.disable(id);
engine.sourceManager.remove(id); engine.sourceManager.edit(id, patch);
engine.sourceManager.validate(def);                 // 只校验不注册
const report = await engine.sourceManager.testSource(id, '测试');
   // 全链实测 search→bookInfo→chapters→content，返回逐步 steps
const backupText = engine.sourceManager.backup();   // 导出全部定义为文本
engine.sourceManager.restore(backupText);           // 恢复
engine.sourceManager.stats();                       // 计数概览
```

登录相关：`sourceManager.loginForm(sourceId)` 取登录表单定义，
`submitLoginForm(values)` 在引擎内提交；`engine.setLoginInfo(sourceId, info)`
直接注入已有登录信息。表单提交后源变量与 Cookie 都落在该源名下。

### 4.6 自定义 JS 源（不用规则、直接写代码）

```js
engine.sourceManager.register({
  id: 'my-source', name: '我的源',
  custom: {
    async search(key, { page }) { return [{ title, author, cover, url }]; },
    async bookInfo(item) { return { ...item, description, tocUrl }; },
    async chapters(item) { return [{ title, url }]; },
    async content(item, chapter) { return { text }; },
    // 可选：exploreCategories() / explore(category, {page})
  },
});
```

自定义源的返回经同一套规范化，与规则源在聚合搜索里混排无区别。

### 4.7 发现、订阅、远程仓库、本地书

```js
engine.rss.register(def); engine.rss.list();
engine.rss.categories(sourceId);
await engine.rss.articles(sourceId, category);
await engine.rss.articleContent(sourceId, article);
await engine.remote.importFromUrl(url);   // 任意仓库文件：书源/订阅/网页型三路分流，逐条报告
parseTxtBook(text); parseEpubBook(bytes, { inflate });
new OpdsCatalog(engine).fetchCatalog(url);
```

### 4.8 缓存、下载、插件、书架

```js
engine.cache.get/set(key, value, ttl?)/has/delete/clear/keys()/stats()/exportAll()/importAll(obj);
const task = engine.downloads.create(book, chapters);   // 整本下载
engine.downloads.pause/resume/cancel(id); await engine.downloads.wait(id);
   // task = {id, bookId, title, status, total, done, failed, progress, errors}
engine.plugins.register({ id, capabilities, hooks: { afterSearch, afterBookInfo, afterContent } });
   // 钩子按启用顺序串行，返回值替换流水线数据；抛错只记该插件的 error，不中断引擎
engine.bookshelf().add(book); engine.bookshelf().list();   // 持久化于注入存储
const task = engine.createTask(); engine.search(kw, { task }); task.abort();
```

### 4.9 调试追踪与健康巡检

```js
const report = await engine.debug.debugSource(sourceId, { keyword: '测试', sampleChapters: 1 });
// { sourceId, sourceName, kind, ok, failedAt, error?, durationMs,
//   counts: {search, chapters, contentChars}, steps: [...], summary }
// failedAt ∈ lookup|resolve|search|bookInfo|chapters|content|rss.articles|rss.content
// 步骤字段：seq / ts / stage / kind / label（如 ruleToc.chapterName）/ rule（截断）/
// inputSummary / outputSummary / excerpt（http 步的正文摘录）/ durationMs / error
// 单个追踪最多保留 500 步，超出的丢最旧并在 summary.dropped 里计数；
// 追踪同一引擎请串行使用（引擎级单槽位，并发会串步）。
const { result, trace } = await engine.debug.trace((e) => e.search('书名'));
const health = await engine.health.check(sourceId);        // 五态：ok|empty|error|unsupported|disabled
const all = await engine.health.checkAll({ concurrency: 3 });  // 连续失败达阈值（默认 3）标 suspect
engine.health.history(sourceId);                            // 最近 10 次记录
```

读法示例：目录为空 → 找 `label === 'ruleToc.chapterList'` 的步，
`outputSummary` 是 `0 elements` 说明选择器没命中，对照同阶段 `http` 步的
`excerpt` 看站点实际返回了什么；有元素再看 `chapterName / chapterUrl` 两步。

### 4.10 Anikumo 桥接层（宿主对接面）

`createAnikumoBridge(engine)` 返回与 Anikumo 的 Dart `NovelSource` 接口
同名同形的方法（首参为源 id，因 Dart 侧一个实例对应一个源、JS 桥多源共用）：

| Dart 签名 | JS 桥 |
|---|---|
| `Future<List<NovelItem>> search(String key, {int page})` | `bridge.search(sourceId, key, page = 1)` |
| `List<NovelExploreCategory> get exploreCategories` | `bridge.exploreCategories(sourceId)`（同步） |
| `Future<List<NovelItem>> explore(NovelExploreCategory c, {int page})` | `bridge.explore(sourceId, category, page = 1)` |
| `Future<NovelItem> bookInfo(NovelItem item)` | `bridge.bookInfo(item)` |
| `Future<List<NovelChapter>> chapters(NovelItem item)` | `bridge.chapters(item)` |
| `Future<List<NovelBlock>> content(NovelItem item, NovelChapter chapter)` | `bridge.content(item, chapter)` |

字段互转由适配器完成（`toAnikumoItem / fromAnikumoItem / toAnikumoChapter /
contentToAnikumoBlocks / toAnikumoCategory` 等）。其中一条硬规则值得单独说明——

**kind ↔ 标签、书名防串位（有测试锁定）：**

1. **书名恒为书名**：桥接输出的 `title` 只取书籍的 `title`，
   严禁用 kind / tags / author 兜底——书名为空就留空。
2. **输出（引擎 → App）**：引擎的 `kind` 各段（按 `,，、/；;` 拆分）与 `tags[]`
   合并、去重、保序后拼成 App 的分类/标签串，一段不丢；书名绝不混入。
3. **输入（App → 引擎）**：标签串拆分还原，第一段为引擎 `kind`（主分类）、
   全段进 `tags[]`；往返不丢、顺序稳定、二次往返为不动点。

正文里的 audio 块：桥接默认把听书源的音频块降级为指向音频地址的 text 块
（链接不丢）；宿主能处理音频块时可传 `{includeAudio: true}` 原样输出。

已装源清单互导：App 以 `novelInstalledSourcesJson` 持久化的原始定义数组，
与引擎注册表保存的是同一份文档，可用 `toAnikumoInstalledJson(engine)` /
`importAnikumoInstalledJson(engine, jsonText)` 直接搬家（逐条报告导入结果）。

---

## 五、调用数据在哪

引擎不自带落盘：**凡是要留下来的数据，都写进宿主注入的 `storage`**。
键名一览（排查问题时按图索骥）：

| 数据 | 存放位置 |
|---|---|
| 书源定义（注册表） | 引擎内存；持久化由宿主负责——Anikumo 存在 App 设置存储的 `novelInstalledSourcesJson`（原始定义数组，与引擎注册表是同一份文档） |
| Cookie 罐 | 注入存储的键 `moyuan:cookies`（变更节流 500ms 落盘）；无注入存储时仅内存 |
| 搜索/书籍/目录/正文缓存 | 内存 LRU（键前缀 `search:` / `book:` / `toc:` / `content:`），不落盘，进程结束即清 |
| 源变量（`java.put` 写入） | 引擎源变量表内存；Anikumo 侧随源持久化（seed/harvest） |
| 登录信息 | 引擎内存，经 `setLoginInfo` 注入或登录表单提交产生 |
| 书架 | 注入存储（`bookshelf()` 系列） |
| 下载任务元数据 | 注入存储的键 `download:tasks`；下载到的正文进缓存 `content:<chapterId>` |
| 健康巡检历史 | 注入存储的键 `moyuan:health:<sourceId>`（每源最近 10 次） |
| 调试追踪 | 仅在追踪调用的返回值里，不落盘 |

**在 Anikumo 中的对应落点：**

- 引擎的键值存储通道背后是 App 的一个专用 Hive 存储盒，
  上表的 Cookie、下载任务、巡检历史都实际存在那里。
- 书源清单存在 App 的设置存储里（键名 `novelInstalledSourcesJson`）。
- 书架、收藏、阅读进度、设置等**应用数据归 App 自己管理**，不经过引擎存储。
- App 另有一层界面侧会话缓存（章节列表与正文按书/按章缓存、下一章预取），
  它在引擎缓存之外、只在本次运行内有效。

---

## 六、兼容范围

墨源支持一类广泛使用的开源书源 JSON 格式的主链：导入、搜索、发现、详情、
目录、正文，以及模板、URL 参数（网址尾部的选项 JSON）、JS 库与登录表单。
逐项兼容表见引擎仓库的兼容说明文档；这里只列口径：

- **明确不支持**（导入这类源时对应功能不生效，诊断会如实标注）：
  `preUpdateJs`、`ruleReview`、`webJs`、`java.webView`。
  其中 `webJs` 仅在宿主注入 `webJsHandler(url, html, sourceId)` 时才执行，
  Anikumo 未注入该处理器。
- **webview-html 型源**（整源一个网页、无规则面）：只识别与分类，不执行，
  诊断直接给「不支持」结论（见 3.3）。
- **订阅源**（RSS/Atom）：定义里只有名称与地址、没有书籍规则的条目会被自动
  分流到订阅注册表，与书源分开管理；无规则的标准 feed 走降级解析。
- 漫画类源以图片正文块执行（bookSourceType 2），听书类以音频块执行（type 1）。
- 我们**不宣称与任何既有生态完全兼容**；遇到解析不了的源，
  诊断报告会给出具体失败点（哪一步、哪条规则、源站实际返回了什么）。

---

## 七、目录结构与运行环境

引擎源码按职责分目录（宿主只需要认识打包后的单文件，这里供二次开发者参考）：

```text
src/core/      引擎本体、事件、任务/并发、配置、错误、模板与 URL 工具、追踪收集器
src/api/       Search/Book/Chapter/Source/Cache/Download 的薄封装
src/source/    源注册表、源执行全链、仓库导入、订阅适配、本地书、OPDS、健康巡检
src/parser/    规则求值：HTML/CSS/XPath/JSONPath/正则/JS 解析器、轻量加密、XML
src/search/    聚合搜索（并行/隔离/进度）与结果去重
src/network/   请求管理（超时/重试/限流/Cookie/编码钩子）
src/cache/     缓存（TTL/LRU/统计/导入导出）
src/storage/   存储适配与内存存储
src/download/  下载队列（暂停/恢复/重试/持久化）
src/plugins/   插件管理（生命周期/能力/错误隔离）
src/adapters/  各运行时适配器与 Anikumo 桥接层
```

运行环境：浏览器 / Node / QuickJS / Deno / Bun / React Native / 小程序 /
Tauri / Anikumo 宿主均可（各有适配器文件）；缺什么能力就抛
`E_UNSUPPORTED` 并写明，不假装支持。

在本仓库（Anikumo）中的位置：

- 打包后的引擎：`assets/moyuan/moyuan.js`
- App 侧宿主与桥接：`lib/services/novel/`（`moyuan_host.dart` / `moyuan_engine.dart`）

构建与自检（引擎仓库内）：

```bash
npm test                  # 离线测试套件（不联网）
npm run bundle:anikumo    # 打包单文件到 dist/moyuan.js
node examples/01-basic-search.js        # 自定义源全链示例（其余示例见 examples/）
```

---

## 八、开源信息

- 墨源 MoYuan 本体采用 **MIT License** 开源。
- Anikumo 应用整体采用 **GPL-3.0** 开源，见仓库根目录 `LICENSE`；
  界面中展示番剧元数据时对数据来源有署名（见 App 内「致谢」与官网说明）。
- 引擎只做规则解析与数据聚合，不托管、不分发任何受版权保护的内容；
  使用者导入的源与访问的内容由其自行负责，详见《免责手册》。
