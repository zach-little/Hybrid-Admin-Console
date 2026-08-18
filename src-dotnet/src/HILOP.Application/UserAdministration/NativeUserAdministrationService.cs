using HILOP.Application.Capabilities;
using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.UserAdministration;

public sealed class NativeUserAdministrationService
{
    private readonly BuiltInCapabilityCatalog _catalog;
    private readonly IReadOnlyDictionary<string, ISimulatorWriteCapability> _writers;

    public NativeUserAdministrationService(
        BuiltInCapabilityCatalog catalog,
        IReadOnlyDictionary<string, ISimulatorWriteCapability> writers)
    {
        _catalog = catalog;
        _writers = writers;
    }

    public async Task<OperationResult<UserAdministrationActionResult>> InvokeAsync(
        UserAdministrationActionRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var capabilityId = ResolveCapabilityId(request);
        var availability = _catalog.Get(request.ProviderId, capabilityId);
        if (!availability.IsInvokableBuiltIn)
        {
            return OperationResult<UserAdministrationActionResult>.Success(
                new UserAdministrationActionResult
                {
                    ActionId = request.ActionId,
                    ProviderId = request.ProviderId,
                    Available = false,
                    Message = availability.Reason
                },
                correlationId,
                status: "Unavailable");
        }

        if (!_writers.TryGetValue(request.ProviderId, out var writer))
        {
            return OperationResult<UserAdministrationActionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("UserAdministration.ProviderUnavailable", $"No native writer is registered for {request.ProviderId}.") },
                status: "Unavailable");
        }

        var change = request.ActionId switch
        {
            UserAdministrationActionIds.ChangeManager => await writer.SetManagerAsync(
                new ManagerChangeRequest { Identity = request.Identity, ManagerIdentity = request.Value },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            UserAdministrationActionIds.AddGroupMembership => await writer.AddGroupMembershipAsync(
                new MembershipChangeRequest { Identity = request.Identity, Group = request.Value },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            UserAdministrationActionIds.RemoveGroupMembership => await writer.RemoveGroupMembershipAsync(
                new MembershipChangeRequest { Identity = request.Identity, Group = request.Value },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            UserAdministrationActionIds.SetMailboxForwarding => await writer.SetMailboxForwardingAsync(
                new MailboxForwardingRequest { Identity = request.Identity, ForwardingSmtpAddress = request.Value, DeliverToMailboxAndForward = true },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            UserAdministrationActionIds.SetGalVisibility => await writer.SetGalVisibilityAsync(
                new GalVisibilityRequest { Identity = request.Identity, HiddenFromAddressListsEnabled = bool.TryParse(request.Value, out var hidden) && hidden },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            UserAdministrationActionIds.AddMailboxDelegation => await writer.AddMailboxDelegationAsync(
                new MailboxDelegationChangeRequest { Identity = request.Identity, Trustee = request.Value, AccessRights = "FullAccess" },
                correlationId,
                cancellationToken).ConfigureAwait(false),
            _ => OperationResult<ProviderChangeResult>.Failure(
                correlationId,
                new[] { OperationError.Create("UserAdministration.UnknownAction", $"Unknown user administration action '{request.ActionId}'.") },
                status: "Unsupported")
        };

        if (!change.Succeeded)
        {
            return OperationResult<UserAdministrationActionResult>.Failure(correlationId, change.Errors, change.Warnings, change.Status);
        }

        return OperationResult<UserAdministrationActionResult>.Success(
            new UserAdministrationActionResult
            {
                ActionId = request.ActionId,
                ProviderId = request.ProviderId,
                Available = true,
                Change = change.Value,
                Message = change.Value?.Message ?? string.Empty
            },
            correlationId,
            change.Warnings,
            change.Status);
    }

    private static string ResolveCapabilityId(UserAdministrationActionRequest request)
    {
        if (request.ProviderId.Equals("DirectorySimulator", StringComparison.OrdinalIgnoreCase))
        {
            return "Simulator.AllWrites";
        }

        if (request.ProviderId.Equals("ActiveDirectory", StringComparison.OrdinalIgnoreCase))
        {
            return "AD.Write";
        }

        if (request.ProviderId.Equals("ExchangeOnline", StringComparison.OrdinalIgnoreCase))
        {
            return request.ActionId switch
            {
                UserAdministrationActionIds.SetMailboxForwarding => "ExchangeOnline.MailboxForwarding",
                UserAdministrationActionIds.SetGalVisibility => "ExchangeOnline.GalVisibility",
                UserAdministrationActionIds.AddMailboxDelegation => "ExchangeOnline.MailboxDelegation",
                UserAdministrationActionIds.AddGroupMembership or UserAdministrationActionIds.RemoveGroupMembership => "ExchangeOnline.DistributionGroups",
                _ => "ExchangeOnline.Unknown"
            };
        }

        if (request.ProviderId.Equals("ExchangeOnPremises", StringComparison.OrdinalIgnoreCase))
        {
            return request.ActionId switch
            {
                UserAdministrationActionIds.SetMailboxForwarding => "ExchangeOnPremises.MailboxForwarding",
                UserAdministrationActionIds.SetGalVisibility => "ExchangeOnPremises.GalVisibility",
                UserAdministrationActionIds.AddMailboxDelegation => "ExchangeOnPremises.MailboxDelegation",
                UserAdministrationActionIds.AddGroupMembership or UserAdministrationActionIds.RemoveGroupMembership => "ExchangeOnPremises.DistributionGroups",
                _ => "ExchangeOnPremises.Unknown"
            };
        }

        return request.ActionId;
    }
}
