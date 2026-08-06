using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public sealed record LegacyPowerShellWorkerOptions
{
    public required string WorkerPath { get; init; }

    public LegacyPowerShellEdition PreferredEdition { get; init; } = LegacyPowerShellEdition.PowerShell7;

    public int TimeoutMilliseconds { get; init; } = 30000;
}
