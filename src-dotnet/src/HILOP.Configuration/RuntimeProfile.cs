using System.Text.Json.Serialization;

namespace HILOP.Configuration;

public sealed record RuntimeProfile
{
    public string ProfileName { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Organization { get; init; } = string.Empty;

    public string ProfileRoot { get; init; } = string.Empty;

    public string ProfileLayout { get; init; } = string.Empty;

    public RuntimeProfileMode Mode { get; init; } = RuntimeProfileMode.Simulation;

    public string Cloud { get; init; } = "Commercial";

    public string Environment { get; init; } = string.Empty;

    public string TenantId { get; init; } = string.Empty;

    public bool SimulationMode { get; init; }

    public bool IsDefault { get; init; }

    public RuntimeAuthenticationSettings Authentication { get; init; } = new();

    public IReadOnlyDictionary<string, RuntimeProviderSettings> Providers { get; init; } =
        new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyList<RuntimeExtensionReference> Extensions { get; init; } =
        Array.Empty<RuntimeExtensionReference>();

    [JsonIgnore]
    public string SourcePath { get; init; } = string.Empty;
}
