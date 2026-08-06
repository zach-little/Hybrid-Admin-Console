using HAP.Providers.Abstractions;

namespace HAP.Application.UserLookup;

public sealed record HybridUserLookupResult
{
    public string Query { get; init; } = string.Empty;

    public IReadOnlyList<ProviderUserLookupResult> ProviderResults { get; init; } = Array.Empty<ProviderUserLookupResult>();

    public IReadOnlyList<SimulatorUserSummary> Users { get; init; } = Array.Empty<SimulatorUserSummary>();
}

public sealed record ProviderUserLookupResult
{
    public string ProviderId { get; init; } = string.Empty;

    public bool Succeeded { get; init; }

    public int ResultCount { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;
}
