using HAP.Providers.Abstractions;

namespace HAP.Application.Status;

public sealed record ProviderStatusSnapshot
{
    public IReadOnlyList<ProviderHealthResult> Providers { get; init; } = Array.Empty<ProviderHealthResult>();

    public string OverallStatus { get; init; } = string.Empty;
}
