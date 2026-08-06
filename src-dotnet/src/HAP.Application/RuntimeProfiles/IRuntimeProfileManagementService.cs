using HAP.Contracts;

namespace HAP.Application.RuntimeProfiles;

public interface IRuntimeProfileManagementService
{
    Task<OperationResult<RuntimeProfileConfigurationDraft>> GetProfileConfigurationAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> SaveProfileConfigurationAsync(
        string repositoryRoot,
        RuntimeProfileConfigurationDraft draft,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> CreateProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> DeleteProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> SetDefaultProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> ExportProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
