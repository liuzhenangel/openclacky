# Deploy Architecture - 部署架构文档

**Last Updated**: 2026-04-11

本文档描述 OpenClacky 部署功能的完整架构，包括客户端（openclacky gem）、后端 API（cloud_backend）和 Railway 平台之间的交互。

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenClacky 客户端 (Ruby Gem)                │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          Deploy Skill (default_skills/deploy/)            │  │
│  │  - 项目类型检测                                           │  │
│  │  - Rails Template 或 Generic Subagent 路由               │  │
│  │  - 工具调用：set_deploy_variables, check_health          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↓                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         DeployApiClient (lib/clacky/deploy_api_client.rb) │  │
│  │  - create_task()  # 创建部署任务                          │  │
│  │  - services()     # 轮询中间件状态                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↓                                   │
│                   使用 project token 调用                       │
│                   Railway CLI: railway variables --set          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    HTTP API (JSON over TLS)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Clacky Cloud Backend (Go Service)                   │
│              https://api.clacky.ai                               │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  POST /openclacky/v1/deploy/create-task                   │  │
│  │  - 创建 PlatformProject（如果不存在）                     │  │
│  │  - 创建 project token: CreateProjectToken()               │  │
│  │  - 部署 Postgres 中间件（使用 master token）             │  │
│  │  - 返回 project token 给客户端                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↓                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GET /openclacky/v1/deploy/services                        │  │
│  │  - 查询 Railway 服务状态                                   │  │
│  │  - 客户端轮询直到 Postgres 就绪                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↓                                   │
│                   使用 master token 调用                        │
│                   Railway GraphQL API                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                         GraphQL API
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Railway Platform                             │
│                                                                   │
│  ┌─────────────────────────┐                                    │
│  │  Clacky Master Account  │                                    │
│  │  (单一 Railway Workspace) │                                  │
│  └─────────────────────────┘                                    │
│              │                                                   │
│              ├─ User A's Project ──┬─ main-service              │
│              │  (project token 1)  ├─ postgres-service          │
│              │                     └─ redis-service             │
│              │                                                   │
│              ├─ User B's Project ──┬─ app-service               │
│              │  (project token 2)  └─ postgres-service          │
│              │                                                   │
│              └─ User C's Project ──┬─ api-service               │
│                 (project token 3)  └─ postgres-service          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Railway Token 架构

### 2.1 Token 类型

| Token 类型 | 持有者 | 用途 | 权限范围 |
|-----------|--------|------|---------|
| **Master Token** (Account Token) | Clacky Backend | 创建 Project<br>创建 Project Token<br>部署中间件 | 整个 Workspace 的所有资源 |
| **Project Token** | OpenClacky 客户端 | 注入环境变量<br>重新部署服务 | 单个 Project 内的有限操作 |

### 2.2 Project Token 权限矩阵

