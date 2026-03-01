# IIS-Site-Manager 部署说明

## 部署到本地 IIS

### 方式一：使用预构建包（已构建）

1. 以**管理员身份**运行 PowerShell
2. 执行：`cd deploy; .\setup-iis.ps1`
3. 访问：http://服务器IP或主机名:8081（支持远程访问）

### 方式二：从源码构建

1. 构建：`cd deploy; .\build.ps1`
2. 部署：以管理员运行 `.\setup-iis.ps1`
3. 访问：http://服务器IP或主机名:8081

## 目录结构

- `api/` - 后端 + 前端（ASP.NET Core 主站，wwwroot 为静态文件）
- `build.ps1` - 构建脚本（后端 + 前端）
- `setup-iis.ps1` - IIS 配置脚本

## 注意事项

- 构建时会自动停止 IIS 站点以释放文件锁
- 应用池使用 **NetworkService** 身份以读取 CPU/带宽性能计数器
- 通过 Web 界面创建站点需管理员权限；若需创建站点，建议以管理员身份运行 `dotnet run` 单独启动后端
- 带宽监控：优先使用 IIS Web Service 计数器，失败时回退到 Network Interface
- 站点绑定 `*:8081`，支持远程访问；脚本会自动添加防火墙规则放行 8081 端口
