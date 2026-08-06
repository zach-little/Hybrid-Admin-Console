using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using HAP.Contracts;
using HAP.Extensions.Abstractions;

namespace HAP.Extensions.Registry;

public sealed class ApprovedExtensionRegistry
{
    private static readonly JsonSerializerOptions ManifestJsonOptions = CreateJsonOptions();

    private readonly HapExtensionManifestValidator _validator;
    private readonly IReadOnlyList<string> _controlledRoots;

    public ApprovedExtensionRegistry(
        IEnumerable<string> controlledRoots,
        HapExtensionManifestValidator? validator = null)
    {
        _controlledRoots = controlledRoots
            .Select(Path.GetFullPath)
            .Select(path => path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
            .ToArray();
        _validator = validator ?? new HapExtensionManifestValidator();
    }

    public OperationResult<IReadOnlyList<ExtensionRegistryEntry>> LoadApproved(
        IEnumerable<ApprovedExtensionRegistration> registrations,
        CorrelationId correlationId)
    {
        var entries = new List<ExtensionRegistryEntry>();
        var errors = new List<OperationError>();

        foreach (var registration in registrations)
        {
            var result = LoadOne(registration, correlationId);
            if (result.Succeeded && result.Value is not null)
            {
                entries.Add(result.Value);
            }
            else
            {
                errors.AddRange(result.Errors);
            }
        }

        if (errors.Count > 0)
        {
            return OperationResult<IReadOnlyList<ExtensionRegistryEntry>>.Failure(correlationId, errors);
        }

        return OperationResult<IReadOnlyList<ExtensionRegistryEntry>>.Success(entries, correlationId);
    }

    private OperationResult<ExtensionRegistryEntry> LoadOne(
        ApprovedExtensionRegistration registration,
        CorrelationId correlationId)
    {
        var manifestPath = Path.GetFullPath(registration.ManifestPath);
        if (!IsUnderControlledRoot(manifestPath))
        {
            return Failure(correlationId, "ExtensionRegistry.PathOutsideControlledRoot", "Extension manifest is not under a HAP-controlled root.", manifestPath);
        }

        if (!File.Exists(manifestPath))
        {
            return Failure(correlationId, "ExtensionRegistry.ManifestMissing", "Approved extension manifest was not found.", manifestPath);
        }

        var sha256 = ComputeSha256(manifestPath);
        if (!string.Equals(sha256, registration.ApprovedSha256, StringComparison.OrdinalIgnoreCase))
        {
            return Failure(correlationId, "ExtensionRegistry.HashMismatch", "Extension manifest hash does not match the approved hash.", manifestPath);
        }

        if (registration.SignatureState == HapExtensionSignatureState.Untrusted)
        {
            return Failure(correlationId, "ExtensionRegistry.SignatureUntrusted", "Extension signature state is untrusted.", manifestPath);
        }

        var manifest = JsonSerializer.Deserialize<HapExtensionManifest>(File.ReadAllText(manifestPath), ManifestJsonOptions);
        if (manifest is null)
        {
            return Failure(correlationId, "ExtensionRegistry.ManifestInvalidJson", "Extension manifest could not be deserialized.", manifestPath);
        }

        var validation = _validator.Validate(manifest, correlationId);
        if (!validation.Succeeded)
        {
            return OperationResult<ExtensionRegistryEntry>.Failure(correlationId, validation.Errors);
        }

        var declared = new HashSet<string>(manifest.Capabilities.Select(capability => capability.Id), StringComparer.OrdinalIgnoreCase);
        var undeclaredGrants = registration.GrantedCapabilities.Where(capability => !declared.Contains(capability)).ToArray();
        if (undeclaredGrants.Length > 0)
        {
            return Failure(correlationId, "ExtensionRegistry.UndeclaredCapabilityGrant", "Registration grants a capability the manifest does not declare.", string.Join(",", undeclaredGrants));
        }

        return OperationResult<ExtensionRegistryEntry>.Success(
            new ExtensionRegistryEntry
            {
                Manifest = manifest,
                ManifestPath = manifestPath,
                ManifestSha256 = sha256,
                SignatureState = registration.SignatureState,
                Enabled = registration.Enabled,
                GrantedCapabilities = registration.GrantedCapabilities.ToArray()
            },
            correlationId);
    }

    public static string ComputeSha256(string path)
    {
        using var stream = File.OpenRead(path);
        var hash = SHA256.HashData(stream);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private bool IsUnderControlledRoot(string path)
    {
        return _controlledRoots.Any(root =>
            path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, root, StringComparison.OrdinalIgnoreCase));
    }

    private static OperationResult<ExtensionRegistryEntry> Failure(
        CorrelationId correlationId,
        string code,
        string message,
        string? target = null)
    {
        return OperationResult<ExtensionRegistryEntry>.Failure(correlationId, new[] { OperationError.Create(code, message, target) });
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
