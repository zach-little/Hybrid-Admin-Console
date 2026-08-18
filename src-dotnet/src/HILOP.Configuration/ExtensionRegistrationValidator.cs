using HILOP.Contracts;

namespace HILOP.Configuration;

public sealed class ExtensionRegistrationValidator
{
    public ConfigurationValidationResult Validate(ExtensionRegistration registration)
    {
        var errors = new List<OperationError>();

        Require(registration.ProviderId, "Extension.ProviderIdRequired", "Provider ID is required.", errors);
        Require(registration.ProviderInstanceId, "Extension.ProviderInstanceIdRequired", "Provider instance ID is required.", errors);
        Require(registration.DisplayName, "Extension.DisplayNameRequired", "Display name is required.", errors);
        Require(registration.Publisher, "Extension.PublisherRequired", "Publisher is required.", errors);
        Require(registration.Version, "Extension.VersionRequired", "Version is required.", errors);
        Require(registration.HapApiVersion, "Extension.HapApiVersionRequired", "HILOP API version is required.", errors);

        if (registration.ImplementationKind == ProviderImplementationKind.PowerShellExtension)
        {
            Require(registration.InstallationPath, "Extension.InstallationPathRequired", "PowerShell extensions require an installation path.", errors);
            Require(registration.EntryModule, "Extension.EntryModuleRequired", "PowerShell extensions require an entry module.", errors);

            if (registration.FileHashes.Count == 0)
            {
                errors.Add(OperationError.Create(
                    "Extension.FileHashRequired",
                    "PowerShell extensions require at least one recorded file hash.",
                    registration.ProviderInstanceId));
            }
        }

        if (!registration.Enabled)
        {
            return ConfigurationValidationResult.From(errors);
        }

        if (!registration.Approved)
        {
            errors.Add(OperationError.Create(
                "Extension.ApprovalRequired",
                "Enabled extensions must be approved.",
                registration.ProviderInstanceId));
        }

        if (registration.ApprovedCapabilities.Count == 0)
        {
            errors.Add(OperationError.Create(
                "Extension.CapabilityGrantRequired",
                "Enabled extensions must have at least one approved capability.",
                registration.ProviderInstanceId));
        }

        return ConfigurationValidationResult.From(errors);
    }

    private static void Require(string value, string code, string message, ICollection<OperationError> errors)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors.Add(OperationError.Create(code, message));
        }
    }
}
