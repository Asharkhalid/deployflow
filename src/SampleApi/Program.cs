var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.MapHealthChecks("/health");

app.MapGet("/", () => new {
    Application = "DeployFlow Demo",
    Version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "1.0.0",
    Commit = Environment.GetEnvironmentVariable("COMMIT_SHA") ?? "Local",
    Environment = app.Environment.EnvironmentName,
    Hostname = System.Net.Dns.GetHostName(),
    Status = "Healthy"
});

app.MapGet("/version", () => new {
    Version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "1.0.0",
    Commit = Environment.GetEnvironmentVariable("COMMIT_SHA") ?? "Local",
    Built = Environment.GetEnvironmentVariable("BUILD_DATE") ?? DateTime.UtcNow.ToString("O")
});

app.MapGet("/environment", () => new {
    Environment = app.Environment.EnvironmentName,
    Hostname = System.Net.Dns.GetHostName()
});

app.MapGet("/uptime", () => new {
    Uptime = TimeSpan.FromMilliseconds(Environment.TickCount64).ToString("g")
});

app.Run();

