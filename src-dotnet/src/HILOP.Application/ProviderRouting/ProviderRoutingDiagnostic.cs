namespace HILOP.Application.ProviderRouting;

public sealed record ProviderRoutingDiagnostic
{
    public string ProviderId { get; init; } = string.Empty;

    public string Implementation { get; init; } = string.Empty;

    public string Capability { get; init; } = string.Empty;

    public string CorrelationId { get; init; } = string.Empty;

    public long DurationMilliseconds { get; init; }

    public string Status { get; init; } = string.Empty;

    public bool PowerShellProcessLaunched { get; init; }
}
