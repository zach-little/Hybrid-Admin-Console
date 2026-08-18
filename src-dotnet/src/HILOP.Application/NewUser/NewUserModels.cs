using HILOP.Providers.Abstractions;

namespace HILOP.Application.NewUser;

public sealed record NewUserPreflightRequest
{
    public string GivenName { get; init; } = string.Empty;

    public string Surname { get; init; } = string.Empty;

    public string SamAccountName { get; init; } = string.Empty;

    public string Department { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string ManagerSamAccountName { get; init; } = string.Empty;

    public string Office { get; init; } = string.Empty;

    public string EmployeeId { get; init; } = string.Empty;

    public string BadgeId { get; init; } = string.Empty;

    public string OfficePhone { get; init; } = string.Empty;

    public string MobilePhone { get; init; } = string.Empty;

    public string HomeOrganization { get; init; } = string.Empty;

    public bool CreateMailbox { get; init; }

    public bool RequiresCac { get; init; }
}

public sealed record NewUserExecutionPlan
{
    public string PlanId { get; init; } = string.Empty;

    public NewUserPreflightRequest Request { get; init; } = new();

    public NewUserResolvedOnboarding ResolvedOnboarding { get; init; } = new();

    public IReadOnlyList<NewUserPlanStep> Steps { get; init; } = Array.Empty<NewUserPlanStep>();

    public bool CanExecute => Steps.All(step => !step.IsBlocking);
}

public sealed record NewUserPlanStep
{
    public string StepId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public string Operation { get; init; } = string.Empty;

    public bool IsBlocking { get; init; }

    public string Message { get; init; } = string.Empty;
}

public sealed record NewUserResolvedOnboarding
{
    public string DisplayName { get; init; } = string.Empty;

    public string UserPrincipalName { get; init; } = string.Empty;

    public string TargetOu { get; init; } = string.Empty;

    public string Company { get; init; } = string.Empty;

    public string City { get; init; } = string.Empty;

    public string StreetAddress { get; init; } = string.Empty;

    public string State { get; init; } = string.Empty;

    public string PostalCode { get; init; } = string.Empty;

    public string RemoteRoutingAddress { get; init; } = string.Empty;

    public IReadOnlyList<string> Groups { get; init; } = Array.Empty<string>();

    public IReadOnlyDictionary<string, string> AdditionalAttributes { get; init; } = new Dictionary<string, string>();

    public IReadOnlyList<NewUserCustomPowerShellStep> CustomPowerShellSteps { get; init; } = Array.Empty<NewUserCustomPowerShellStep>();
}

public sealed record NewUserExecutionResult
{
    public string PlanId { get; init; } = string.Empty;

    public IReadOnlyList<NewUserExecutionStepResult> Steps { get; init; } = Array.Empty<NewUserExecutionStepResult>();

    public bool Succeeded => Steps.All(step => step.Succeeded);
}

public sealed record NewUserExecutionStepResult
{
    public string StepId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public string Operation { get; init; } = string.Empty;

    public bool Succeeded { get; init; }

    public bool Changed { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;
}

public static class NewUserPlanStepIds
{
    public const string ValidateRuntime = "validate-runtime";
    public const string CheckUniqueness = "check-uniqueness";
    public const string CreateDirectoryUser = "create-directory-user";
    public const string SetManager = "set-manager";
    public const string AddGroupMembershipPrefix = "add-group:";
    public const string EnableRemoteMailbox = "enable-remote-mailbox";
    public const string CustomPowerShellPrefix = "custom-powershell:";
}
