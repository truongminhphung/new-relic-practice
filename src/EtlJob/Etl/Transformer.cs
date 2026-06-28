using EtlJob.Models;
using Microsoft.Extensions.Logging;

namespace EtlJob.Etl;

public record TransformResult(IReadOnlyList<RegionSummary> RegionSummaries, int Processed, int Skipped);

public class Transformer(ILogger<Transformer> logger)
{
    public TransformResult Transform(IReadOnlyList<Order> orders)
    {
        logger.LogInformation("TRANSFORM: validating + normalizing {Count} rows...", orders.Count);

        var valid = new List<Order>(orders.Count);
        int skipped = 0;

        foreach (var order in orders)
        {
            if (order.Amount is null or <= 0)
            {
                skipped++;
                continue;
            }
            valid.Add(order);
        }

        if (skipped > 0)
            logger.LogWarning("TRANSFORM: skipped {Skipped} invalid rows (missing or zero amount)", skipped);

        var summaries = valid
            .GroupBy(o => o.Region)
            .Select(g => new RegionSummary(
                Region:      g.Key,
                OrderCount:  g.Count(),
                TotalAmount: Math.Round(g.Sum(o => o.Amount!.Value), 2)))
            .OrderBy(s => s.Region)
            .ToList();

        logger.LogInformation("TRANSFORM: aggregated to {RegionCount} region totals", summaries.Count);

        return new TransformResult(summaries, valid.Count, skipped);
    }
}
