using System.Diagnostics;
using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.Auditing;

public sealed class AuditedWriteCapability : ISimulatorWriteCapability
{
    private readonly ISimulatorWriteCapability _inner;
    private readonly IAuditLog _audit;
    private readonly string _providerId;
    private readonly IDirectoryReadCapability? _directoryRead;
    private readonly IDirectoryAttributeReadCapability? _attributeRead;
    private readonly IExchangeReadCapability? _exchangeRead;

    public AuditedWriteCapability(string providerId, ISimulatorWriteCapability inner, IAuditLog audit)
    {
        _providerId = providerId;
        _inner = inner;
        _audit = audit;
        _directoryRead = inner as IDirectoryReadCapability;
        _attributeRead = inner as IDirectoryAttributeReadCapability;
        _exchangeRead = inner as IExchangeReadCapability;
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("CreateUser", "User", request.SamAccountName, request, correlationId,
            null,
            () => SnapshotUserAsync(request.SamAccountName, correlationId, cancellationToken),
            () => _inner.CreateUserAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("UpdateUserAttributes", "User", request.Identity, request, correlationId,
            () => SnapshotAttributesAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotAttributesAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.UpdateUserAttributesAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("SetManager", "User", request.Identity, request, correlationId,
            () => SnapshotManagerAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotManagerAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.SetManagerAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("AddGroupMembership", "User", request.Identity, request, correlationId,
            () => SnapshotGroupsAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotGroupsAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.AddGroupMembershipAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("RemoveGroupMembership", "User", request.Identity, request, correlationId,
            () => SnapshotGroupsAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotGroupsAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.RemoveGroupMembershipAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("SetMailboxForwarding", "Mailbox", request.Identity, request, correlationId,
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.SetMailboxForwardingAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("SetGalVisibility", "Mailbox", request.Identity, request, correlationId,
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.SetGalVisibilityAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("AddMailboxDelegation", "Mailbox", request.Identity, request, correlationId,
            () => SnapshotDelegationsAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotDelegationsAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.AddMailboxDelegationAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("EnableRemoteMailbox", "Mailbox", request.Identity, request, correlationId,
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => SnapshotMailboxAsync(request.Identity, correlationId, cancellationToken),
            () => _inner.EnableRemoteMailboxAsync(request, correlationId, cancellationToken), cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        ExecuteAsync("ResetState", "Provider", _providerId, new { }, correlationId, null, null,
            () => _inner.ResetStateAsync(correlationId, cancellationToken), cancellationToken);

    private async Task<OperationResult<ProviderChangeResult>> ExecuteAsync(
        string action,
        string targetType,
        string targetId,
        object request,
        CorrelationId correlationId,
        Func<Task<object?>>? before,
        Func<Task<object?>>? after,
        Func<Task<OperationResult<ProviderChangeResult>>> execute,
        CancellationToken cancellationToken)
    {
        var started = DateTimeOffset.UtcNow;
        object? previous = null;
        try { if (before is not null) previous = await before().ConfigureAwait(false); } catch { }
        await _audit.WriteAsync(new AuditEventRequest
        {
            CorrelationId = correlationId.Value,
            Category = "Provider Edit",
            EventType = ProviderEventType() + "Attempted",
            Action = action,
            Outcome = "Started",
            ProviderId = _providerId,
            TargetType = targetType,
            TargetId = targetId,
            TargetDisplayName = targetId,
            StartedAtUtc = started,
            PreviousValues = previous,
            NewValues = request,
            Message = $"{action} requested for {targetType} '{targetId}'."
        }, cancellationToken).ConfigureAwait(false);
        OperationResult<ProviderChangeResult>? result = null;
        Exception? exception = null;
        try
        {
            result = await execute().ConfigureAwait(false);
            return result;
        }
        catch (Exception ex)
        {
            exception = ex;
            throw;
        }
        finally
        {
            object? current = null;
            try { if (after is not null) current = await after().ConfigureAwait(false); } catch { }
            var succeeded = result?.Succeeded == true && exception is null;
            await _audit.WriteAsync(new AuditEventRequest
            {
                CorrelationId = correlationId.Value,
                Category = "Provider Edit",
                EventType = ProviderEventType(),
                Action = action,
                Outcome = exception is not null ? "Failed" : result?.Status ?? (succeeded ? "Completed" : "Failed"),
                Severity = succeeded ? "Information" : "Error",
                ProviderId = _providerId,
                TargetType = targetType,
                TargetId = targetId,
                TargetDisplayName = targetId,
                StartedAtUtc = started,
                CompletedAtUtc = DateTimeOffset.UtcNow,
                Message = exception?.Message ?? result?.Value?.Message ?? string.Join("; ", result?.Errors.Select(error => error.Message) ?? Array.Empty<string>()),
                PreviousValues = previous,
                NewValues = new { Request = request, Snapshot = current, Result = result?.Value },
                Metadata = new { Changed = result?.Value?.Changed ?? false, Status = result?.Status },
                Errors = exception is null ? result?.Errors.Cast<object>() : new object[] { new { exception.Message, ExceptionType = exception.GetType().FullName } },
                Warnings = result?.Warnings.Cast<object>()
            }, cancellationToken).ConfigureAwait(false);
        }
    }

    private string ProviderEventType() =>
        _providerId.Contains("Exchange", StringComparison.OrdinalIgnoreCase) ? "ExchangeEdit" :
        _providerId.Contains("Graph", StringComparison.OrdinalIgnoreCase) || _providerId.Contains("Entra", StringComparison.OrdinalIgnoreCase) ? "EntraEdit" :
        _providerId.Contains("ActiveDirectory", StringComparison.OrdinalIgnoreCase) ? "ActiveDirectoryEdit" : "ProviderEdit";

    private async Task<object?> SnapshotUserAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _directoryRead is null ? null : (await _directoryRead.GetUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;

    private async Task<object?> SnapshotAttributesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _attributeRead is null ? await SnapshotUserAsync(identity, correlationId, cancellationToken).ConfigureAwait(false) : (await _attributeRead.GetDirectoryAttributesAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;

    private async Task<object?> SnapshotManagerAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _directoryRead is null ? null : (await _directoryRead.GetManagerAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;

    private async Task<object?> SnapshotGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _directoryRead is null ? null : (await _directoryRead.GetGroupsAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;

    private async Task<object?> SnapshotMailboxAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _exchangeRead is null ? null : (await _exchangeRead.GetMailboxAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;

    private async Task<object?> SnapshotDelegationsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken) =>
        _exchangeRead is null ? null : (await _exchangeRead.GetMailboxDelegationsAsync(identity, correlationId, cancellationToken).ConfigureAwait(false)).Value;
}
