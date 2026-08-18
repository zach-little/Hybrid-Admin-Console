namespace HILOP.Providers.Simulator;

public sealed record DirectorySimulatorOptions
{
    public bool Enabled { get; init; } = true;

    public bool Required { get; init; } = true;

    public bool ConfigurationValid { get; init; } = true;

    public bool ProviderAvailable { get; init; } = true;

    public bool AllowGeneratedFallbackUsers { get; init; } = true;

    public int TimeoutMilliseconds { get; init; } = 30000;

    public int SimulatedDelayMilliseconds { get; init; }

    public bool IncludePartialFixture { get; init; }
}
