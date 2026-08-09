using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Mail;
using System.Text;
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
    private readonly Func<string, CorrelationId, CancellationToken, Task<OperationResult<string>>>? _bearerTokenResolver;

    public NativeProviderWorkflowActionExecutor(
        IReadOnlyDictionary<string, ISimulatorWriteCapability> providers,
        IPowerShellWorkflowActionRunner? powerShellRunner = null,
        Func<string, CorrelationId, CancellationToken, Task<OperationResult<string>>>? bearerTokenResolver = null)
    {
        _providers = providers;
        _powerShellRunner = powerShellRunner;
        _bearerTokenResolver = bearerTokenResolver;
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

        if (action.Type.Equals(WorkflowActionTypes.LaunchBrowser, StringComparison.OrdinalIgnoreCase))
        {
            return ExecuteLaunchBrowser(action, request);
        }

        if (action.Type.Equals(WorkflowActionTypes.SendEmail, StringComparison.OrdinalIgnoreCase))
        {
            return await ExecuteSendEmailAsync(action, request, cancellationToken).ConfigureAwait(false);
        }

        if (action.Type.Equals(WorkflowActionTypes.InvokeRestApi, StringComparison.OrdinalIgnoreCase))
        {
            return await ExecuteRestApiAsync(action, request, correlationId, cancellationToken).ConfigureAwait(false);
        }

        if (action.Type.Equals(WorkflowActionTypes.Delay, StringComparison.OrdinalIgnoreCase))
        {
            return await ExecuteDelayAsync(action, request, cancellationToken).ConfigureAwait(false);
        }

        if (action.Type.Equals(WorkflowActionTypes.Approval, StringComparison.OrdinalIgnoreCase))
        {
            return ExecuteApproval(action, request);
        }

        if (action.Type.Equals(WorkflowActionTypes.ConditionalBranch, StringComparison.OrdinalIgnoreCase))
        {
            return ExecuteConditionalBranch(action, request);
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
            TemporaryPassword = Optional(inputs, "TemporaryPassword"),
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

    private static WorkflowActionResult ExecuteLaunchBrowser(WorkflowActionDefinition action, WorkflowExecutionRequest request)
    {
        try
        {
            var inputs = ExpandInputs(action.Inputs, request.Variables);
            var url = Required(inputs, "Url");
            var browser = Optional(inputs, "Browser");
            if (browser.Equals("Chrome", StringComparison.OrdinalIgnoreCase))
            {
                var chrome = ChromePath();
                Process.Start(new ProcessStartInfo
                {
                    FileName = chrome,
                    Arguments = url,
                    UseShellExecute = string.Equals(chrome, "chrome.exe", StringComparison.OrdinalIgnoreCase)
                });
            }
            else
            {
                Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
            }

            return Completed(action, true, $"Launched browser URL: {url}");
        }
        catch (Exception ex)
        {
            return Failed(action, "Failed", $"Browser launch failed: {ex.Message}");
        }
    }

    private static async Task<WorkflowActionResult> ExecuteSendEmailAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var inputs = ExpandInputs(action.Inputs, request.Variables);
            using var message = new MailMessage
            {
                From = new MailAddress(Required(inputs, "From")),
                Subject = Required(inputs, "Subject"),
                Body = Required(inputs, "Body"),
                IsBodyHtml = Bool(inputs, "IsBodyHtml")
            };
            foreach (var recipient in Required(inputs, "To").Split(new[] { ';', ',' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                message.To.Add(recipient);
            }

            using var client = new SmtpClient(Required(inputs, "SmtpServer"));
            if (int.TryParse(Optional(inputs, "SmtpPort"), out var port) && port > 0)
            {
                client.Port = port;
            }

            client.EnableSsl = Bool(inputs, "EnableSsl");
            var username = Optional(inputs, "Username");
            if (!string.IsNullOrWhiteSpace(username))
            {
                client.Credentials = new NetworkCredential(username, Optional(inputs, "Password"));
            }

            await client.SendMailAsync(message, cancellationToken).ConfigureAwait(false);
            return Completed(action, true, $"Sent email to {inputs["To"]}.");
        }
        catch (Exception ex)
        {
            return Failed(action, "Failed", $"Email send failed: {ex.Message}");
        }
    }

    private async Task<WorkflowActionResult> ExecuteRestApiAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        try
        {
            var inputs = ExpandInputs(action.Inputs, request.Variables);
            using var httpRequest = new HttpRequestMessage(new HttpMethod(Optional(inputs, "Method", "GET")), Required(inputs, "Url"));
            var bearer = Optional(inputs, "BearerToken");
            if (string.IsNullOrWhiteSpace(bearer))
            {
                bearer = await ResolveBearerTokenAsync(action, inputs, correlationId, cancellationToken).ConfigureAwait(false);
            }

            if (!string.IsNullOrWhiteSpace(bearer))
            {
                httpRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearer);
            }

            foreach (var header in inputs.Where(pair => pair.Key.StartsWith("Header:", StringComparison.OrdinalIgnoreCase)))
            {
                httpRequest.Headers.TryAddWithoutValidation(header.Key["Header:".Length..], header.Value);
            }

            var body = Optional(inputs, "Body");
            if (!string.IsNullOrWhiteSpace(body))
            {
                httpRequest.Content = new StringContent(body, Encoding.UTF8, Optional(inputs, "ContentType", "application/json"));
            }

            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(Int(inputs, "TimeoutSeconds", 100)) };
            using var response = await client.SendAsync(httpRequest, cancellationToken).ConfigureAwait(false);
            var responseText = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            var ok = ExpectedStatusCodes(inputs).Contains((int)response.StatusCode);
            return new WorkflowActionResult
            {
                ActionId = action.Id,
                ActionName = action.Name,
                ActionType = action.Type,
                ProviderId = action.ProviderId,
                Succeeded = ok,
                Changed = ok && !string.Equals(Optional(inputs, "Method", "GET"), "GET", StringComparison.OrdinalIgnoreCase),
                Status = $"{(int)response.StatusCode} {response.StatusCode}",
                Message = string.IsNullOrWhiteSpace(responseText) ? "REST request completed." : TrimForResult(responseText)
            };
        }
        catch (Exception ex)
        {
            return Failed(action, "Failed", $"REST request failed: {ex.Message}");
        }
    }

    private async Task<string> ResolveBearerTokenAsync(
        WorkflowActionDefinition action,
        IReadOnlyDictionary<string, string> inputs,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var tokenProvider = Optional(inputs, "TokenProvider", action.ProviderId);
        if (string.IsNullOrWhiteSpace(tokenProvider) || _bearerTokenResolver is null)
        {
            return string.Empty;
        }

        var result = await _bearerTokenResolver(tokenProvider, correlationId, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded || string.IsNullOrWhiteSpace(result.Value))
        {
            throw new InvalidOperationException(result.Errors.Count == 0
                ? $"Token provider '{tokenProvider}' did not return a bearer token."
                : string.Join("; ", result.Errors.Select(error => error.Message)));
        }

        return result.Value;
    }

    private static async Task<WorkflowActionResult> ExecuteDelayAsync(
        WorkflowActionDefinition action,
        WorkflowExecutionRequest request,
        CancellationToken cancellationToken)
    {
        var inputs = ExpandInputs(action.Inputs, request.Variables);
        var milliseconds = Int(inputs, "Milliseconds", 0);
        if (milliseconds <= 0)
        {
            milliseconds = Int(inputs, "Seconds", 0) * 1000;
        }

        if (milliseconds <= 0)
        {
            return Failed(action, "InvalidInput", "Delay requires Milliseconds or Seconds greater than zero.");
        }

        await Task.Delay(milliseconds, cancellationToken).ConfigureAwait(false);
        return Completed(action, false, $"Delayed workflow for {milliseconds} ms.");
    }

    private static WorkflowActionResult ExecuteApproval(WorkflowActionDefinition action, WorkflowExecutionRequest request)
    {
        var inputs = ExpandInputs(action.Inputs, request.Variables);
        if (!Bool(inputs, "Approved"))
        {
            return Failed(action, "ApprovalRequired", Optional(inputs, "Prompt", "Workflow approval is required before continuing."));
        }

        return Completed(action, false, Optional(inputs, "Message", "Workflow approval confirmed."));
    }

    private static WorkflowActionResult ExecuteConditionalBranch(WorkflowActionDefinition action, WorkflowExecutionRequest request)
    {
        var inputs = ExpandInputs(action.Inputs, request.Variables);
        var condition = Required(inputs, "Condition");
        var matched = EvaluateCondition(condition, request.Variables);
        return matched
            ? Completed(action, false, Optional(inputs, "TrueMessage", "Condition evaluated to true."))
            : Skipped(action, "ConditionFalse", Optional(inputs, "FalseMessage", "Condition evaluated to false."));
    }

    private static WorkflowActionResult Completed(WorkflowActionDefinition action, bool changed, string message)
    {
        return new WorkflowActionResult { ActionId = action.Id, ActionName = action.Name, ActionType = action.Type, ProviderId = action.ProviderId, Succeeded = true, Changed = changed, Status = "Completed", Message = message };
    }

    private static int Int(IReadOnlyDictionary<string, string> inputs, string key, int fallback)
    {
        return inputs.TryGetValue(key, out var value) && int.TryParse(value, out var parsed) ? parsed : fallback;
    }

    private static IReadOnlySet<int> ExpectedStatusCodes(IReadOnlyDictionary<string, string> inputs)
    {
        var configured = Optional(inputs, "ExpectedStatusCodes");
        if (string.IsNullOrWhiteSpace(configured))
        {
            return new HashSet<int>(Enumerable.Range(200, 100));
        }

        return configured
            .Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(value => int.TryParse(value, out var parsed) ? parsed : 0)
            .Where(value => value > 0)
            .ToHashSet();
    }

    private static bool EvaluateCondition(string condition, IReadOnlyDictionary<string, string> variables)
    {
        if (string.IsNullOrWhiteSpace(condition))
        {
            return true;
        }

        var andParts = condition.Split("&&", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (andParts.Length > 1)
        {
            return andParts.All(part => EvaluateCondition(part, variables));
        }

        var orParts = condition.Split("||", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (orParts.Length > 1)
        {
            return orParts.Any(part => EvaluateCondition(part, variables));
        }

        foreach (var op in new[] { "==", "!=" })
        {
            var index = condition.IndexOf(op, StringComparison.Ordinal);
            if (index < 0)
            {
                continue;
            }

            var left = Clean(Expand(condition[..index], variables));
            var right = Clean(Expand(condition[(index + op.Length)..], variables));
            var equal = string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
            return op == "==" ? equal : !equal;
        }

        var expanded = Clean(Expand(condition, variables));
        return bool.TryParse(expanded, out var parsed) ? parsed : !string.IsNullOrWhiteSpace(expanded);
    }

    private static string Clean(string value)
    {
        return value.Trim().Trim('"').Trim('\'');
    }

    private static string TrimForResult(string value)
    {
        const int max = 1200;
        var clean = value.Replace("\r", " ", StringComparison.Ordinal).Replace("\n", " ", StringComparison.Ordinal).Trim();
        return clean.Length <= max ? clean : $"{clean[..max]}...";
    }

    private static string ChromePath()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe")
        };
        return candidates.FirstOrDefault(File.Exists) ?? "chrome.exe";
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
