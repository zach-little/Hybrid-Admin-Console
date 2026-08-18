namespace HILOP.Contracts;

public sealed record ProviderCapability(string Id, string DisplayName, string Version = "1.0")
{
    public static ProviderCapability Create(string id, string displayName, string version = "1.0")
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            throw new ArgumentException("Capability ID cannot be empty.", nameof(id));
        }

        if (string.IsNullOrWhiteSpace(displayName))
        {
            throw new ArgumentException("Capability display name cannot be empty.", nameof(displayName));
        }

        if (string.IsNullOrWhiteSpace(version))
        {
            throw new ArgumentException("Capability version cannot be empty.", nameof(version));
        }

        return new ProviderCapability(id.Trim(), displayName.Trim(), version.Trim());
    }
}
