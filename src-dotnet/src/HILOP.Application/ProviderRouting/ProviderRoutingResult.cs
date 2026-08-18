namespace HILOP.Application.ProviderRouting;

public sealed record ProviderRoutingResult<T>
{
    public required T Value { get; init; }

    public required ProviderRoutingDiagnostic Diagnostic { get; init; }
}
