namespace HILOP.Extensions.PowerShell;

public sealed record PowerShellProviderProxyOptions
{
    public required string PluginHostPath { get; init; }

    public int TimeoutMilliseconds { get; init; } = 30000;
}
