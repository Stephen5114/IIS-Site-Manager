using Microsoft.Web.Administration;

namespace IIS_Site_Manager.API.Services;

public class IISService
{
    public (bool Success, string Message) CreateSite(string siteName, string domain, string physicalPath, string appPoolName, int port)
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                using var serverManager = new ServerManager();

                // Check if site name or domain already exists
                if (serverManager.Sites.Any(s => s.Name.Equals(siteName, StringComparison.OrdinalIgnoreCase)))
                    return (false, $"Site '{siteName}' already exists.");

                if (serverManager.Sites.Any(s => s.Bindings.Any(b =>
                    b.Host.Equals(domain, StringComparison.OrdinalIgnoreCase))))
                    return (false, $"Domain '{domain}' is already bound to another site.");

                // Create physical directory if not exists
                var path = Path.GetFullPath(physicalPath.Trim().TrimEnd(Path.DirectorySeparatorChar, '/', '\\'));
                if (!Directory.Exists(path))
                {
                    try
                    {
                        Directory.CreateDirectory(path);
                    }
                    catch (Exception ex)
                    {
                        return (false, $"Failed to create folder '{path}': {ex.Message}");
                    }
                }

                // Ensure app pool exists
                var pool = serverManager.ApplicationPools[appPoolName];
                if (pool == null)
                {
                    pool = serverManager.ApplicationPools.Add(appPoolName);
                    pool.ManagedRuntimeVersion = "";
                    pool.ManagedPipelineMode = ManagedPipelineMode.Integrated;
                }

                // Create the site
                var siteId = GetNextSiteId(serverManager);
                var site = serverManager.Sites.Add(siteName, "http", $"*:{port}:{domain}", path);
                site.Id = siteId;
                site.ApplicationDefaults.ApplicationPoolName = appPoolName;
                site.ServerAutoStart = true;

                // Add www binding if domain doesn't start with *
                if (!domain.StartsWith("*"))
                    site.Bindings.Add($"*:{port}:www.{domain}", "http");

                serverManager.CommitChanges();

                // Add default index.html if folder is empty
                try
                {
                    if (Directory.GetFiles(path).Length == 0 && Directory.GetDirectories(path).Length == 0)
                    {
                        var defaultHtml = """
                            <!DOCTYPE html>
                            <html><head><title>Welcome</title><meta charset="utf-8"></head>
                            <body><h1>Site is ready</h1><p>Your IIS site is working. Replace this file with your own content.</p></body>
                            </html>
                            """;
                        File.WriteAllText(Path.Combine(path, "index.html"), defaultHtml);
                    }
                }
                catch { /* Ignore default page creation errors */ }

                return (true, $"Site '{siteName}' and folder created successfully.");
            }
            catch (Exception ex)
            {
                return (false, $"Failed to create site: {ex.Message}");
            }
        }

        return (false, "IIS site creation is only supported on Windows.");
    }

    public List<object> ListSites()
    {
        if (!OperatingSystem.IsWindows())
            return [];

        try
        {
            using var serverManager = new ServerManager();
            return serverManager.Sites
                .Where(s => s.Name != "Default Web Site")
                .Select(s => (object)new
                {
                    Id = s.Id,
                    Name = s.Name,
                    State = s.State.ToString(),
                    Bindings = s.Bindings.Select(b => $"{b.Protocol}://{b.BindingInformation}").ToList(),
                    PhysicalPath = s.Applications["/"]?.VirtualDirectories["/"]?.PhysicalPath ?? ""
                })
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    static long GetNextSiteId(ServerManager manager)
    {
        var maxId = manager.Sites.Max(s => (long?)s.Id) ?? 0;
        return maxId + 1;
    }
}
