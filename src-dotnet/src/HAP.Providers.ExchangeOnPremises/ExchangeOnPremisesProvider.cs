using System.Diagnostics;
using System.Text.Json;
using HAP.Contracts;
using HAP.Providers.Abstractions;

namespace HAP.Providers.ExchangeOnPremises;

public sealed class ExchangeOnPremisesProvider : IProviderHealthCapability, IExchangeReadCapability, ISimulatorWriteCapability
{
    private readonly ExchangeOnPremisesProviderOptions _options;

    public ExchangeOnPremisesProvider(ExchangeOnPremisesProviderOptions? options = null)
    {
        _options = options ?? new ExchangeOnPremisesProviderOptions();
    }

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var errors = ValidateConnection();
        if (errors.Count > 0) return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(correlationId, errors, status: "Failed"));
        return Task.FromResult(OperationResult<ProviderHealthResult>.Success(new ProviderHealthResult
        {
            ProviderId = "ExchangeOnPremises",
            Mode = _options.UsePowerShell ? "RemoteExchangePowerShell" : "NativeSupportedApisOnly",
            Enabled = true,
            Required = false,
            Status = _options.UsePowerShell ? "Connected" : "Limited",
            Message = _options.UsePowerShell ? "Exchange on-premises remote PowerShell provider is enabled." : "Exchange on-premises PowerShell provider is not enabled for this profile.",
            Available = true,
            Connected = _options.UsePowerShell
        }, correlationId, status: _options.UsePowerShell ? "Connected" : "Limited"));
    }

    public async Task<OperationResult<MailboxSummary?>> GetMailboxAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!EnsurePowerShell<MailboxSummary?>(correlationId, out var failure)) return failure!;
        var json = await InvokeExchangeAsync($@"
$mailbox = Get-Mailbox -Identity '{Ps(identity)}' -ErrorAction Stop
[pscustomobject]@{{
  DisplayName = [string]$mailbox.DisplayName
  PrimarySmtpAddress = [string]$mailbox.PrimarySmtpAddress
  EmailAddresses = @($mailbox.EmailAddresses | ForEach-Object {{ [string]$_ }})
  UserPrincipalName = [string]$mailbox.UserPrincipalName
  RecipientTypeDetails = [string]$mailbox.RecipientTypeDetails
  ExchangeGuid = [string]$mailbox.ExchangeGuid
  HiddenFromAddressListsEnabled = [bool]$mailbox.HiddenFromAddressListsEnabled
  LitigationHoldEnabled = [bool]$mailbox.LitigationHoldEnabled
  DeliverToMailboxAndForward = [bool]$mailbox.DeliverToMailboxAndForward
  ForwardingSmtpAddress = [string]$mailbox.ForwardingSmtpAddress
}} | ConvertTo-Json -Compress -Depth 4", cancellationToken).ConfigureAwait(false);
        if (!json.Succeeded) return OperationResult<MailboxSummary?>.Failure(correlationId, json.Errors, status: json.Status);
        var value = JsonSerializer.Deserialize<MailboxDto>(json.Value ?? "{}");
        return OperationResult<MailboxSummary?>.Success(value is null ? null : MapMailbox(value), correlationId);
    }

    public async Task<OperationResult<MailboxStatisticsSummary?>> GetMailboxStatisticsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!EnsurePowerShell<MailboxStatisticsSummary?>(correlationId, out var failure)) return failure!;
        var json = await InvokeExchangeAsync($@"
$stats = Get-MailboxStatistics -Identity '{Ps(identity)}' -ErrorAction Stop
[pscustomobject]@{{
  DisplayName = [string]$stats.DisplayName
  TotalItemSize = [string]$stats.TotalItemSize
  ItemCount = [int]$stats.ItemCount
  LastLogonTime = if ($stats.LastLogonTime) {{ $stats.LastLogonTime.ToString('o') }} else {{ $null }}
}} | ConvertTo-Json -Compress -Depth 4", cancellationToken).ConfigureAwait(false);
        if (!json.Succeeded) return OperationResult<MailboxStatisticsSummary?>.Failure(correlationId, json.Errors, status: json.Status);
        return OperationResult<MailboxStatisticsSummary?>.Success(MapStatistics(JsonSerializer.Deserialize<MailboxStatisticsDto>(json.Value ?? "{}")), correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<MailboxDelegationSummary>>> GetMailboxDelegationsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!EnsurePowerShell<IReadOnlyList<MailboxDelegationSummary>>(correlationId, out var failure)) return failure!;
        var json = await InvokeExchangeAsync($@"
@(Get-MailboxPermission -Identity '{Ps(identity)}' -ErrorAction Stop |
  Where-Object {{ -not $_.IsInherited -and $_.User -notlike 'NT AUTHORITY\SELF' }} |
  Select-Object @{{n='Trustee';e={{[string]$_.User}}}}, @{{n='AccessRights';e={{[string]($_.AccessRights -join ',')}}}}, @{{n='Inherited';e={{[bool]$_.IsInherited}}}}, @{{n='Identity';e={{'{Ps(identity)}'}}}}) | ConvertTo-Json -Compress -Depth 5", cancellationToken).ConfigureAwait(false);
        if (!json.Succeeded) return OperationResult<IReadOnlyList<MailboxDelegationSummary>>.Failure(correlationId, json.Errors, status: json.Status);
        return OperationResult<IReadOnlyList<MailboxDelegationSummary>>.Success(ReadArray<MailboxDelegationDto>(json.Value).Select(MapDelegation).ToArray(), correlationId);
    }

    public async Task<OperationResult<IReadOnlyList<DistributionGroupSummary>>> GetDistributionGroupsAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        if (!EnsurePowerShell<IReadOnlyList<DistributionGroupSummary>>(correlationId, out var failure)) return failure!;
        var json = await InvokeExchangeAsync($@"
@(Get-DistributionGroup -ResultSize Unlimited -Filter ""Members -eq '{Ps(identity)}'"" -ErrorAction SilentlyContinue |
  Select-Object @{{n='Id';e={{[string]$_.Identity}}}}, @{{n='DisplayName';e={{[string]$_.DisplayName}}}}, @{{n='Mail';e={{[string]$_.PrimarySmtpAddress}}}}, @{{n='Source';e={{'ExchangeOnPremises.PowerShell'}}}}) | ConvertTo-Json -Compress -Depth 5", cancellationToken).ConfigureAwait(false);
        if (!json.Succeeded) return OperationResult<IReadOnlyList<DistributionGroupSummary>>.Failure(correlationId, json.Errors, status: json.Status);
        return OperationResult<IReadOnlyList<DistributionGroupSummary>>.Success(ReadArray<DistributionGroupDto>(json.Value).Select(MapDistributionGroup).ToArray(), correlationId);
    }

    public Task<OperationResult<ProviderChangeResult>> CreateUserAsync(UserCreateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "CreateUser", request.SamAccountName, "ExchangeOnPremises.UserCreate.NotExchangeResponsibility", "User creation is not an Exchange on-premises responsibility in native HAP.");

    public Task<OperationResult<ProviderChangeResult>> UpdateUserAttributesAsync(UserUpdateRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "UpdateUserAttributes", request.Identity, "ExchangeOnPremises.UserAttributes.NotExchangeResponsibility", "Directory user attributes are handled by Active Directory.");

    public Task<OperationResult<ProviderChangeResult>> SetManagerAsync(ManagerChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        UnsupportedChange(correlationId, "SetManager", request.Identity, "ExchangeOnPremises.Manager.NotExchangeResponsibility", "Manager changes are handled by Active Directory.");

    public Task<OperationResult<ProviderChangeResult>> AddGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        InvokeChangeAsync("AddDistributionGroupMember", request.Group, $"Add-DistributionGroupMember -Identity '{Ps(request.Group)}' -Member '{Ps(request.Identity)}' -BypassSecurityGroupManagerCheck -ErrorAction Stop", correlationId, cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> RemoveGroupMembershipAsync(MembershipChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        InvokeChangeAsync("RemoveDistributionGroupMember", request.Group, $"Remove-DistributionGroupMember -Identity '{Ps(request.Group)}' -Member '{Ps(request.Identity)}' -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction Stop", correlationId, cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> SetMailboxForwardingAsync(MailboxForwardingRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var clear = string.IsNullOrWhiteSpace(request.ForwardingSmtpAddress);
        var command = clear
            ? $"Set-Mailbox -Identity '{Ps(request.Identity)}' -ForwardingSmtpAddress $null -DeliverToMailboxAndForward:$false -ErrorAction Stop"
            : $"Set-Mailbox -Identity '{Ps(request.Identity)}' -ForwardingSmtpAddress '{Ps(request.ForwardingSmtpAddress)}' -DeliverToMailboxAndForward:${request.DeliverToMailboxAndForward.ToString().ToLowerInvariant()} -ErrorAction Stop";
        return InvokeChangeAsync("SetMailboxForwarding", request.Identity, command, correlationId, cancellationToken);
    }

    public Task<OperationResult<ProviderChangeResult>> SetGalVisibilityAsync(GalVisibilityRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        InvokeChangeAsync("SetGalVisibility", request.Identity, $"Set-Mailbox -Identity '{Ps(request.Identity)}' -HiddenFromAddressListsEnabled:${request.HiddenFromAddressListsEnabled.ToString().ToLowerInvariant()} -ErrorAction Stop", correlationId, cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> AddMailboxDelegationAsync(MailboxDelegationChangeRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        InvokeChangeAsync("AddMailboxDelegation", request.Identity, $"Add-MailboxPermission -Identity '{Ps(request.Identity)}' -User '{Ps(request.Trustee)}' -AccessRights {PsBare(request.AccessRights)} -InheritanceType All -AutoMapping:$false -ErrorAction Stop", correlationId, cancellationToken);

    public Task<OperationResult<ProviderChangeResult>> EnableRemoteMailboxAsync(MailboxProvisioningRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var routing = string.IsNullOrWhiteSpace(request.RemoteRoutingAddress)
            ? string.Empty
            : $" -RemoteRoutingAddress '{Ps(request.RemoteRoutingAddress)}'";
        var primary = string.IsNullOrWhiteSpace(request.PrimarySmtpAddress)
            ? string.Empty
            : $" -PrimarySmtpAddress '{Ps(request.PrimarySmtpAddress)}'";
        return InvokeChangeAsync("EnableRemoteMailbox", request.Identity, $"Enable-RemoteMailbox -Identity '{Ps(request.Identity)}'{routing}{primary} -ErrorAction Stop", correlationId, cancellationToken);
    }

    public Task<OperationResult<ProviderChangeResult>> ResetStateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default) =>
        Task.FromResult(OperationResult<ProviderChangeResult>.Success(Change("ResetState", "ExchangeOnPremises", false, "Native Exchange on-premises provider has no local mutable state."), correlationId, status: "NoChange"));

    private async Task<OperationResult<ProviderChangeResult>> InvokeChangeAsync(string operation, string target, string command, CorrelationId correlationId, CancellationToken cancellationToken)
    {
        if (!EnsurePowerShell<ProviderChangeResult>(correlationId, out var failure)) return failure!;
        var result = await InvokeExchangeAsync($"{command}; [pscustomobject]@{{Changed=$true;Message='{Ps(operation)} completed.'}} | ConvertTo-Json -Compress", cancellationToken).ConfigureAwait(false);
        return result.Succeeded
            ? OperationResult<ProviderChangeResult>.Success(Change(operation, target, true, $"{operation} completed."), correlationId, status: "Updated")
            : OperationResult<ProviderChangeResult>.Failure(correlationId, result.Errors, status: result.Status);
    }

    private async Task<OperationResult<string>> InvokeExchangeAsync(string body, CancellationToken cancellationToken)
    {
        var script = $@"
$ErrorActionPreference='Stop'
$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri '{Ps(ConnectionUri())}' -Authentication {Authentication()} -ErrorAction Stop
try {{
  Import-PSSession $session -DisableNameChecking -AllowClobber | Out-Null
  {body}
}} finally {{
  if ($session) {{ Remove-PSSession $session -ErrorAction SilentlyContinue }}
}}";
        return await RunPowerShellAsync(script, cancellationToken).ConfigureAwait(false);
    }

    private async Task<OperationResult<string>> RunPowerShellAsync(string script, CancellationToken cancellationToken)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoLogo -NoProfile -ExecutionPolicy Bypass -Command \"{script.Replace("\"", "`\"", StringComparison.Ordinal)}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Unable to start Windows PowerShell.");
            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            var output = await outputTask.ConfigureAwait(false);
            var error = await errorTask.ConfigureAwait(false);
            return process.ExitCode == 0
                ? OperationResult<string>.Success(output.Trim(), CorrelationId.New())
                : OperationResult<string>.Failure(CorrelationId.New(), new[] { OperationError.Create("ExchangeOnPremises.PowerShellFailed", "Exchange on-premises PowerShell command failed.", error) }, status: "Failed");
        }
        catch (Exception ex)
        {
            return OperationResult<string>.Failure(CorrelationId.New(), new[] { OperationError.Create("ExchangeOnPremises.PowerShellLaunchFailed", ex.Message) }, status: "Failed");
        }
    }

    private bool EnsurePowerShell<T>(CorrelationId correlationId, out OperationResult<T>? result)
    {
        var errors = ValidateConnection();
        if (errors.Count > 0) { result = OperationResult<T>.Failure(correlationId, errors, status: "Failed"); return false; }
        if (!_options.UsePowerShell) { result = OperationResult<T>.Failure(correlationId, new[] { OperationError.Create("ExchangeOnPremises.PowerShellDisabled", "Exchange on-premises PowerShell is not enabled for this runtime profile.") }, status: "Unsupported"); return false; }
        if (string.IsNullOrWhiteSpace(ConnectionUri())) { result = OperationResult<T>.Failure(correlationId, new[] { OperationError.Create("ExchangeOnPremises.ConnectionUriMissing", "Exchange on-premises server or connection URI is required.") }, status: "Failed"); return false; }
        result = null;
        return true;
    }

    private IReadOnlyList<OperationError> ValidateConnection()
    {
        var errors = new List<OperationError>();
        if (!_options.ConnectionAvailable) errors.Add(OperationError.Create("ExchangeOnPremises.ConnectionFailed", "Exchange on-premises connection failed."));
        if (!_options.AuthenticationSucceeded) errors.Add(OperationError.Create("ExchangeOnPremises.AuthenticationFailed", "Exchange on-premises authentication failed."));
        return errors;
    }

    private string ConnectionUri() => !string.IsNullOrWhiteSpace(_options.ConnectionUri) ? _options.ConnectionUri : string.IsNullOrWhiteSpace(_options.Server) ? string.Empty : $"http://{_options.Server}/PowerShell/";

    private string Authentication() => string.IsNullOrWhiteSpace(_options.Authentication) ? "Kerberos" : PsBare(_options.Authentication);

    private static IReadOnlyList<T> ReadArray<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<T>();
        var trimmed = json.Trim();
        return trimmed.StartsWith("[", StringComparison.Ordinal)
            ? JsonSerializer.Deserialize<T[]>(trimmed) ?? Array.Empty<T>()
            : new[] { JsonSerializer.Deserialize<T>(trimmed)! }.Where(item => item is not null).ToArray();
    }

    private static MailboxSummary MapMailbox(MailboxDto dto) => new()
    {
        DisplayName = dto.DisplayName ?? string.Empty,
        PrimarySmtpAddress = dto.PrimarySmtpAddress ?? string.Empty,
        EmailAddresses = dto.EmailAddresses ?? Array.Empty<string>(),
        UserPrincipalName = dto.UserPrincipalName ?? string.Empty,
        RecipientTypeDetails = dto.RecipientTypeDetails ?? string.Empty,
        ExchangeGuid = dto.ExchangeGuid ?? string.Empty,
        HiddenFromAddressListsEnabled = dto.HiddenFromAddressListsEnabled,
        LitigationHoldEnabled = dto.LitigationHoldEnabled,
        DeliverToMailboxAndForward = dto.DeliverToMailboxAndForward,
        ForwardingSmtpAddress = dto.ForwardingSmtpAddress ?? string.Empty,
        Source = "ExchangeOnPremises.PowerShell"
    };

    private static MailboxStatisticsSummary? MapStatistics(MailboxStatisticsDto? dto) => dto is null ? null : new()
    {
        DisplayName = dto.DisplayName ?? string.Empty,
        TotalItemSize = dto.TotalItemSize ?? string.Empty,
        ItemCount = dto.ItemCount,
        LastLogonTime = DateTimeOffset.TryParse(dto.LastLogonTime, out var parsed) ? parsed : null
    };

    private static MailboxDelegationSummary MapDelegation(MailboxDelegationDto dto) => new() { Trustee = dto.Trustee ?? string.Empty, AccessRights = dto.AccessRights ?? string.Empty, Inherited = dto.Inherited, Identity = dto.Identity ?? string.Empty };

    private static DistributionGroupSummary MapDistributionGroup(DistributionGroupDto dto) => new() { Id = dto.Id ?? string.Empty, DisplayName = dto.DisplayName ?? string.Empty, Mail = dto.Mail ?? string.Empty, Source = string.IsNullOrWhiteSpace(dto.Source) ? "ExchangeOnPremises.PowerShell" : dto.Source! };

    private static ProviderChangeResult Change(string operation, string targetId, bool changed, string message) => new() { Operation = operation, TargetId = targetId, Changed = changed, Message = message, Source = "ExchangeOnPremises.PowerShell" };

    private static Task<OperationResult<ProviderChangeResult>> UnsupportedChange(CorrelationId correlationId, string operation, string targetId, string code, string message) => Task.FromResult(OperationResult<ProviderChangeResult>.Failure(correlationId, new[] { OperationError.Create(code, message, operation) }, status: "Unsupported"));

    private static string Ps(string value) => (value ?? string.Empty).Replace("'", "''", StringComparison.Ordinal);

    private static string PsBare(string value) => string.IsNullOrWhiteSpace(value) ? "Kerberos" : value.Replace("'", string.Empty, StringComparison.Ordinal);

    private sealed record MailboxDto(string? DisplayName, string? PrimarySmtpAddress, IReadOnlyList<string>? EmailAddresses, string? UserPrincipalName, string? RecipientTypeDetails, string? ExchangeGuid, bool HiddenFromAddressListsEnabled, bool LitigationHoldEnabled, bool DeliverToMailboxAndForward, string? ForwardingSmtpAddress);
    private sealed record MailboxStatisticsDto(string? DisplayName, string? TotalItemSize, int ItemCount, string? LastLogonTime);
    private sealed record MailboxDelegationDto(string? Trustee, string? AccessRights, bool Inherited, string? Identity);
    private sealed record DistributionGroupDto(string? Id, string? DisplayName, string? Mail, string? Source);
}
