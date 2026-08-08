using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Application.Workflows;

public interface IPowerShellWorkflowActionRunner
{
    Task<OperationResult<ProviderChangeResult>> ExecuteAsync(
        WorkflowActionDefinition action,
        IReadOnlyDictionary<string, string> variables,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}

public sealed class NativeProviderWorkflowActionExecutor : IWorkflowActionExecutor
{
    private readonly IReadOnlyDictionary<string, ISimulatorWriteCapability> _providers;
    private readonly IPowerShellWorkflowActionRunner? _powerShellRunner;

    public NativeProviderWorkflowActionExecutor(
        IReadOnlyDictionary<string, ISimulatorWriteCapability> providers,
        IPowerShellWorkflowActionRunner? powerShellRunner = null)
    {
        _providers = providers;
        _powerShellRunner = powerShellRunner;
    }

    public async Task<WorkflowActionResult> ExecuteAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (action.Type.Equals(WorkflowActionTypes.ExecutePowerShell, StringComparison.OrdinalIgnoreCase))
        {
            return await ExecutePowerShellAsync(action, request, correlationId, cancellationToken).ConfigureAwait(false);
        }

        if (IsFutureAction(action.Type))
        {
            return Skipped(action, "Deferred", $"{action.Type} is reserved for a future workflow capability.");
        }

        if (!_providers.TryGetValue(action.ProviderId, out var provider))
        {
            return Failed(action, "ProviderUnavailable", $"Provider '{action.ProviderId}' is not available.");
        }

