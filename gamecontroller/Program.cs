using gamecontroller.Singletons;

var builder = WebApplication.CreateBuilder(args);

// Self-host: listen on every interface so players outside this machine can reach the server browser.
// Override with ASPNETCORE_URLS (e.g. "http://0.0.0.0:5000").
if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ASPNETCORE_URLS")) && builder.Configuration["urls"] == null)
{
    builder.WebHost.UseUrls("http://0.0.0.0:5000");
}

// Add services to the container.

builder.Services.AddControllers();

builder.Services.AddSingleton<GameSessions>();

builder.Services.AddSingleton<DatabaseSessions>();

builder.Services.AddHostedService<SessionCleanupService>();

var app = builder.Build();

// Configure the HTTP request pipeline.

app.UseAuthorization();

app.MapControllers();

app.Run();
