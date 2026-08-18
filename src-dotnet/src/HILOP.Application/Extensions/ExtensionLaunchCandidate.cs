using HILOP.Extensions.Abstractions;

namespace HILOP.Application.Extensions;

public sealed record ExtensionLaunchCandidate
{
    public required string ProviderId { get; init; }

    public required HapProviderImplementationKind Implementation { get; init; }

    public required bool Enabled { get; init; }
}