        OperationResult<ProviderChangeResult> result;
        try
        {
            var inputs = ExpandInputs(action.Inputs, request.Variables);
            result = action.Type switch
            {
                WorkflowActionTypes.CreateAdUser => await provider.CreateUserAsync(CreateUser(inputs), correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.UpdateAdAttributes => await provider.UpdateUserAttributesAsync(UpdateAttributes(inputs), correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.SetManager => await provider.SetManagerAsync(new ManagerChangeRequest { Identity = Required(inputs, "Identity"), ManagerIdentity = Required(inputs, "ManagerIdentity") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.AddGroup => await provider.AddGroupMembershipAsync(new MembershipChangeRequest { Identity = Required(inputs, "Identity"), Group = Required(inputs, "Group") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.RemoveGroup => await provider.RemoveGroupMembershipAsync(new MembershipChangeRequest { Identity = Required(inputs, "Identity"), Group = Required(inputs, "Group") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.EnableRemoteMailbox => await provider.EnableRemoteMailboxAsync(new MailboxProvisioningRequest { Identity = Required(inputs, "Identity"), RemoteRoutingAddress = Optional(inputs, "RemoteRoutingAddress"), PrimarySmtpAddress = Optional(inputs, "PrimarySmtpAddress") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.SetMailboxForwarding => await provider.SetMailboxForwardingAsync(new MailboxForwardingRequest { Identity = Required(inputs, "Identity"), ForwardingSmtpAddress = Optional(inputs, "ForwardingSmtpAddress"), DeliverToMailboxAndForward = Bool(inputs, "DeliverToMailboxAndForward") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.SetGalVisibility => await provider.SetGalVisibilityAsync(new GalVisibilityRequest { Identity = Required(inputs, "Identity"), HiddenFromAddressListsEnabled = Bool(inputs, "HiddenFromAddressListsEnabled") }, correlationId, cancellationToken).ConfigureAwait(false),
                WorkflowActionTypes.AddMailboxDelegation => await provider.AddMailboxDelegationAsync(new MailboxDelegationChangeRequest { Identity = Required(inputs, "Identity"), Trustee = Required(inputs, "Trustee"), AccessRights = Optional(inputs, "AccessRights", "FullAccess") }, correlationId, cancellationToken).ConfigureAwait(false),
                _ => OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create("Workflow.ActionUnsupported", $"Workflow action '{action.Type}' is not supported.") }, status: "Unsupported")
            };
        }
        catch (InvalidOperationException ex)
        {
            result = OperationResult<ProviderChangeResult>.Failure(
                correlationId,
                new[] { OperationError.Create("Workflow.ActionInputInvalid", ex.Message) },
                status: "InvalidInput");
        }

        return FromProviderResult(action, result);
    }

    private async Task<WorkflowActionResult> ExecutePowerShellAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        if (_powerShellRunner is null)
        {
            return Skipped(action, "RunnerRequired", "PowerShell workflow action is configured, but no approved PowerShell action runner is attached.");
        }

        return FromProviderResult(action, await _powerShellRunner.ExecuteAsync(action, request.Variables, correlationId, cancellationToken).ConfigureAwait(false));
    }

    private static WorkflowActionResult FromProviderResult(WorkflowActionDefinition action, OperationResult<ProviderChangeResult> result)
    {
        return new WorkflowActionResult
        {
            ActionId = action.Id,
            ActionName = action.Name,
            ActionType = action.Type,
            ProviderId = action.ProviderId,
            Succeeded = result.Succeeded,
            Changed = result.Value?.Changed ?? false,
            Status = result.Status ?? (result.Succeeded ? "Completed" : "Failed"),
            Message = result.Value?.Message ?? string.Join("; ", result.Errors.Select(error => error.Message))
        };
    }

    private static UserCreateRequest CreateUser(IReadOnlyDictionary<string, string> inputs)
    {
        return new UserCreateRequest
        {
            GivenName = Required(inputs, "GivenName"),
            Surname = Required(inputs, "Surname"),
            SamAccountName = Required(inputs, "SamAccountName"),
            Department = Optional(inputs, "Department"),
            Title = Optional(inputs, "Title"),
            ManagerSamAccountName = Optional(inputs, "ManagerSamAccountName"),
            Office = Optional(inputs, "Office"),
            DisplayName = Optional(inputs, "DisplayName"),
            UserPrincipalName = Optional(inputs, "UserPrincipalName"),
            TargetOu = Optional(inputs, "TargetOu"),
            Company = Optional(inputs, "Company"),
            EmployeeId = Optional(inputs, "EmployeeId"),
            BadgeId = Optional(inputs, "BadgeId"),
            OfficePhone = Optional(inputs, "OfficePhone"),
            MobilePhone = Optional(inputs, "MobilePhone"),
            City = Optional(inputs, "City"),
            StreetAddress = Optional(inputs, "StreetAddress"),
            State = Optional(inputs, "State"),
            PostalCode = Optional(inputs, "PostalCode"),
            OtherAttributes = inputs
                .Where(pair => pair.Key.StartsWith("Attribute:", StringComparison.OrdinalIgnoreCase))
                .ToDictionary(pair => pair.Key["Attribute:".Length..], pair => pair.Value, StringComparer.OrdinalIgnoreCase)
        };
    }

    private static UserUpdateRequest UpdateAttributes(IReadOnlyDictionary<string, string> inputs)
    {
        return new UserUpdateRequest
        {
            Identity = Required(inputs, "Identity"),
            Attributes = inputs
                .Where(pair => pair.Key.StartsWith("Attribute:", StringComparison.OrdinalIgnoreCase))
                .ToDictionary(pair => pair.Key["Attribute:".Length..], pair => pair.Value, StringComparer.OrdinalIgnoreCase)
        };
    }

    private static IReadOnlyDictionary<string, string> ExpandInputs(
        IReadOnlyDictionary<string, string> inputs,
        IReadOnlyDictionary<string, string> variables)
    {
        return inputs.ToDictionary(
            pair => pair.Key,
            pair => Expand(pair.Value, variables),
            StringComparer.OrdinalIgnoreCase);
    }

    private static string Expand(string value, IReadOnlyDictionary<string, string> variables)
    {
        var expanded = value;
        foreach (var variable in variables)
        {
            expanded = expanded.Replace($"{{{{{variable.Key}}}}}", variable.Value, StringComparison.OrdinalIgnoreCase);
        }

        return expanded;
    }

    private static string Required(IReadOnlyDictionary<string, string> inputs, string key)
    {
        var value = Optional(inputs, key);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Required workflow input '{key}' is missing.");
        }

        return value;
    }

    private static string Optional(IReadOnlyDictionary<string, string> inputs, string key, string fallback = "")
    {
        return inputs.TryGetValue(key, out var value) ? value : fallback;
    }

    private static bool Bool(IReadOnlyDictionary<string, string> inputs, string key)
    {
        return inputs.TryGetValue(key, out var value) && bool.TryParse(value, out var parsed) && parsed;
    }

    private static bool IsFutureAction(string actionType)
    {
        return actionType.Equals(WorkflowActionTypes.InvokeRestApi, StringComparison.OrdinalIgnoreCase) ||
               actionType.Equals(WorkflowActionTypes.Delay, StringComparison.OrdinalIgnoreCase) ||
               actionType.Equals(WorkflowActionTypes.Approval, StringComparison.OrdinalIgnoreCase) ||
               actionType.Equals(WorkflowActionTypes.ConditionalBranch, StringComparison.OrdinalIgnoreCase);
    }

    private static WorkflowActionResult Failed(WorkflowActionDefinition action, string status, string message)
    {
        return new WorkflowActionResult { ActionId = action.Id, ActionName = action.Name, ActionType = action.Type, ProviderId = action.ProviderId, Status = status, Message = message };
    }

    private static WorkflowActionResult Skipped(WorkflowActionDefinition action, string status, string message)
    {
        return new WorkflowActionResult { ActionId = action.Id, ActionName = action.Name, ActionType = action.Type, ProviderId = action.ProviderId, Skipped = true, Status = status, Message = message };
    }
}
