namespace HAP.LegacyWorker.Protocol;

public static class LegacyWorkerKnownOperations
{
    public const string GetRuntimeProfiles = "Get-HapRuntimeProfiles";
    public const string GetRuntimeProfileSelection = "Get-HapRuntimeProfileSelection";
    public const string SetRuntimeProfileSelection = "Set-HapRuntimeProfileSelection";
    public const string TestRuntimeProfile = "Test-HapRuntimeProfile";
    public const string StartRuntimeSession = "Start-HapRuntimeSession";
    public const string StopRuntimeSession = "Stop-HapRuntimeSession";
    public const string GetProviderHealth = "Get-HapProviderHealth";
    public const string GetRuntimeDiagnostics = "Get-HapRuntimeDiagnostics";
}
