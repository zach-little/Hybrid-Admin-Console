using HILOP.Providers.Abstractions;

namespace HILOP.Application.Status;

public sealed record ProviderStatusSnapshot
{
    public IReadOnlyList<ProviderHealthResult> Providers { get; init; } = Array.Empty<ProviderHealthResult>();

    public string OverallStatus { get; init; } = string.Empty;
}
