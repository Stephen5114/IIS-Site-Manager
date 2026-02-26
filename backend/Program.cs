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
builder.Services.AddOpenApi();

var app = builder.Build();

app.UseCors();

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseHttpsRedirection();

// System monitoring endpoints (/api/* for dev, /* for IIS sub-app)
app.MapGet("/api/metrics", (SystemMonitorService monitor) =>
{
    var (cpu, memPercent, memUsed, memTotal) = monitor.GetMetrics();
    return new SystemMetrics(cpu, memPercent, memUsed, memTotal, DateTime.UtcNow);
});
app.MapGet("/metrics", (SystemMonitorService monitor) =>
{
    var (cpu, memPercent, memUsed, memTotal) = monitor.GetMetrics();
    return new SystemMetrics(cpu, memPercent, memUsed, memTotal, DateTime.UtcNow);
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

app.Run();
