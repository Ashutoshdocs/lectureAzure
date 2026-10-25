// Minimal ASP.NET Core web app for Azure App Service (.NET runtime stack).
// No NuGet packages: only the built-in ASP.NET Core framework.
using System.Diagnostics;
using System.Runtime.InteropServices;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
var startedAt = DateTime.UtcNow;

// Serve wwwroot/index.html at "/" and other static files from wwwroot.
app.UseDefaultFiles();
app.UseStaticFiles();

// --- API routes ---
app.MapGet("/api/health", () => Results.Ok(new
{
    status = "healthy",
    time = DateTime.UtcNow.ToString("o")
}));

app.MapGet("/api/info", () => Results.Ok(new
{
    app = "dotnet10-webapp-demo",
    runtime = RuntimeInformation.FrameworkDescription,          // e.g. ".NET 10.0.x"
    platform = $"{RuntimeInformation.OSDescription} {RuntimeInformation.OSArchitecture}",
    hostname = Environment.MachineName,
    siteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME") ?? "local",
    region = Environment.GetEnvironmentVariable("REGION_NAME") ?? "local",
    uptimeSeconds = (int)(DateTime.UtcNow - startedAt).TotalSeconds,
    memoryMB = Process.GetCurrentProcess().WorkingSet64 / 1024 / 1024
}));

// Azure App Service (Linux) routes traffic to the port it sets in ASPNETCORE_URLS / PORT,
// which ASP.NET Core picks up automatically. Locally it uses launch defaults.
app.Run();