> 来源: [railway-sdk README](https://github.com/crisog/railway-sdk) - Official Railway SDK

| API Category       | Project Token 权限 | 说明 |
|--------------------|--------------------|------|
| **projects/**      | ⚠️ Get Only         | 只能读取当前 project 信息，**不能删除 project** |
| **services/**      | ✅ Full Access      | 可创建/删除/管理 services |
| **environments/**  | ✅ Full Access      | 可管理 environments |
| **deployments/**   | ❌ Not Authorized   | **不能列出或管理 deployments** |
| **variables/**     | ✅ Full Access      | 可设置/查看所有环境变量（含密码） |
| **domains/**       | ✅ Full Access      | 可创建/删除域名 |
| **templates/**     | ⚠️ Existing Project | 可在现有 project 中部署 template（如 postgres） |
| **networking/**    | ✅ Full Access      | 可管理网络配置 |
| **observability/** | ⚠️ Events Only      | 只能查看事件，不能访问 metrics |
| **workflows/**     | ❌ Not Authorized   | 无权限 |
| **integrations/**  | ❌ Not Authorized   | 无法管理 GitHub 集成 |
| **volumes/**       | ⚠️ Backups Only     | 只能管理备份 |
| **account/**       | ❌ Not Authorized   | 无账户访问权限 |

**关键引用**: "Has broad access within the scoped project but **cannot list deployments or access metrics**."

### 2.3 安全性分析

#### ✅ Project Token 的限制

- ❌ **不能删除 project** - 只有 Get 权限
- ❌ **不能查看 deployments** - 无权限访问
- ❌ **不能管理 GitHub 集成** - 无权限

#### ⚠️ Project Token 仍可做的危险操作

尽管有上述限制，project token 仍然可以：

```bash
# 用户拿到 project token 后可以执行：
export RAILWAY_TOKEN=<project_token>

# 1. 删除服务
railway service delete --service postgres

# 2. 查看所有密码
railway variables --json

# 3. 修改数据库密码
railway variables --set POSTGRES_PASSWORD=hacked

# 4. 修改域名配置
railway domain delete

# 5. 修改网络配置
railway networking ...
```

#### ✅ Backend API 的安全优势

**为什么必须使用 Backend API 而不是让用户本地使用 Railway CLI：**

1. **细粒度权限控制**
   - Backend 可限制用户只能注入变量，禁止删除服务
   - Backend 可实施业务规则（如禁止删除 postgres）
   
2. **审计日志**
   - 所有操作记录在 `deploy_task_logs` 表
   - 可追溯谁在何时做了什么操作
   
3. **Token 隔离**
   - 用户永远看不到 token
   - Token 只在 backend 和客户端内存中短暂存在
   
4. **输入验证**
   - Backend 验证参数合法性
   - 防止注入攻击和恶意参数
   
5. **业务逻辑保护**
   - Backend 可实施复杂的业务规则
   - 例如：防止误删生产数据库、限制资源配额

**如果让用户本地使用 Railway CLI 的风险：**

- ❌ 用户拥有 services 完全访问权限（删除、重启）
- ❌ 用户可查看/修改所有环境变量（含密码）
- ❌ 用户可修改域名和网络配置
- ❌ 无审计日志（本地操作无法追踪）
- ❌ Token 存储在用户机器（泄露风险）

---

## 3. 部署流程详解

### 3.1 数据库创建流程（Step 4）

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 4a: 客户端调用 Backend API                                  │
└─────────────────────────────────────────────────────────────────┘
         │
         │ POST /openclacky/v1/deploy/create-task
         │ { project_id, backup_db, env_vars, region }
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4b: Backend 处理（cloud_backend/internal/deployment）      │
│                                                                   │
│  1. 检查 PlatformProject 是否存在                                │
│     - 不存在 → 调用 EnsurePlatformProject()                     │
│       ├─ 创建 Railway Project (使用 master token)               │
│       ├─ 创建 Project Token                                      │
│       │  token, err := cli.GetClient().CreateProjectToken(      │
│       │      ctx, projectID, envID, tokenName)                  │
│       └─ 存储到 platform_project 表                              │
│                                                                   │
│  2. 部署 Postgres 中间件（使用 master token）                   │
│     cli.GetClient().DeployTemplateWithConfig(ctx,               │
│         railway.TemplateDeployOptions{                           │
│             ProjectID:     pp.PlatformProjectID,                │
│             EnvironmentID: pp.PlatformEnvironmentID,            │
│             TemplateCode:  "postgres",                          │
│             ServiceName:   "Postgres-xxxx",                     │
│             Region:        task.Region,                         │
│         })                                                       │
│                                                                   │
│  3. 返回响应给客户端                                             │
│     {                                                            │
│       deploy_task_id,                                            │
│       deploy_service_id,                                         │
│       platform_token,         # ← Project Token                 │
│       platform_project_id,                                       │
│       platform_environment_id                                    │
│     }                                                            │
└─────────────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4c: 客户端轮询服务状态                                       │
│                                                                   │
│  loop do                                                         │
│    response = GET /openclacky/v1/deploy/services?               │
│                   deploy_task_id=xxx                             │
│                                                                   │
│    postgres = response.find { |s| s.type == 'postgres' }        │
│    break if postgres && postgres.status == 'SUCCESS'            │
│                                                                   │
│    sleep 5  # 每 5 秒轮询一次                                     │
│  end                                                             │
└─────────────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4d: Postgres 就绪，注入 DATABASE_URL                        │
│                                                                   │
│  # 使用客户端本地的 Railway CLI                                  │
│  env = { "RAILWAY_TOKEN" => platform_token }  # Project Token   │
│                                                                   │
│  system(env,                                                     │
│    "railway", "variables",                                       │
│    "--service", main_service_name,                              │
│    "--set", "DATABASE_URL=${{Postgres-xxxx.DATABASE_PUBLIC_URL}}",│
│    in: :close, out: File::NULL)                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 关键设计决策

| 操作 | 使用的 Token | 执行位置 | 原因 |
|------|-------------|---------|------|
| **创建 Project** | Master Token | Backend | 需要 Workspace 级别权限 |
| **创建 Project Token** | Master Token | Backend | 需要 Workspace 级别权限 |
| **部署 Postgres** | Master Token | Backend | 统一管理，后端控制 |
| **注入环境变量** | Project Token | Client | 减轻后端负载，允许客户端重试 |
| **重新部署服务** | Project Token | Client | 允许用户直接控制 |

**为什么数据库创建用 Backend，但变量注入用 Client？**

1. **数据库创建（Backend）**:
   - 需要 master token（project token 也可以部署 template，但 backend 统一管理更安全）
   - 涉及资源创建和计费
   - 需要审计和速率限制
   - 异步操作，适合后端处理

2. **变量注入（Client）**:
   - 操作简单，适合客户端重试
   - 减轻后端负载（不需要每个变量都调用 backend API）
   - 用户可以快速调整配置
   - Project token 足够且安全（只能修改自己 project 的变量）

---

## 4. Railway CLI 调用方式

### 4.1 问题：`Open3.capture3` 导致挂起

**现象**:
```ruby
# ❌ 这样会挂起
env = { "RAILWAY_TOKEN" => token }
out, err, status = Open3.capture3(env, *cmd)
```

**原因**:
- `Open3.capture3` 使用管道捕获 stdout/stderr
- Railway CLI 可能等待管道缓冲区清空或检测到非 TTY 环境
- 导致死锁

### 4.2 解决方案：使用 `system()`

**正确方式**:
```ruby
# ✅ 这样不会挂起
env = { "RAILWAY_TOKEN" => token }
success = system(env, *cmd, in: :close, out: File::NULL)
```

**为什么有效**:
- `system()` 继承父进程的 stdin/stdout/stderr（无管道）
- `in: :close` 防止 Railway CLI 等待 stdin 输入
- `out: File::NULL` 抑制 stdout 输出（我们不需要）
- stderr 保持可见（用于调试）

**使用场景**:

| 操作 | 使用方法 | 原因 |
|------|---------|------|
| `railway variables --set` | `system()` | 避免挂起，不需要输出 |
| `railway status --json` | `Open3.capture3` | 需要解析 JSON 输出 |
| `railway up --detach` | `Open3.capture3` | 需要检查 "Build Logs:" 输出 |

**相关文件**:
- `lib/clacky/default_skills/deploy/tools/set_deploy_variables.rb`

---

## 5. 关键代码路径

### 5.1 Backend (Go)

```
cloud_backend/
├── internal/deployment/service/
│   ├── create.go              # POST /deploy/create-task
│   │   └─ buildStartDeploySyncResponse()  # 构造响应（含 platform_token）
│   │
│   ├── middleware.go          # 中间件（数据库）部署逻辑
│   │   ├─ ensureMiddlewares()        # 确保 Postgres 存在
│   │   ├─ deployMiddleware()         # 部署单个中间件
│   │   └─ deployMiddlewareWithRetry() # 重试逻辑（最多 3 次）
│   │
│   ├── ensure.go              # PlatformProject 管理
│   │   ├─ EnsurePlatformProject()    # 创建或获取 PlatformProject
│   │   └─ CreateProjectToken()       # line 83: 创建 project token
│   │
│   └── pool_integration.go    # Railway 项目池集成
│
├── common/railway-go/pkg/railway/
│   ├── token.go               # Token 管理
│   │   └─ CreateProjectToken() # 封装 createProjectTokenRaw()
│   │
│   ├── graphql_raw.go         # GraphQL 底层调用
│   │   └─ createProjectTokenRaw() # GraphQL mutation
│   │
│   └── service.go             # Service 管理
│       ├─ CreateService()
│       ├─ DeleteService()
│       └─ DeployTemplateWithConfig() # 部署 template（如 postgres）
│
└── internal/infra/gen/model/
    └── platform_project.gen.go  # PlatformProject 数据模型
        ├─ PlatformToken           # 存储 project token
        ├─ PlatformTokenName
        └─ TokenExpiresAt
```

### 5.2 Client (Ruby)

```
openclacky/
├── lib/clacky/
│   ├── deploy_api_client.rb   # Backend API 客户端
│   │   ├─ create_task()       # POST /deploy/create-task
│   │   └─ services()          # GET /deploy/services (轮询)
│   │
│   └── default_skills/deploy/
│       ├── SKILL.md            # Deploy skill 入口
│       │
│       ├── templates/
│       │   └── rails_deploy.rb  # Rails 固定脚本
│       │
│       ├── subagent/
│       │   └── DEPLOY_ROLE.md   # Generic 部署 subagent
│       │
│       └── tools/
│           ├── set_deploy_variables.rb  # 注入环境变量
│           │   ├─ set_batch()    # 批量设置（使用 system()）
│           │   └─ set_one()      # 单个设置（使用 system()）
│           │
│           ├── list_services.rb         # 列出服务
│           ├── execute_deployment.rb    # 执行部署
│           ├── fetch_runtime_logs.rb    # 获取日志
│           └── check_health.rb          # 健康检查
│
└── docs/
    ├── deploy_subagent_design.md  # Deploy skill 设计文档
    └── deploy-architecture.md     # 本文档
```

---

## 6. 数据流示例

### 6.1 首次部署（创建 Project + 数据库）

```
1. 用户: "Deploy my Rails app"
   ↓
2. Deploy Skill 检测到 Rails 项目
   ↓
3. Rails Template 执行 Step 1-3（检查服务、设置变量）
   ↓
4. Step 4: 客户端调用 Backend API
   POST /deploy/create-task
   {
     project_id: "abc123",
     backup_db: false,
     env_vars: {},
     region: "us-west2"
   }
   ↓
5. Backend 处理:
   a. EnsurePlatformProject("abc123")
      - Railway CreateProject() [使用 master token]
      - CreateProjectToken(projectID, envID, tokenName)
      - 存储 platform_project 记录
   
   b. deployMiddleware("postgres")
      - DeployTemplateWithConfig("postgres") [使用 master token]
      - 保存 deploy_service 记录（status: initializing）
   
   c. 返回响应:
      {
        deploy_task_id: "task-xyz",
        deploy_service_id: "svc-123",
        platform_token: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",  # ← Project Token
        platform_project_id: "railway-proj-456",
        platform_environment_id: "railway-env-789"
      }
   ↓
6. 客户端轮询:
   loop do
     services = GET /deploy/services?deploy_task_id=task-xyz
     postgres = services.find { |s| s.type == 'postgres' }
     break if postgres.status == 'SUCCESS'
     sleep 5
   end
   ↓
7. Postgres 就绪后，客户端注入 DATABASE_URL:
   env = { "RAILWAY_TOKEN" => platform_token }
   system(env,
     "railway", "variables", "--service", "main-app",
     "--set", "DATABASE_URL=${{Postgres-abc.DATABASE_PUBLIC_URL}}",
     in: :close, out: File::NULL)
   ↓
8. 继续执行 Rails Template 的 Step 5-8
   - 执行部署
   - 运行 db:migrate
   - 运行 db:seed（首次）
   - 健康检查
   - 报告成功
```

### 6.2 后续部署（Project 已存在）

```
1. 用户: "Deploy again"
   ↓
2. Rails Template 执行
   ↓
3. Step 4: POST /deploy/create-task (project_id 已存在)
   ↓
4. Backend:
   - PlatformProject 已存在，跳过创建
   - Postgres 已存在，跳过部署
   - 直接返回现有 platform_token
   ↓
5. 客户端:
   - services() 返回现有 Postgres（已是 SUCCESS）
   - 跳过轮询，直接注入变量
   - 执行部署
   - 运行 db:migrate（跳过 db:seed）
```

---

## 7. 优化机会（未实现）

### 7.1 Webhook 通知（已有基础设施）

**当前**: 客户端每 5 秒轮询一次 `/deploy/services`

**可优化**: 使用 Railway Webhook 主动通知

```ruby
# Backend 已经创建了 webhook:
webhook, err := cli.GetClient().CreateWebhook(ctx, pp.ID, webhookURL, nil)

# 可以实现:
# 1. Railway → Backend Webhook: "Postgres deployment completed"
# 2. Backend → SSE / WebSocket: 推送给客户端
# 3. 客户端无需轮询，立即收到通知
```

**优点**:
- 减少 API 调用量
- 更快的响应时间
- 更好的用户体验

### 7.2 缩短轮询间隔

```ruby
# 当前: 每 5 秒轮询
sleep 5

# 可改为: 每 2 秒轮询（更快反馈）
sleep 2
```

### 7.3 并行操作

```ruby
# 当前: 串行执行
# Step 4a: 创建数据库
# Step 4b: 等待数据库就绪
# Step 4c: 注入变量

# 可优化: 部分并行
# Thread 1: 监控数据库状态
# Thread 2: 准备其他环境变量
# 数据库就绪后，立即注入所有变量
```

---

## 8. 故障排查指南

### 8.1 部署挂起在 Step 3（变量注入）

**症状**: 执行 `railway variables --set` 时无响应

**原因**: 使用了 `Open3.capture3`

**解决**:
```ruby
# 修改 set_deploy_variables.rb
# 将 Open3.capture3 改为 system()
success = system(env, *cmd, in: :close, out: File::NULL)
```

### 8.2 无法创建 Project Token

**症状**: Backend 返回 "failed to create project token"

**检查**:
1. Railway master token 是否有效
2. Railway API 是否可达
3. 是否达到 token 数量限制

**日志位置**:
```
cloud_backend/internal/deployment/service/ensure.go:85
```

### 8.3 Postgres 部署失败

**症状**: 轮询超时，Postgres 状态一直是 `initializing`

**检查**:
1. Railway 账户余额
2. 区域是否支持 Postgres
3. Backend 日志中的重试信息

**相关代码**:
```
cloud_backend/internal/deployment/service/middleware.go
- deployMiddlewareWithRetry() # 最多重试 3 次
```

### 8.4 DATABASE_URL 注入失败

**症状**: 主服务找不到数据库连接

**检查**:
1. Postgres 服务名称是否正确
2. Railway 变量引用语法: `${{Service-Name.VARIABLE}}`
3. Project token 是否有效

**调试命令**:
```bash
# 手动检查变量
export RAILWAY_TOKEN=<project_token>
railway variables --service main-app --json
```

---

## 9. 参考资料

### 9.1 官方文档

- [Railway Public API](https://docs.railway.com/integrations/api)
- [Railway Project Tokens](https://docs.railway.com/integrations/api#project-tokens)

### 9.2 非官方 SDK

- [railway-sdk (TypeScript)](https://github.com/crisog/railway-sdk) - 包含详细的 token 权限矩阵

### 9.3 内部文档

- `openclacky/docs/deploy_subagent_design.md` - Deploy skill 设计
- `openclacky/docs/openclacky_cloud_api_reference.md` - License API 参考
- `~/.clacky/memories/deploy-railway-cli-system-call.md` - Railway CLI 调用问题和解决方案

---

## 10. 更新历史

| 日期 | 版本 | 变更说明 |
|------|------|---------|
| 2026-04-11 | 1.0.0 | 初始版本，包含完整架构说明、token 权限矩阵、安全分析 |

---

**维护者**: OpenClacky Team  
**反馈**: 如发现文档有误或需要补充，请提 Issue 或 PR
