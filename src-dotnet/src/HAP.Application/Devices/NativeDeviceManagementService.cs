using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Application.Devices;

public sealed class NativeDeviceManagementService
{
    private readonly IReadOnlyList<(string ProviderId, IDeviceReadCapability Provider)> _providers;
    private readonly IReadOnlyList<(string ProviderId, IDeviceActionCapability Provider)> _actionProviders;

    public NativeDeviceManagementService(IEnumerable<(string ProviderId, IDeviceReadCapability Provider)> providers)
    {
        _providers = providers.ToArray();
        _actionProviders = _providers
            .Where(item => item.Provider is IDeviceActionCapability)
            .Select(item => (item.ProviderId, Provider: (IDeviceActionCapability)item.Provider))
            .ToArray();
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

    public async Task<OperationResult<DeviceSecretRevealResult>> RevealDeviceSecretAsync(
        DeviceSecretRevealRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var provider = FindActionProvider(request.Device.Source);
        if (provider.Provider is null)
        {
            return OperationResult<DeviceSecretRevealResult>.Failure(
                correlationId,
                new[] { OperationError.Create("DeviceManagement.SecretReveal.ProviderUnsupported", $"No secret reveal provider is available for source '{request.Device.Source}'.") },
                status: "Unsupported");
        }

        return await provider.Provider.RevealDeviceSecretAsync(request, correlationId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<IReadOnlyList<DeviceLifecycleResult>>> RetireDeviceAsync(
        DeviceLifecycleRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return await InvokeLifecycleAsync(request, retire: true, correlationId, cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<IReadOnlyList<DeviceLifecycleResult>>> DeleteDeviceAsync(
        DeviceLifecycleRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return await InvokeLifecycleAsync(request, retire: false, correlationId, cancellationToken).ConfigureAwait(false);
    }

    private async Task<OperationResult<IReadOnlyList<DeviceLifecycleResult>>> InvokeLifecycleAsync(
        DeviceLifecycleRequest request,
        bool retire,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var providers = ResolveActionProviders(request);
        if (providers.Count == 0)
        {
            return OperationResult<IReadOnlyList<DeviceLifecycleResult>>.Failure(
                correlationId,
                new[] { OperationError.Create("DeviceManagement.Lifecycle.ProviderUnsupported", $"No device action provider is available for target '{request.Target}'.") },
                status: "Unsupported");
        }

        var results = new List<DeviceLifecycleResult>();
        var warnings = new List<OperationWarning>();
        foreach (var (providerId, provider) in providers)
        {
            var next = retire
                ? await provider.RetireDeviceAsync(request, correlationId, cancellationToken).ConfigureAwait(false)
                : await provider.DeleteDeviceAsync(request, correlationId, cancellationToken).ConfigureAwait(false);
            if (next.Succeeded && next.Value is not null)
            {
                results.Add(next.Value);
            }
            else
            {
                warnings.Add(OperationWarning.Create("DeviceManagement.Lifecycle.ProviderFailed", $"{providerId}: {string.Join(" ", next.Errors.Select(error => error.Message))}", providerId));
            }
        }

        return OperationResult<IReadOnlyList<DeviceLifecycleResult>>.Success(results, correlationId, warnings, warnings.Count > 0 ? "Partial" : "Completed");
    }

    private IReadOnlyList<(string ProviderId, IDeviceActionCapability Provider)> ResolveActionProviders(DeviceLifecycleRequest request)
    {
        if (request.Target == DeviceActionTarget.All)
        {
            return _actionProviders;
        }

        var target = request.Target switch
        {
            DeviceActionTarget.Intune => "MicrosoftGraph",
            DeviceActionTarget.EntraId => "MicrosoftGraph",
            DeviceActionTarget.ActiveDirectory => "ActiveDirectory",
            _ => request.Device.Source
        };

        return _actionProviders
            .Where(item => item.ProviderId.Contains(target, StringComparison.OrdinalIgnoreCase) ||
                           item.ProviderId.Equals(target, StringComparison.OrdinalIgnoreCase))
            .ToArray();
    }

    private (string ProviderId, IDeviceActionCapability? Provider) FindActionProvider(string source)
    {
        var provider = _actionProviders.FirstOrDefault(item => source.Contains(item.ProviderId, StringComparison.OrdinalIgnoreCase));
        if (provider.Provider is not null)
        {
            return provider;
        }

        return _actionProviders.FirstOrDefault();
    }
}
