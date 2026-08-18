using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.Status;

public sealed class NativeProviderHealthService
{
    private readonly IReadOnlyList<(string ProviderId, IProviderHealthCapability Provider)> _providers;

    public NativeProviderHealthService(IEnumerable<(string ProviderId, IProviderHealthCapability Provider)> providers)
    {
        _providers = providers.ToArray();
    }

    public async Task<OperationResult<ProviderStatusSnapshot>> GetStatusAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var health = new List<ProviderHealthResult>();
        var warnings = new List<OperationWarning>();

        foreach (var (providerId, provider) in _providers)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = await provider.GetHealthAsync(correlationId, cancellationToken).ConfigureAwait(false);
            if (result.Succeeded && result.Value is not null)
            {
                health.Add(result.Value);
                warnings.AddRange(result.Warnings);
            }
            else
            {
                health.Add(new ProviderHealthResult
                {
                    ProviderId = providerId,
                    Status = result.Status ?? "Failed",
                    Message = string.Join("; ", result.Errors.Select(error => error.Message)),
                    Available = false,
                    Connected = false,
                    LastError = string.Join("; ", result.Errors.Select(error => error.Code))
                });
                warnings.Add(OperationWarning.Create("ProviderHealth.ProviderFailed", $"{providerId} health failed.", providerId));
            }
        }

        var overall = health.All(item => item.Connected) ? "Healthy" : health.Any(item => item.Connected) ? "Degraded" : "Unavailable";
        return OperationResult<ProviderStatusSnapshot>.Success(
            new ProviderStatusSnapshot { Providers = health, OverallStatus = overall },
            correlationId,
            warnings,
            overall);
    }
}
