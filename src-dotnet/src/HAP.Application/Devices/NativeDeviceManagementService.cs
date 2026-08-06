using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Application.Devices;

public sealed class NativeDeviceManagementService
{
    private readonly IReadOnlyList<(string ProviderId, IDeviceReadCapability Provider)> _providers;

    public NativeDeviceManagementService(IEnumerable<(string ProviderId, IDeviceReadCapability Provider)> providers)
    {
        _providers = providers.ToArray();
    }

    public async Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("DeviceManagement.QueryRequired", "Device search query is required.") });
        }

        var devices = new List<ManagedDeviceSummary>();
        var warnings = new List<OperationWarning>();
        foreach (var (providerId, provider) in _providers)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = await provider.SearchDevicesAsync(query, correlationId, cancellationToken).ConfigureAwait(false);
            if (result.Succeeded)
            {
                devices.AddRange(result.Value ?? Array.Empty<ManagedDeviceSummary>());
            }
            else
            {
                warnings.Add(OperationWarning.Create("DeviceManagement.ProviderFailed", $"{providerId} failed during device search.", providerId));
            }
        }

        return OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(
            devices
                .GroupBy(device => string.IsNullOrWhiteSpace(device.Id) ? device.Name : device.Id, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.OrderBy(device => device.Source, StringComparer.OrdinalIgnoreCase).First())
                .OrderBy(device => device.Name, StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            correlationId,
            warnings,
            warnings.Count > 0 ? "Partial" : "Completed");
    }
}
