using EtlJob.Etl;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

var runId = Guid.NewGuid().ToString("N")[..8];
var startedAt = DateTime.UtcNow;

using var services = new ServiceCollection()
    .AddLogging(b => b.AddSimpleConsole(o =>
    {
        o.SingleLine = true;
        o.TimestampFormat = "HH:mm:ss.fff ";
    }))
    .AddSingleton<Extractor>()
    .AddSingleton<Transformer>()
    .AddSingleton<Loader>()
    .BuildServiceProvider();

var logger = services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("ETL job starting. RunId={RunId}|StartedAt={StartedAt:O}", runId, startedAt);

try
{
    var rows   = services.GetRequiredService<Extractor>().Extract();
    var result = services.GetRequiredService<Transformer>().Transform(rows);
    services.GetRequiredService<Loader>().Load(result);

    var durationMs = (DateTime.UtcNow - startedAt).TotalMilliseconds;
    logger.LogInformation(
        "ETL job finished OK. RunId={RunId}|Status=Success|Processed={Processed}|Skipped={Skipped}|DurationMs={DurationMs:F0}",
        runId, result.Processed, result.Skipped, durationMs);

    return 0;
}
catch (Exception ex)
{
    logger.LogError(ex, "ETL job failed. RunId={RunId}|Status=Failed", runId);
    return 1;
}
