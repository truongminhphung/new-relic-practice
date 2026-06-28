using System.Diagnostics;
using EtlJob.Data;
using EtlJob.Models;
using Microsoft.Extensions.Logging;

namespace EtlJob.Etl;

public class Extractor(ILogger<Extractor> logger)
{
    public IReadOnlyList<Order> Extract()
    {
        logger.LogInformation("EXTRACT: generating sample orders...");
        var sw = Stopwatch.StartNew();
        var rows = SampleDataGenerator.Generate();
        sw.Stop();
        logger.LogInformation("EXTRACT: generated {Count} rows in {ElapsedMs} ms", rows.Count, sw.ElapsedMilliseconds);
        return rows;
    }
}
