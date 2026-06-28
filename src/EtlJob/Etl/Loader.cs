using Microsoft.Extensions.Logging;

namespace EtlJob.Etl;

public class Loader(ILogger<Loader> logger)
{
    public void Load(TransformResult result)
    {
        logger.LogInformation("LOAD: writing {Count} aggregate records to sink...", result.RegionSummaries.Count);

        foreach (var summary in result.RegionSummaries)
        {
            logger.LogInformation(
                "LOAD: Region={Region} Orders={OrderCount} TotalAmount={TotalAmount:F2}",
                summary.Region, summary.OrderCount, summary.TotalAmount);
        }

        logger.LogInformation("LOAD: load complete");
    }
}
