namespace HAP.Application.Extensions;

public sealed record PowerShellExtensionLaunchPlan
{
    public IReadOnlyList<string> ProviderIdsRequiringHost { get; init; } = Array.Empty<string>();

    public bool ShouldLaunchPowerShell => ProviderIdsRequiringHost.Count > 0;
}
