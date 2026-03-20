# Browser Tool: Native CDP Integration Design

## 背景与目标

现有的 browser tool 依赖 `agent-browser`（Rust 二进制，通过 npm 分发），每次使用都启动一个独立的 Chrome 实例，存在以下问题：

- 用户登录态、Cookie 无法复用
- 需要额外安装 npm / agent-browser
- 每次任务弹出新 Chrome 窗口，体验差
- 依赖链长：npm → agent-browser binary → Chrome for Testing

**核心目标**：Clacky 直接复用用户已打开的 Chrome，继承所有登录态和 Cookie，零额外依赖。

---

## Chrome 146 的关键变化

### 时间线

| Chrome 版本 | 行为 |
|------------|------|
| ≤ 135 | `--remote-debugging-port` 可连接 default profile（不推荐但能用）|
| 136 ~ 145 | Default profile 被封锁，必须用 `--user-data-dir` 开隔离 profile（空的，无登录态）|
| **146+** | 新增 **autoConnect toggle**，一次开关，直接连真实浏览器，Consent-based ✅ |

### 用户操作（一次性）

1. 打开 `chrome://inspect/#remote-debugging`
2. 勾选 **"Allow remote debugging for this browser instance"**
3. Chrome 在 `127.0.0.1:9222` 启动 CDP server

之后每次 Clacky 连接时，Chrome 会弹一次 **"Allow remote debugging?"** 权限确认框，用户点 Allow 即可。

---

## 技术方案：纯 Ruby CDP Client

### 核心发现

Chrome 146 的 autoConnect 模式**不暴露标准 `/json` HTTP endpoint**（返回 404），而是通过一个文件告知连接信息：

```
~/Library/Application Support/Google/Chrome/DevToolsActivePort
```

文件内容格式：
```
9222
/devtools/browser/98823857-17b3-48ec-8f24-5805e3012a05
```

第一行是端口，第二行是 WebSocket path，直接拼成：

```
ws://127.0.0.1:9222/devtools/browser/98823857-17b3-48ec-8f24-5805e3012a05
```

### 连接流程

```
1. 读 DevToolsActivePort 文件
        ↓
2. WebSocket 连接 Browser endpoint
        ↓
3. Target.getTargets → 列出所有真实 tab
        ↓
4. Target.attachToTarget(targetId, flatten: true) → 获得 sessionId
        ↓
5. 通过 sessionId 发送 CDP 命令操作指定 tab
```

### 依赖

**零新依赖**，只用已有的：
- `websocket-driver`（已在 gemspec）
- `socket`（Ruby 标准库）
- `net/http`（Ruby 标准库）
- `json`（Ruby 标准库）

### 已验证能力

实测（2026-03-20）通过脚本验证：

- ✅ 读取 DevToolsActivePort，发现 9222 端口
- ✅ WebSocket 连接 Browser endpoint
- ✅ `Target.getTargets` 列出用户所有真实 tab（含标题、URL）
- ✅ `Target.attachToTarget` attach 到指定 tab
- ✅ `Runtime.evaluate` 执行 JS（获取 URL、title 等）
- ✅ `Page.captureScreenshot` 截图
- ✅ `Target.createTarget` 开新 tab 并导航
- ✅ 复用用户登录态（访问 yafeilee.com/admin 直接进后台，无需重新登录）

---

## 实施方案

### 第一层：Discovery（发现层）

```ruby
# 检测 Chrome 是否开启了 remote debugging
def discover_chrome_cdp
  port_file = File.expand_path(
    "~/Library/Application Support/Google/Chrome/DevToolsActivePort"
  )
  return nil unless File.exist?(port_file)

  lines = File.read(port_file).strip.split("\n")
  port = lines[0].to_i
  path = lines[1]

  # 验证端口确实在监听
  TCPSocket.new("127.0.0.1", port).close
  { port: port, path: path, ws_url: "ws://127.0.0.1:#{port}#{path}" }
rescue Errno::ECONNREFUSED
  nil
end
```

**没有发现时的引导**：

> "请在 Chrome 地址栏打开 `chrome://inspect/#remote-debugging`，
> 勾选 'Allow remote debugging for this browser instance'，只需一次。"

### 第二层：CDP Client（通信层）

新建 `lib/clacky/tools/cdp_client.rb`，实现：

- WebSocket 连接管理
- 命令发送（带 id）/ 响应匹配
- Session 管理（Browser-level vs Tab-level）
- 事件监听（Page.loadEventFired 等）

### 第三层：Browser Tool 改造

`lib/clacky/tools/browser.rb` 改造策略：

```
优先级 1: 检测 DevToolsActivePort → 用户真实 Chrome（Native CDP）
优先级 2: Fallback → 现有 agent-browser（向后兼容）
```

### macOS 路径（其他平台待补充）

| 平台 | DevToolsActivePort 路径 |
|------|------------------------|
| macOS | `~/Library/Application Support/Google/Chrome/DevToolsActivePort` |
| Linux | `~/.config/google-chrome/DevToolsActivePort` |
| Windows | `%LOCALAPPDATA%\Google\Chrome\User Data\DevToolsActivePort` |

---

## 关键问题与结论

### Q: `/json` endpoint 返回 404，怎么办？

Chrome 146 autoConnect 模式不走 HTTP `/json`，改用 `DevToolsActivePort` 文件 + 直接 WebSocket 连接。

### Q: ferrum gem 是否适用？

**不适用**。`Ferrum::Browser.new(url: "http://localhost:9222")` 虽然能连接到已有 Chrome，但会创建新的 incognito browser context，不复用用户的 tab 和登录态。需要绕过 ferrum，直接操作原始 CDP。

### Q: 每次连接都要点 Allow？

是的，Chrome 146 每次新的 WebSocket 连接都会弹确认框。这是 Chrome 的安全 consent 机制，无法绕过，但体验上是可以接受的（用户清楚地知道浏览器被控制了）。

### Q: agent-browser 是否彻底废弃？

建议渐进迁移：先并行运行，Native CDP 作为优先路径，agent-browser 作为 fallback，稳定后再移除。

---

## 参考资料

- [Chrome 146 autoConnect 介绍 - DEV Community](https://dev.to/minatoplanb/chrome-146-finally-lets-ai-control-your-real-browser-google-oauth-included-28b7)
- [One Toggle That Changed Browser Automation - LinkedIn](https://www.linkedin.com/posts/surajadsul_one-toggle-that-changed-the-browser-automation-activity-7439161929664864257-0v8z)
- [Chrome DevTools MCP 连接模式详解](https://www.heyuan110.com/posts/ai/2026-03-17-chrome-devtools-mcp-guide/)
- [agent-browser #412: Support --auto-connect](https://github.com/vercel-labs/agent-browser/issues/412)
- [Chrome DevTools Protocol 官方文档](https://chromedevtools.github.io/devtools-protocol/)
- [DevToolsActivePort WebSocket path 说明](https://deepwiki.com/ChromeDevTools/chrome-devtools-mcp/2.3-connection-modes)
- [ferrum issue #320: Connect to existing Chrome](https://github.com/rubycdp/ferrum/issues/320)
- [Chrome remote-debugging security changes](https://developer.chrome.com/blog/remote-debugging-port)

---

## 测试脚本

原型验证脚本位于：`tmp/cdp_test.rb`

运行前提：
1. Chrome 已开启 remote debugging（`chrome://inspect/#remote-debugging`）
2. 点击 Allow 弹框

```bash
bundle exec ruby tmp/cdp_test.rb
```
