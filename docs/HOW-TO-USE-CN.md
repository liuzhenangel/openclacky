# OpenClacky 使用指南

## 安装

```bash
gem install openclacky
```

**系统要求：** Ruby >= 3.1

## 快速开始

### 1. 启动 Clacky

```bash
clacky
```

### 2. 配置 API Key（首次使用）

在聊天界面中输入：

```
/config
```

然后按提示设置你的 API key：
- **OpenAI**：从 https://platform.openai.com/api-keys 获取
- **Anthropic**：从 https://console.anthropic.com/ 获取
- **MiniMax**：国内推荐，https://platform.minimaxi.com/
- **OpenRouter**：聚合多个 AI 模型，https://openrouter.ai/

### 3. 开始对话

直接在聊天框输入你的问题或需求：

```
帮我写一个解析 CSV 文件的 Ruby 脚本
```

```
创建一个网页爬虫提取文章标题
```

## 核心功能

### 🎯 自主代理模式
Clacky 可以自动执行复杂任务，内置多种工具：
- **文件操作**：读取、写入、编辑、搜索文件
- **网页访问**：浏览网页、搜索信息
- **代码执行**：运行 shell 命令、测试代码
- **项目管理**：Git 操作、测试、部署

### 🔌 技能系统
使用简写命令调用强大的技能：

```
/commit          # 智能 Git 提交助手
/gem-release     # 自动化 gem 发布流程
```

你还可以在 `.clacky/skills/` 目录创建自己的技能！

### 💬 智能记忆管理
- **自动压缩**长对话内容
- **保留上下文**同时降低 token 成本
- **智能总结**对话历史

### ⚙️ 简单配置
- 交互式设置向导
- 支持多个 API 提供商
- 成本追踪和使用限制
- 常用场景的智能默认值

## 聊天中的常用命令

```
/config          # 配置 API 设置
/help            # 显示可用命令
/skills          # 列出可用技能
```

## 为什么选择 OpenClacky？

✅ **安装简单** - 一条命令安装，立即开始对话  
✅ **功能强大** - 自主执行复杂任务  
✅ **可扩展** - 为你的工作流创建自定义技能  
✅ **省钱高效** - 智能记忆压缩节省 token 费用  
✅ **多平台** - 支持 OpenAI、Anthropic、MiniMax、OpenRouter 等  
✅ **质量保证** - 367+ 测试用例确保可靠性  

## 了解更多

- GitHub：https://github.com/clacky-ai/openclacky
- 问题反馈：https://github.com/clacky-ai/openclacky/issues
- 当前版本：0.7.0
