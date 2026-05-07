# 刮削源 JSON 模板说明

本应用 **不内嵌任何 scrape 源**；引擎只在用户主动导入的 JSON 模板上运行。  
本文是模板格式参考，给愿意自行编写规则的用户阅读。

## 顶层字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 显示名 |
| `type` | enum | `video` / `music` / `lyric` |
| `origin` | string | 站点根 URL（仅显示用） |
| `enabled` | bool | 默认 `true` |
| `headers` | object | 可选 HTTP 头，例如 Cookie |
| `searchRequest` | object | 见下文「请求模板」 |
| `searchListSelector` | string | 选择条目数组的根选择器（CSS / XPath / JSONPath） |
| `searchItemRule` | object | 字段 → selector 映射；至少需要 `title` 与 `link` |
| `detailRequest` | object | 详情请求，可省略；URL 内可用 `{link}` 占位 |
| `detailRule` | object | 详情字段映射 |
| `lyricRequest` | object | 仅 type=lyric 用到，URL 内可用 `{title}` `{artist}` |
| `lyricContentSelector` | string | 歌词正文选择器 |

## 请求模板（ScrapeRequest）

```json
{
  "url": "https://example.com/api/search?q={query}",
  "method": "GET",
  "body": null,
  "bodyType": "form",
  "responseType": "json"
}
```

- `responseType` 取 `html` 或 `json`；引擎按此选择解析路径。
- `bodyType` 取 `form` / `json` / `raw`；POST 时生效。
- URL / body 内的占位符：
  - `{query}` 搜索关键词（自动 URL-encode）
  - `{query_raw}` 不做 encode
  - `{link}` 详情条目的链接（来自搜索结果的 link 字段）
  - `{title}` `{artist}` 仅歌词请求

## 字段选择器（Selector）

字符串前缀决定执行方式，前缀后再加 `@attr` 取属性 / `@text` 文本 / `@html` innerHTML：

| 前缀 | 用途 | 示例 |
|---|---|---|
| `css::`（默认可省） | HTML CSS 选择器 | `css::div.item h2 a@text` |
| `xpath::` | HTML XPath | `xpath:://div[@class='item']/h2/a/@href` |
| `json::` | JSONPath（JSON 响应） | `json::$.results[*].title` |
| `regex::` | 正则（在响应纯文本上） | `regex::/play/(\d+)\.html` |

## 完整示例（视频站，HTML 响应）

```json
{
  "name": "示例影视站",
  "type": "video",
  "origin": "https://example.com",
  "enabled": true,
  "searchRequest": {
    "url": "https://example.com/search?keyword={query}",
    "method": "GET",
    "responseType": "html"
  },
  "searchListSelector": "css::ul.search-list > li",
  "searchItemRule": {
    "title": "css::h2.title a@text",
    "year":  "css::span.year@text",
    "image": "css::img@src",
    "link":  "css::h2.title a@href"
  },
  "detailRequest": {
    "url": "{link_raw}",
    "method": "GET",
    "responseType": "html"
  },
  "detailRule": {
    "title":    "css::h1.title@text",
    "overview": "css::div.synopsis@text",
    "image":    "css::div.poster img@src"
  }
}
```

## 完整示例（歌词，JSON 响应）

```json
{
  "name": "示例歌词站",
  "type": "lyric",
  "origin": "https://example.com",
  "lyricRequest": {
    "url": "https://example.com/api/lyric?title={title}&artist={artist}",
    "method": "GET",
    "responseType": "json"
  },
  "lyricContentSelector": "json::$.data.lrc"
}
```

## 引擎执行流程

1. 用户在「刮削源（脚本式）」页面粘贴 JSON 导入。
2. 调用 `ScrapeEngine.instance.search(source, keyword)` → 拼 URL → 抓响应 → 按 `searchListSelector` 切分 → 对每条用 `searchItemRule` 解析字段。
3. 拿到候选条目后，可调 `getDetail(source, link)` 抓详情；歌词类型直接走 `getLyric(source, title:..., artist:...)`。
4. 当前 commit 只接好引擎与导入页，**8 个 native scraper 仍照常工作**；后续 commit 会按使用场景接入返回结果（先视频详情页扫描候选源 → 命中即覆盖）。

## 安全与版权

- 启动时只从 Hive 读用户导入的源；assets/ 下不放任何 *.json。
- 引擎不执行任何用户脚本，仅按声明式规则解析；规避了 eval 沙箱风险。
- 出现 5xx / 网络异常时按 `AppError` 走本地日志，不主动重试，不主动上传任何数据。
