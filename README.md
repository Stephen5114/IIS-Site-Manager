# IIS Site Manager

简单的 IIS 站点管理工具，支持创建站点、监控 CPU 和内存。

- **前端**: Next.js + TypeScript + Tailwind + Recharts
- **后端**: .NET 10 Web API

## 目录结构

```
IIS-Site-Manager/
├── backend/          # .NET 10 Web API
├── frontend/         # Next.js 前端
└── README.md
```

## 功能

- 创建 IIS 站点（站点名、域名、物理路径、应用池、端口）
- 实时 CPU 和 RAM 监控（每 3 秒刷新）
- CPU/RAM 历史曲线图
- 站点列表展示

## 运行

### 开发模式

1. **后端**：`cd backend && dotnet run`（默认 http://localhost:5032）
2. **前端**：`cd frontend && npm run dev`（默认 http://localhost:3000）
3. 创建 IIS 站点需以**管理员**身份运行后端

### IIS 部署

1. 构建：`cd deploy && .\build.ps1`
2. 部署：以管理员运行 `.\setup-iis.ps1`
3. 访问：http://localhost:8081（前端）| http://localhost:8081/api（API）

详见 `deploy/DEPLOY.md`。

## API 接口

| 方法 | 路径 | 说明 |
|-----|------|------|
| GET | `/api/metrics` | 获取 CPU、内存指标 |
| GET | `/api/sites` | 获取站点列表 |
| POST | `/api/sites` | 创建站点（JSON body） |

## 技术栈

- **前端**: Next.js 15, React 19, Tailwind CSS, Recharts
- **后端**: ASP.NET Core 10, Microsoft.Web.Administration, System.Diagnostics.PerformanceCounter
