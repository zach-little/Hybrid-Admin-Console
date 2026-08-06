namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyWorkerHandshakeRequest
{
    public string ProtocolVersion { get; init; } = LegacyWorkerProtocol.Version;

    public LegacyWorkerMessageKind Kind { get; init; } = LegacyWorkerMessageKind.HandshakeRequest;

    public required string ClientName { get; init; }

    public IReadOnlyList<string> SupportedProtocolVersions { get; init; } = new[] { LegacyWorkerProtocol.Version };
}

public sealed record LegacyWorkerHandshakeResponse
{
    public string ProtocolVersion { get; init; } = LegacyWorkerProtocol.Version;

    public LegacyWorkerMessageKind Kind { get; init; } = LegacyWorkerMessageKind.HandshakeResponse;

    public required bool Accepted { get; init; }

    public required string WorkerName { get; init; }

    public required string WorkerVersion { get; init; }

    public LegacyPowerShellEdition Edition { get; init; } = LegacyPowerShellEdition.PowerShell7;

    public IReadOnlyList<string> SupportedOperations { get; init; } = Array.Empty<string>();

    public string Message { get; init; } = string.Empty;
}
