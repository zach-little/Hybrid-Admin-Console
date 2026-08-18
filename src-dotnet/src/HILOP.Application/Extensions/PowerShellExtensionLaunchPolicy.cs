using HILOP.Extensions.Abstractions;

namespace HILOP.Application.Extensions;

public sealed class PowerShellExtensionLaunchPolicy
{
    public PowerShellExtensionLaunchPlan CreatePlan(IEnumerable<ExtensionLaunchCandidate> candidates)
    {
        var providers = candidates
            .Where(candidate => candidate.Enabled && candidate.Implementation == HapProviderImplementationKind.PowerShell)
            .Select(candidate => candidate.ProviderId)
            .Where(providerId => !string.IsNullOrWhiteSpace(providerId))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return new PowerShellExtensionLaunchPlan { ProviderIdsRequiringHost = providers };
    }
}
