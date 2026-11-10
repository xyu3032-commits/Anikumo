# 墨源 MoYuan 使用手册

墨源（MoYuan）是 Anikumo 小说区使用的**自研纯 JavaScript 小说聚合引擎**：
零依赖、单文件、模块化设计。它负责把用户导入的书源定义执行成统一的
搜索 / 详情 / 目录 / 正文数据，供 App 小说区展示。

- 引擎本体仓库目录：`moyuan/`（独立 SDK），许可证 **MIT**（见该目录 LICENSE）。
- 在 Anikumo 中以单文件形式内置：`assets/moyuan/moyuan.js`（由 SDK 源码打包生成，
  加载后全局名为 `MoYuan`，`JsNovelEngine` 为兼容别名）。
- 本手册分两部分：**在 Anikumo 里怎么用**（普通用户）与
  **SDK 调用详解**（开发者：具体怎么调用、数据存在哪）。

---

## 一、在 Anikumo 里怎么用

1. 打开小说区 →「书源管理」，通过 URL 导入、粘贴 JSON 或从仓库导入书源；
   也可以导入订阅源（RSS 格式），订阅源会单独分流到订阅注册表。
2. 回到小说区搜索框输入书名即可跨源搜索；点结果进详情、目录、正文阅读。
3. 源出问题时：书源管理页顶栏有诊断入口，对单个源跑一次全链诊断
   （搜索 → 详情 → 目录 → 正文），报告会指出断在哪一步、哪条规则。
4. 小说设置 →「扩展功能」里还有功能仓库（语音朗读、本地书籍等可选功能）。

注意：引擎只执行**用户自行导入的来源**，App 不内置任何内容源。

---

## 二、SDK 快速开始（独立使用）

墨源本体是 ES Modules 源码，无构建步骤，Node ≥ 18 或任意现代 JS 引擎可直接引用；
也可以用打包后的单文件 `dist/moyuan.js`（QuickJS 等无模块系统的宿主用）。

```js
import { createNovelEngine, Novel } from './src/index.js';

// 方式 A：独立引擎实例（推荐，可多实例隔离）
const engine = createNovelEngine({
  request: async (url, options) => { /* 你的传输层，见下文 */ },
  storage: myStorage,                    // 可选，缺省为内存存储
  config: { timeout: 15000, concurrency: 5 },
});

// 方式 B：全局门面 Novel（内部持有默认引擎）
Novel.configure({ request: myRequest });
```

最短调用链：

```js
engine.sourceManager.register(sourceJson);            // 注册一个书源定义
// 或批量 / 远程导入：
engine.sourceManager.importFromText(jsonText);
await engine.sourceManager.importFromUrl(url);

const { results } = await engine.search('小说名称', { concurrency: 5 });
const book = await engine.getBookInfo(results[0]);    // 详情（含目录地址 tocUrl）
const chapters = await engine.getChapters(book);      // 目录（分页自动跟随）
const content = await engine.getChapterContent(chapters[0].id);  // 正文
// content = { text, blocks: [{type:'text',text} | {type:'image',url,headers}], images, ... }
```

---

## 三、初始化选项：宿主必须注入什么

引擎核心不依赖 DOM、Node API、`fetch`、`localStorage`——网络、存储、解码全部由
宿主注入，这也是它能跑在 QuickJS 里
...[truncated 9114 chars]