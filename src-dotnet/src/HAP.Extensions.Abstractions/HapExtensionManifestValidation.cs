using HAP.Contracts;

namespace HAP.Extensions.Abstractions;

public sealed record HapExtensionManifestValidation
{
    public required ExtensionApiVersion ApiVersion { get; init; }

    public required bool IsCompatible { get; init; }

    public IReadOnlyList<string> CapabilityIds { get; init; } = Array.Empty<string>();
}

public sealed class HapExtensionManifestValidator
{
    private readonly ExtensionApiVersion _hostApiVersion;

    public HapExtensionManifestValidator()
        : this(ExtensionApiVersion.Current)
    {
    }

    public HapExtensionManifestValidator(ExtensionApiVersion hostApiVersion)
    {
        _hostApiVersion = hostApiVersion;
    }

    public OperationResult<HapExtensionManifestValidation> Validate(
        HapExtensionManifest manifest,
        CorrelationId correlationId)
    {
        var errors = new List<OperationError>();

        Require(manifest.ManifestVersion, "Extension.ManifestVersionRequired", "ManifestVersion is required.", errors);
        Require(manifest.ProviderId, "Extension.ProviderIdRequired", "ProviderId is required.", errors);
        Require(manifest.DisplayName, "Extension.DisplayNameRequired", "DisplayName is required.", errors);
        Require(manifest.Publisher, "Extension.PublisherRequired", "Publisher is required.", errors);
        Require(manifest.ProviderVersion, "Extension.ProviderVersionRequired", "ProviderVersion is required.", errors);

        if (!ExtensionApiVersion.TryParse(manifest.ApiVersion, out var apiVersion))
        {
            errors.Add(OperationError.Create("Extension.ApiVersionInvalid", "ApiVersion must use major.minor format."));
        }
        else if (!apiVersion.IsCompatibleWith(_hostApiVersion))
        {
            errors.Add(OperationError.Create(
                "Extension.ApiVersionUnsupported",
                $"Extension API version {apiVersion} is not compatible with host API version {_hostApiVersion}."));
        }

        ValidateEntryPoint(manifest, errors);
        ValidateCapabilities(manifest.Capabilities, errors);

        if (errors.Count > 0)
        {
            return OperationResult<HapExtensionManifestValidation>.Failure(correlationId, errors);
        }

        return OperationResult<HapExtensionManifestValidation>.Success(
            new HapExtensionManifestValidation
            {
                ApiVersion = apiVersion,
                IsCompatible = true,
                CapabilityIds = manifest.Capabilities.Select(capability => capability.Id).ToArray()
            },
            correlationId);
    }

    private static void ValidateEntryPoint(HapExtensionManifest manifest, List<OperationError> errors)
    {
        if (manifest.Implementation == HapProviderImplementationKind.NativeDotNet)
        {
            Require(manifest.EntryPoint.AssemblyPath, "Extension.AssemblyPathRequired", "Native extensions require EntryPoint.AssemblyPath.", errors);
            Require(manifest.EntryPoint.TypeName, "Extension.TypeNameRequired", "Native extensions require EntryPoint.TypeName.", errors);
            return;
        }

        if (manifest.Implementation == HapProviderImplementationKind.PowerShell)
        {
            Require(manifest.EntryPoint.ModulePath, "Extension.ModulePathRequired", "PowerShell extensions require EntryPoint.ModulePath.", errors);
            Require(manifest.EntryPoint.RequiredPowerShellEdition, "Extension.PowerShellEditionRequired", "PowerShell extensions require EntryPoint.RequiredPowerShellEdition.", errors);
            Require(manifest.EntryPoint.MinimumPowerShellVersion, "Extension.PowerShellVersionRequired", "PowerShell extensions require EntryPoint.MinimumPowerShellVersion.", errors);
        }
    }

    private static void ValidateCapabilities(
        IReadOnlyList<HapExtensionCapabilityDeclaration> capabilities,
        List<OperationError> errors)
    {
        if (capabilities.Count == 0)
        {
            errors.Add(OperationError.Create("Extension.CapabilitiesRequired", "At least one capability declaration is required."));
            return;
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var capability in capabilities)
        {
            Require(capability.Id, "Extension.CapabilityIdRequired", "Capability Id is required.", errors);
            if (!string.IsNullOrWhiteSpace(capability.Id) && !seen.Add(capability.Id))
            {
                errors.Add(OperationError.Create("Extension.CapabilityDuplicate", $"Capability '{capability.Id}' is declared more than once.", capability.Id));
            }

            if (capability.Operations.Count == 0 || capability.Operations.Any(string.IsNullOrWhiteSpace))
            {
                errors.Add(OperationError.Create("Extension.CapabilityOperationsRequired", $"Capability '{capability.Id}' requires at least one operation.", capability.Id));
            }
        }
    }

    private static void Require(
        string value,
        string code,
        string message,
        List<OperationError> errors)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors.Add(OperationError.Create(code, message));
        }
    }
}
