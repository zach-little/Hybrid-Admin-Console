using HAP.Contracts;

namespace HAP.Configuration;

public sealed class RuntimeProfileValidator
{
    private static readonly HashSet<string> KnownCapabilities = new(StringComparer.OrdinalIgnoreCase)
    {
        ProviderCapabilityIds.ProviderHealth,
        ProviderCapabilityIds.UserLookup,
        ProviderCapabilityIds.UserProvisioning,
        ProviderCapabilityIds.UserUpdate,
        ProviderCapabilityIds.UserDeprovisioning,
        ProviderCapabilityIds.GroupMembership,
        ProviderCapabilityIds.DeviceLookup,
        ProviderCapabilityIds.DeviceAction,
        ProviderCapabilityIds.CredentialEnrollment,
        ProviderCapabilityIds.CredentialReset,
        ProviderCapabilityIds.LicenseAssignment,
        ProviderCapabilityIds.Reporting,
        ProviderCapabilityIds.SecurityRead,
        ProviderCapabilityIds.WorkflowTrigger,
        ProviderCapabilityIds.ChoiceLookup
    };

    public ConfigurationValidationResult Validate(
        RuntimeProfile profile,
        IEnumerable<ExtensionRegistration>? extensionRegistrations = null)
    {
        var errors = new List<OperationError>();
        var warnings = new List<OperationWarning>();
        var extensionsByInstance = (extensionRegistrations ?? Array.Empty<ExtensionRegistration>())
            .ToDictionary(item => item.ProviderInstanceId, StringComparer.OrdinalIgnoreCase);

        if (string.IsNullOrWhiteSpace(profile.ProfileName))
        {
            errors.Add(OperationError.Create("RuntimeProfile.ProfileNameRequired", "Runtime profile name is required."));
        }

        if (string.IsNullOrWhiteSpace(profile.Cloud))
        {
            errors.Add(OperationError.Create("RuntimeProfile.CloudRequired", "Runtime profile cloud is required."));
        }

        if (profile.Providers.Count == 0)
        {
            errors.Add(OperationError.Create("RuntimeProfile.ProviderRequired", "At least one provider must be declared."));
        }

        var enabledProviders = profile.Providers.Values.Where(provider => provider.Enabled).ToArray();
        if (enabledProviders.Length == 0)
        {
            errors.Add(OperationError.Create("RuntimeProfile.EnabledProviderRequired", "At least one provider must be enabled."));
        }

        if (profile.Mode == RuntimeProfileMode.Simulation)
        {
            var hasDirectorySimulator = profile.Providers.TryGetValue("DirectorySimulator", out var simulator)
                && simulator.Enabled
                && simulator.Mode == ProviderMode.Simulation;
            if (!hasDirectorySimulator)
            {
                errors.Add(OperationError.Create(
                    "RuntimeProfile.DirectorySimulatorRequired",
                    "Simulation profiles must enable the DirectorySimulator provider in Simulation mode.",
                    "DirectorySimulator"));
            }
        }

        foreach (var provider in profile.Providers.Values)
        {
            if (string.IsNullOrWhiteSpace(provider.Name))
            {
                errors.Add(OperationError.Create("RuntimeProfile.ProviderNameRequired", "Provider name is required."));
            }

            if (provider.Enabled && provider.Mode == ProviderMode.Disabled)
            {
                errors.Add(OperationError.Create(
                    "RuntimeProfile.EnabledProviderCannotBeDisabled",
                    "Enabled providers cannot use Disabled mode.",
                    provider.Name));
            }

            foreach (var capability in provider.RequestedCapabilities)
            {
                if (!KnownCapabilities.Contains(capability))
                {
                    warnings.Add(OperationWarning.Create(
                        "RuntimeProfile.UnknownCapability",
                        $"Provider requests unknown capability '{capability}'.",
                        provider.Name));
                }
            }

            if (provider.ImplementationKind == ProviderImplementationKind.PowerShellExtension)
            {
                ValidateExtensionProviderReference(provider, extensionsByInstance, errors);
            }
        }

        foreach (var reference in profile.Extensions)
        {
            if (string.IsNullOrWhiteSpace(reference.ProviderInstanceId))
            {
                errors.Add(OperationError.Create("RuntimeProfile.ExtensionInstanceRequired", "Extension references require a provider instance ID."));
                continue;
            }

            if (!extensionsByInstance.TryGetValue(reference.ProviderInstanceId, out var registration))
            {
                errors.Add(OperationError.Create(
                    "RuntimeProfile.ExtensionNotRegistered",
                    "Runtime profile references an extension instance that is not registered.",
                    reference.ProviderInstanceId));
                continue;
            }

            ValidateRequestedCapabilities(reference.ProviderInstanceId, reference.RequestedCapabilities, registration, errors);
        }

        return ConfigurationValidationResult.From(errors, warnings);
    }

    private static void ValidateExtensionProviderReference(
        RuntimeProviderSettings provider,
        IReadOnlyDictionary<string, ExtensionRegistration> extensionsByInstance,
        List<OperationError> errors)
    {
        if (string.IsNullOrWhiteSpace(provider.ExtensionInstanceId))
        {
            errors.Add(OperationError.Create(
                "RuntimeProfile.ExtensionInstanceRequired",
                "PowerShell extension providers require an extension instance ID.",
                provider.Name));
            return;
        }

        if (!extensionsByInstance.TryGetValue(provider.ExtensionInstanceId, out var registration))
        {
            errors.Add(OperationError.Create(
                "RuntimeProfile.ExtensionNotRegistered",
                "Provider references an extension instance that is not registered.",
                provider.Name));
            return;
        }

        ValidateRegistrationState(provider.ExtensionInstanceId, registration, errors);
        ValidateRequestedCapabilities(provider.Name, provider.RequestedCapabilities, registration, errors);
    }

    private static void ValidateRegistrationState(
        string target,
        ExtensionRegistration registration,
        List<OperationError> errors)
    {
        if (!registration.Enabled)
        {
            errors.Add(OperationError.Create("RuntimeProfile.ExtensionDisabled", "Referenced extension is disabled.", target));
        }

        if (!registration.Approved)
        {
            errors.Add(OperationError.Create("RuntimeProfile.ExtensionNotApproved", "Referenced extension is not approved.", target));
        }
    }

    private static void ValidateRequestedCapabilities(
        string target,
        IEnumerable<string> requestedCapabilities,
        ExtensionRegistration registration,
        List<OperationError> errors)
    {
        var approved = new HashSet<string>(registration.ApprovedCapabilities, StringComparer.OrdinalIgnoreCase);
        var denied = new HashSet<string>(registration.DeniedCapabilities, StringComparer.OrdinalIgnoreCase);

        foreach (var capability in requestedCapabilities)
        {
            if (denied.Contains(capability) || !approved.Contains(capability))
            {
                errors.Add(OperationError.Create(
                    "RuntimeProfile.ExtensionCapabilityNotApproved",
                    $"Requested extension capability '{capability}' is not approved.",
                    target));
            }
        }
    }
}
