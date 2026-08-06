using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Application.UserLookup;

public sealed class NativeHybridUserLookupService
{
    private readonly IReadOnlyList<(string ProviderId, IUserLookupCapability Provider)> _providers;

    public NativeHybridUserLookupService(IEnumerable<(string ProviderId, IUserLookupCapability Provider)> providers)
    {
        _providers = providers.ToArray();
    }

    public async Task<OperationResult<HybridUserLookupResult>> SearchAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return OperationResult<HybridUserLookupResult>.Failure(
                correlationId,
                new[] { OperationError.Create("HybridUserLookup.QueryRequired", "User lookup query is required.") });
        }

        var providerResults = new List<ProviderUserLookupResult>();
        var warnings = new List<OperationWarning>();
        var users = new List<SimulatorUserSummary>();

        foreach (var (providerId, provider) in _providers)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = await provider.SearchUsersAsync(query, correlationId, cancellationToken).ConfigureAwait(false);
            if (result.Succeeded)
            {
                var values = result.Value ?? Array.Empty<SimulatorUserSummary>();
                users.AddRange(values.Select(user => user with { Source = string.IsNullOrWhiteSpace(user.Source) ? providerId : user.Source }));
                providerResults.Add(new ProviderUserLookupResult { ProviderId = providerId, Succeeded = true, ResultCount = values.Count, Status = result.Status ?? "Completed" });
                warnings.AddRange(result.Warnings);
            }
            else
            {
                providerResults.Add(new ProviderUserLookupResult
                {
                    ProviderId = providerId,
                    Succeeded = false,
                    Status = result.Status ?? "Failed",
                    Message = string.Join("; ", result.Errors.Select(error => error.Message))
                });
                warnings.Add(OperationWarning.Create("HybridUserLookup.ProviderFailed", $"{providerId} failed during user lookup.", providerId));
            }
        }

        var normalized = users
            .GroupBy(user => NormalizeIdentity(user), StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(user => user.Source, StringComparer.OrdinalIgnoreCase).First())
            .OrderBy(user => user.SamAccountName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return OperationResult<HybridUserLookupResult>.Success(
            new HybridUserLookupResult
            {
                Query = query,
                ProviderResults = providerResults,
                Users = normalized
            },
            correlationId,
            warnings,
            providerResults.Any(result => !result.Succeeded) ? "Partial" : "Completed");
    }

    private static string NormalizeIdentity(SimulatorUserSummary user)
    {
        if (!string.IsNullOrWhiteSpace(user.UserPrincipalName))
        {
            return user.UserPrincipalName;
        }

        if (!string.IsNullOrWhiteSpace(user.SamAccountName))
        {
            return user.SamAccountName;
        }

        return user.DisplayName;
    }
}
