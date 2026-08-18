namespace HILOP.Application.Capabilities;

public sealed record CapabilityAvailability
{
    public string ProviderId { get; init; } = string.Empty;

    public string CapabilityId { get; init; } = string.Empty;

    public CapabilityDisposition Disposition { get; init; }

    public bool IsInvokableBuiltIn { get; init; }

    public string Reason { get; init; } = string.Empty;

    public string ReplacementProviderId { get; init; } = string.Empty;
}
