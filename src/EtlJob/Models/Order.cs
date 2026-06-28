namespace EtlJob.Models;

public record Order(
    string OrderId,
    string Region,
    string CustomerName,
    decimal? Amount,     // nullable — rows with null Amount are treated as invalid
    DateTime CreatedAt
);
