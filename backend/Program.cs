using IIS_Site_Manager.API.Models;
using IIS_Site_Manager.API.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});
builder.Services.AddSingleton<IISService>();
builder.Services.AddSingleton<SystemMonitorService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<SystemMonitorService>());
builder.Services.AddOpenApi();

var app = builder.Build();

app.UseCors();

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseHttpsRedirection();

// Static files before API (so / serves index.html, /api/* goes to endpoints)
var wwwroot = Path.Combine(app.Environment.ContentRootPath, "wwwroot");
if (Directory.Exists(wwwroot))
{
    app.UseDefaultFiles();
    app.UseStaticFiles();
}

// API routes
app.MapGet("/api/metrics", (SystemMonitorService monitor) =>
{
    var (cpu, memPercent, memUsed, memTotal, bytesRecv, bytesSent) = monitor.GetMetrics();
    return new SystemMetrics(cpu, memPercent, memUsed, memTotal, bytesRecv, bytesSent, bytesRecv + bytesSent, DateTime.UtcNow);
});
app.MapGet("/metrics", (SystemMonitorService monitor) =>
{
    var (cpu, memPercent, memUsed, memTotal, bytesRecv, bytesSent) = monitor.GetMetrics();
    return new SystemMetrics(cpu, memPercent, memUsed, memTotal, bytesRecv, bytesSent, bytesRecv + bytesSent, DateTime.UtcNow);
}).WithName("GetMetrics");

// IIS endpoints
app.MapGet("/api/sites", (IISService iis) => iis.ListSites());
app.MapGet("/sites", (IISService iis) => iis.ListSites()).WithName("ListSites");
app.MapPost("/api/sites", (CreateSiteRequest req, IISService iis) =>
{
    var (success, message) = iis.CreateSite(
        req.SiteName,
        req.Domain,
        req.PhysicalPath,
        req.AppPoolName,
        req.Port);
    return success ? Results.Ok(new { success, message }) : Results.BadRequest(new { success, message });
});
app.MapPost("/sites", (CreateSiteRequest req, IISService iis) =>
{
    var (success, message) = iis.CreateSite(req.SiteName, req.Domain, req.PhysicalPath, req.AppPoolName, req.Port);
    return success ? Results.Ok(new { success, message }) : Results.BadRequest(new { success, message });
}).WithName("CreateSite");

// SPA fallback: unmatched routes -> index.html
if (Directory.Exists(wwwroot))
    app.MapFallbackToFile("index.html");

app.Run();
