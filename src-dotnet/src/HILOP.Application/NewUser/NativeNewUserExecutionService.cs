using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.NewUser;

public sealed class NativeNewUserExecutionService
{
    private readonly ISimulatorWriteCapability _directoryWriter;
    private readonly ISimulatorWriteCapability _exchangeWriter;

    public NativeNewUserExecutionService(ISimulatorWriteCapability directoryWriter)
        : this(directoryWriter, directoryWriter)
    {
    }

    public NativeNewUserExecutionService(ISimulatorWriteCapability directoryWriter, ISimulatorWriteCapability exchangeWriter)
    {
        _directoryWriter = directoryWriter;
        _exchangeWriter = exchangeWriter;
    }

    public async Task<OperationResult<NewUserExecutionResult>> ExecuteAsync(
        NewUserExecutionPlan plan,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!plan.CanExecute)
        {
            return OperationResult<NewUserExecutionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("NewUser.PlanBlocked", "The New User Wizard plan contains blocking preflight steps.") },
                status: "Blocked");
        }

        var results = new List<NewUserExecutionStepResult>();
        foreach (var step in plan.Steps.Where(step => step.ProviderId != "Application"))
        {
            cancellationToken.ThrowIfCancellationRequested();
            OperationResult<ProviderChangeResult> result = step.StepId switch
            {
                NewUserPlanStepIds.CreateDirectoryUser => await _directoryWriter.CreateUserAsync(
                    new UserCreateRequest
                    {
                        GivenName = plan.Request.GivenName,
                        Surname = plan.Request.Surname,
                        SamAccountName = plan.Request.SamAccountName,
                        Department = plan.Request.Department,
                        Title = plan.Request.Title,
                        ManagerSamAccountName = plan.Request.ManagerSamAccountName,
                        Office = plan.Request.Office,
                        DisplayName = plan.ResolvedOnboarding.DisplayName,
                        UserPrincipalName = plan.ResolvedOnboarding.UserPrincipalName,
                        TargetOu = plan.ResolvedOnboarding.TargetOu,
                        Company = plan.ResolvedOnboarding.Company,
                        EmployeeId = plan.Request.EmployeeId,
                        BadgeId = plan.Request.BadgeId,
                        OfficePhone = plan.Request.OfficePhone,
                        MobilePhone = plan.Request.MobilePhone,
                        City = plan.ResolvedOnboarding.City,
                        StreetAddress = plan.ResolvedOnboarding.StreetAddress,
                        State = plan.ResolvedOnboarding.State,
                        PostalCode = plan.ResolvedOnboarding.PostalCode,
                        OtherAttributes = plan.ResolvedOnboarding.AdditionalAttributes
                    },
                    correlationId,
                    cancellationToken).ConfigureAwait(false),
                NewUserPlanStepIds.SetManager => await _directoryWriter.SetManagerAsync(
                    new ManagerChangeRequest { Identity = plan.Request.SamAccountName, ManagerIdentity = plan.Request.ManagerSamAccountName },
                    correlationId,
                    cancellationToken).ConfigureAwait(false),
                var stepId when stepId.StartsWith(NewUserPlanStepIds.AddGroupMembershipPrefix, StringComparison.OrdinalIgnoreCase) => await _directoryWriter.AddGroupMembershipAsync(
                    new MembershipChangeRequest { Identity = plan.Request.SamAccountName, Group = step.StepId[NewUserPlanStepIds.AddGroupMembershipPrefix.Length..] },
                    correlationId,
                    cancellationToken).ConfigureAwait(false),
                NewUserPlanStepIds.EnableRemoteMailbox => await _exchangeWriter.EnableRemoteMailboxAsync(
                    new MailboxProvisioningRequest
                    {
                        Identity = plan.Request.SamAccountName,
                        RemoteRoutingAddress = plan.ResolvedOnboarding.RemoteRoutingAddress,
                        PrimarySmtpAddress = plan.ResolvedOnboarding.UserPrincipalName
                    },
                    correlationId,
                    cancellationToken).ConfigureAwait(false),
                _ => OperationResult<ProviderChangeResult>.Success(
                    new ProviderChangeResult { Operation = step.Operation, TargetId = plan.Request.SamAccountName, Changed = false, Message = "No execution action required.", Source = step.ProviderId },
                    correlationId,
                    status: "Skipped")
            };

            results.Add(new NewUserExecutionStepResult
            {
                StepId = step.StepId,
                ProviderId = step.ProviderId,
                Operation = step.Operation,
                Succeeded = result.Succeeded,
                Changed = result.Value?.Changed ?? false,
                Status = result.Status ?? (result.Succeeded ? "Succeeded" : "Failed"),
                Message = result.Value?.Message ?? string.Join("; ", result.Errors.Select(error => error.Message))
            });

            if (!result.Succeeded)
            {
                break;
            }
        }

        var execution = new NewUserExecutionResult { PlanId = plan.PlanId, Steps = results };
        return execution.Succeeded
            ? OperationResult<NewUserExecutionResult>.Success(execution, correlationId, status: "Completed")
            : OperationResult<NewUserExecutionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("NewUser.ExecutionFailed", "New User Wizard execution failed. See step results.") },
                status: "Failed");
    }
}
