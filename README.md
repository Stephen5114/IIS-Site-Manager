# IIS Site Manager

简单的 IIS 站点管理工具，支持创建站点、监控 CPU、内存和带宽。

- **前端**: Next.js + TypeScript + Tailwind + Recharts
- **后端**: .NET 10 Web API

## 目录结构

```
IIS-Site-Manager/
├── backend/          # .NET 10 Web API 源码
├── frontend/         # Next.js 前端源码
├── deploy/           # IIS 部署包
│   ├── api/          # 后端 + 前端（单应用，wwwroot 为静态文件）
│   ├── build.ps1     # 构建脚本
│   ├── setup-iis.ps1 # IIS 配置脚本
│   └── DEPLOY.md     # 部署说明
└── README.md
```

## 功能

- 创建 IIS 站点（站点名、域名、物理路径、应用池、端口）
- 实时 CPU、RAM 和带宽监控（每 3 秒刷新）
- CPU/RAM/带宽历史曲线图
- 站点列表展示
- 支持远程访问（绑定 `*:8081`，自动放行防火墙）

## 运行

### 开发模式

1. **后端**：`cd backend && dotnet run`（默认 http://localhost:5032）
2. **前端**：`cd frontend && npm run dev`（默认 http://localhost:3000）
3. 创建 IIS 站点需以**管理员**身份运行后端

### IIS 部署（使用预构建包）

仓库已包含 `deploy/` 目录的预构建部署包，可直接部署到 IIS：

1. **以管理员身份**运行 PowerShell
2. 执行：`cd deploy; .\setup-iis.ps1`
3. 访问：http://服务器IP或主机名:8081（支持远程访问）

### IIS 部署（从源码构建）

1. 构建：`cd deploy; .\build.ps1`
2. 部署：以管理员运行 `.\setup-iis.ps1`
3. 访问：http://服务器IP或主机名:8081（支持远程访问）

详见 [`deploy/DEPLOY.md`](deploy/DEPLOY.md)。

## API 接口

| 方法 | 路径 | 说明 |
|-----|------|------|
| GET | `/api/metrics` | 获取 CPU、内存、带宽指标 |
| GET | `/api/sites` | 获取站点列表 |
| POST | `/api/sites` | 创建站点（JSON body） |

## 技术栈

- **前端**: Next.js 16, React 19, Tailwind CSS 4, Recharts
- **后端**: ASP.NET Core 10, Microsoft.Web.Administration, System.Diagnostics.PerformanceCounter, System.Management (WMI)

## 注意事项

- 应用池使用 **NetworkService** 身份以读取 CPU/带宽性能计数器
- 通过 Web 界面创建站点需管理员权限；若需创建站点，建议以管理员身份运行 `dotnet run` 单独启动后端
