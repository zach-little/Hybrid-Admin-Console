using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.NewUser;

public sealed class NativeNewUserPreflightService
{
    private readonly IUserLookupCapability _directoryLookup;
    private readonly NewUserOnboardingConfiguration _configuration;

    public NativeNewUserPreflightService(IUserLookupCapability directoryLookup)
        : this(directoryLookup, new NewUserOnboardingConfiguration())
    {
    }

    public NativeNewUserPreflightService(IUserLookupCapability directoryLookup, NewUserOnboardingConfiguration configuration)
    {
        _directoryLookup = directoryLookup;
        _configuration = configuration;
    }

    public async Task<OperationResult<NewUserExecutionPlan>> BuildPlanAsync(
        NewUserPreflightRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var steps = new List<NewUserPlanStep>
        {
            Step(NewUserPlanStepIds.ValidateRuntime, "Application", "ValidateRuntime", false, "Runtime profile supports native New User Wizard preflight.")
        };

        var missing = MissingRequiredFields(request).ToArray();
        if (missing.Length > 0)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, $"Missing required fields: {string.Join(", ", missing)}."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps, _configuration.Resolve(request)), correlationId, status: "Blocked");
        }

        var existing = await _directoryLookup.SearchUsersAsync(request.SamAccountName, correlationId, cancellationToken).ConfigureAwait(false);
        if (!existing.Succeeded)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, "Unable to confirm account uniqueness."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps, _configuration.Resolve(request)), correlationId, existing.Warnings, "Blocked");
        }

        if ((existing.Value?.Count ?? 0) > 0)
        {
            steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", true, "A matching user already exists."));
            return OperationResult<NewUserExecutionPlan>.Success(CreatePlan(request, steps, _configuration.Resolve(request)), correlationId, status: "Blocked");
        }

        var resolved = _configuration.Resolve(request);
        steps.Add(Step(NewUserPlanStepIds.CheckUniqueness, "ActiveDirectory", "CheckUniqueness", false, "No existing user matched the requested SAM account name."));
        steps.Add(Step(
            NewUserPlanStepIds.CreateDirectoryUser,
            "ActiveDirectory",
            "CreateUser",
            false,
            string.IsNullOrWhiteSpace(resolved.TargetOu)
                ? "Create the directory user."
                : $"Create the directory user in {resolved.TargetOu}."));
        if (!string.IsNullOrWhiteSpace(request.ManagerSamAccountName))
        {
            steps.Add(Step(NewUserPlanStepIds.SetManager, "ActiveDirectory", "SetManager", false, "Set the requested manager."));
        }

        foreach (var group in resolved.Groups)
        {
            steps.Add(Step($"{NewUserPlanStepIds.AddGroupMembershipPrefix}{group}", "ActiveDirectory", "AddGroupMembership", false, $"Add user to {group}."));
        }

        if (request.CreateMailbox && _configuration.Mailbox.CreateRemoteMailboxWhenRequested)
        {
            steps.Add(Step(
                NewUserPlanStepIds.EnableRemoteMailbox,
                "ExchangeOnPremises",
                "EnableRemoteMailbox",
                false,
                string.IsNullOrWhiteSpace(resolved.RemoteRoutingAddress)
                    ? "Enable the remote mailbox."
                    : $"Enable the remote mailbox with remote routing address {resolved.RemoteRoutingAddress}."));
        }

        foreach (var customStep in resolved.CustomPowerShellSteps)
        {
            steps.Add(Step(
                $"{NewUserPlanStepIds.CustomPowerShellPrefix}{customStep.Id}",
                "CustomPowerShell",
                customStep.DisplayName,
                true,
                $"Configured custom PowerShell step '{customStep.DisplayName}' is present. Execution is blocked until the command runner is explicitly enabled for the profile."));
        }

        var plan = CreatePlan(request, steps, resolved);
        return OperationResult<NewUserExecutionPlan>.Success(plan, correlationId, status: plan.CanExecute ? "Ready" : "Blocked");
    }

    private static NewUserExecutionPlan CreatePlan(NewUserPreflightRequest request, IReadOnlyList<NewUserPlanStep> steps, NewUserResolvedOnboarding resolved)
    {
        return new NewUserExecutionPlan
        {
            PlanId = $"new-user:{request.SamAccountName.Trim().ToLowerInvariant()}",
            Request = request,
            ResolvedOnboarding = resolved,
            Steps = steps
        };
    }

    private static NewUserPlanStep Step(string stepId, string providerId, string operation, bool blocking, string message)
    {
        return new NewUserPlanStep
        {
            StepId = stepId,
            ProviderId = providerId,
            Operation = operation,
            IsBlocking = blocking,
            Message = message
        };
    }

    private static IEnumerable<string> MissingRequiredFields(NewUserPreflightRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.GivenName)) yield return nameof(request.GivenName);
        if (string.IsNullOrWhiteSpace(request.Surname)) yield return nameof(request.Surname);
        if (string.IsNullOrWhiteSpace(request.SamAccountName)) yield return nameof(request.SamAccountName);
        if (string.IsNullOrWhiteSpace(request.Department)) yield return nameof(request.Department);
    }
}
