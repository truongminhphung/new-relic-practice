using EtlJob.Models;

namespace EtlJob.Data;

public static class SampleDataGenerator
{
    private static readonly string[] Regions =
        ["APAC", "EMEA", "NA", "LATAM", "ANZ"];

    private static readonly string[] Customers =
    [
        "Alice Wong",       "Bob Smith",       "Carlos Garcia",  "Diana Chen",    "Edward Kim",
        "Fiona Patel",      "George Brown",    "Hannah Lee",     "Ivan Petrov",   "Julia Santos",
        "Kevin Zhang",      "Laura Müller",    "Mohammed Hassan","Nina Johansson","Oscar Tran",
    ];

    // These row indices will have Amount = null to trigger WARN logs in the Transformer
    private static readonly HashSet<int> InvalidIndices = [7, 23, 41, 58, 72];

    public static IReadOnlyList<Order> Generate(int count = 100)
    {
        var result = new List<Order>(count);
        var baseDate = DateTime.UtcNow.Date.AddDays(-count);

        for (int i = 0; i < count; i++)
        {
            result.Add(new Order(
                OrderId:      $"ORD-{i + 1:D4}",
                Region:       Regions[i % Regions.Length],
                CustomerName: Customers[i % Customers.Length],
                Amount:       InvalidIndices.Contains(i) ? null : Math.Round((decimal)(10 + i * 7.3 % 990), 2),
                CreatedAt:    baseDate.AddDays(i)
            ));
        }

        return result;
    }
}
