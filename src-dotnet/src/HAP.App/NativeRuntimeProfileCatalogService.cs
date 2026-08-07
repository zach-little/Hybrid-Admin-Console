using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using HAP.Application.RuntimeProfiles;
using HAP.Contracts;

namespace HAP.App;

internal sealed class NativeRuntimeProfileCatalogService : IRuntimeProfileCatalogService, IRuntimeProfileManagementService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var profilesRoot = GetProfilesRoot(repositoryRoot);
            var activeProfile = GetActiveProfileName(profilesRoot);
            if (!Directory.Exists(profilesRoot))
            {
                Directory.CreateDirectory(profilesRoot);
            }

            var profiles = Directory.EnumerateDirectories(profilesRoot)
                .Select(folder => LoadProfileSummary(folder, activeProfile))
                .OrderByDescending(profile => profile.IsDefault)
                .ThenBy(profile => profile.DisplayName, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            return Task.FromResult(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Success(profiles, correlationId, status: "Completed"));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Failure(
                correlationId,
                new[] { OperationError.Create("RuntimeProfile.LoadFailed", ex.Message) }));
        }
    }

    public Task<OperationResult<RuntimeProfileConfigurationDraft>> GetProfileConfigurationAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var profileRoot = GetProfileRoot(repositoryRoot, profileName);
            var runtime = LoadObject(Path.Combine(profileRoot, "runtime.json"));
            var config = LoadObject(Path.Combine(profileRoot, "config.json"));
            var branding = LoadObject(Path.Combine(profileRoot, "branding.json"));
            var wizard = config["NewUserWizard"] as JsonObject ?? new JsonObject();
            var authentication = runtime["Authentication"] as JsonObject ?? new JsonObject();
            var appOnly = authentication["AppOnly"] as JsonObject ?? new JsonObject();
            var delegated = authentication["Delegated"] as JsonObject ?? new JsonObject();
            var activeDirectory = runtime["Providers"]?["ActiveDirectory"] as JsonObject ?? new JsonObject();
            var exchangeOnPremises = runtime["Providers"]?["ExchangeOnPremises"] as JsonObject ?? new JsonObject();

            var draft = new RuntimeProfileConfigurationDraft
            {
                ProfileName = GetString(runtime, "ProfileName", profileName),
                DisplayName = GetString(runtime, "DisplayName", profileName),
                Organization = GetString(runtime, "Organization", profileName),
                Environment = GetString(runtime, "Environment", string.Empty),
                RuntimeMode = GetString(runtime, "Mode", "Simulation"),
                CloudEnvironment = GetString(runtime, "Cloud", "Commercial"),
                TenantId = GetString(runtime, "TenantId", string.Empty),
                AppOnlyEnabled = GetBool(appOnly, "Enabled", false),
                AppOnlyTenantDomain = GetString(appOnly, "TenantDomain", string.Empty),
                AppOnlyClientId = GetString(appOnly, "ClientId", FirstNonEmpty(GetString(config, "ClientId", string.Empty), GetString(config, "client_id", string.Empty))),
                AppOnlyCredentialMode = GetString(appOnly, "CredentialMode", "Certificate"),
                CertificateThumbprint = GetString(appOnly, "CertificateThumbprint", string.Empty),
                CertificatePath = GetString(appOnly, "CertificatePath", string.Empty),
                SecretReference = GetString(appOnly, "SecretReference", FirstNonEmpty(GetString(config, "client_secret", string.Empty), GetString(config, "SecretReference", string.Empty))),
                DelegatedEnabled = GetBool(delegated, "Enabled", false),
                DelegatedPromptWhenRequired = GetBool(delegated, "PromptWhenRequired", false),
                ActiveDirectoryDomain = GetString(activeDirectory, "Domain", string.Empty),
                ActiveDirectoryServer = GetString(activeDirectory, "Server", string.Empty),
                ActiveDirectoryDefaultUserContainer = GetString(activeDirectory, "DefaultUserContainer", string.Empty),
                ExchangeOnPremisesServer = GetString(exchangeOnPremises, "Server", string.Empty),
                ExchangeOnPremisesConnectionUri = GetString(exchangeOnPremises, "ConnectionUri", string.Empty),
                ExchangeOnPremisesAuthentication = GetString(exchangeOnPremises, "Authentication", "Kerberos"),
                HybridConnectionServer = GetString(EnsureObject(runtime, "HybridConnection"), "Server", string.Empty),
                NotificationRecipient = FirstNonEmpty(GetString(wizard, "NotificationRecipient", string.Empty), GetString(config, "new_user_notification_recipient", string.Empty)),
                NotificationSender = FirstNonEmpty(GetString(wizard, "NotificationSender", string.Empty), GetString(config, "new_user_notification_sender", string.Empty)),
                Departments = JoinNames(wizard["Departments"]),
                Locations = JoinNames(wizard["Locations"]),
                JobTitles = JoinValues(wizard["JobTitles"]),
                Portfolios = JoinValues(wizard["Portfolios"]),
                DefaultLicenseSet = JoinValues(wizard["DefaultLicenseSet"]),
                NewUserWizardJson = wizard.ToJsonString(JsonOptions),
                DirectorySimulatorEnabled = GetProviderEnabled(runtime, "DirectorySimulator"),
                ActiveDirectoryEnabled = GetProviderEnabled(runtime, "ActiveDirectory"),
                MicrosoftGraphEnabled = GetProviderEnabled(runtime, "MicrosoftGraph"),
                ExchangeOnlineEnabled = GetProviderEnabled(runtime, "ExchangeOnline"),
                ExchangeOnPremisesEnabled = GetProviderEnabled(runtime, "ExchangeOnPremises"),
                CreateMailboxByDefault = GetBool(wizard, "CreateMailboxByDefault", true),
                SendOnboardingNotification = GetBool(wizard, "SendOnboardingNotification", true),
                RequireManagerValidation = GetBool(wizard, "RequireManagerValidation", true),
                WindowTitle = GetString(branding, "WindowTitle", GetString(branding, "DisplayName", GetString(runtime, "DisplayName", "Hybrid Admin Platform"))),
                ThemeName = GetString(branding, "ThemeName", string.Empty),
                PrimaryColor = GetString(branding, "PrimaryColor", "#0F6CBD"),
                AccentColor = GetString(branding, "AccentColor", "#38BDF8"),
                BackgroundColor = GetString(branding, "BackgroundColor", "#0B1220"),
                SurfaceColor = FirstNonEmpty(GetString(branding, "SurfaceColor", string.Empty), GetString(branding, "PanelColor", string.Empty), "#1E293B"),
                ForegroundColor = GetString(branding, "ForegroundColor", "#F8FAFC"),
                MutedTextColor = GetString(branding, "MutedTextColor", "#94A3B8"),
                LogoPath = FirstNonEmpty(GetString(branding, "LogoPath", string.Empty), GetString(branding, "Logo", string.Empty)),
                IconPath = FirstNonEmpty(GetString(branding, "IconPath", string.Empty), GetString(branding, "Icon", string.Empty)),
                SplashPath = GetString(branding, "SplashPath", string.Empty),
                ThemeMode = GetString(branding, "Theme", "Dark")
            };

            return Task.FromResult(OperationResult<RuntimeProfileConfigurationDraft>.Success(draft, correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<RuntimeProfileConfigurationDraft>.Failure(
                correlationId,
                new[] { OperationError.Create("RuntimeProfile.ConfigurationLoadFailed", ex.Message, profileName) }));
        }
    }

    public Task<OperationResult<string>> SaveProfileConfigurationAsync(
        string repositoryRoot,
        RuntimeProfileConfigurationDraft draft,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var profileRoot = GetProfileRoot(repositoryRoot, draft.ProfileName);
            var runtimePath = Path.Combine(profileRoot, "runtime.json");
            var configPath = Path.Combine(profileRoot, "config.json");
            var brandingPath = Path.Combine(profileRoot, "branding.json");
            var runtime = LoadObject(runtimePath);
            var config = LoadObject(configPath);
            var branding = LoadObject(brandingPath);
            var wizard = ParseWizardJson(draft.NewUserWizardJson);
            var authentication = EnsureObject(runtime, "Authentication");
            var appOnly = EnsureObject(authentication, "AppOnly");
            var delegated = EnsureObject(authentication, "Delegated");
            var hybridConnection = EnsureObject(runtime, "HybridConnection");

            runtime["DisplayName"] = draft.DisplayName;
            runtime["Organization"] = draft.Organization;
            runtime["Environment"] = draft.Environment;
            runtime["Mode"] = draft.RuntimeMode;
            runtime["Cloud"] = draft.CloudEnvironment;
            runtime["TenantId"] = draft.TenantId;
            authentication["Cloud"] = draft.CloudEnvironment;
            appOnly["Enabled"] = draft.AppOnlyEnabled;
            appOnly["TenantId"] = draft.TenantId;
            appOnly["TenantDomain"] = draft.AppOnlyTenantDomain;
            appOnly["ClientId"] = draft.AppOnlyClientId;
            appOnly["CredentialMode"] = draft.AppOnlyCredentialMode;
            appOnly["CertificateThumbprint"] = draft.CertificateThumbprint;
            appOnly["CertificatePath"] = draft.CertificatePath;
            appOnly["SecretReference"] = draft.SecretReference;
            delegated["Enabled"] = draft.DelegatedEnabled;
            delegated["PromptWhenRequired"] = draft.DelegatedPromptWhenRequired;
            SetProvider(runtime, "DirectorySimulator", draft.DirectorySimulatorEnabled);
            SetProvider(runtime, "ActiveDirectory", draft.ActiveDirectoryEnabled);
            SetProvider(runtime, "MicrosoftGraph", draft.MicrosoftGraphEnabled);
            SetProvider(runtime, "ExchangeOnline", draft.ExchangeOnlineEnabled);
            SetProvider(runtime, "ExchangeOnPremises", draft.ExchangeOnPremisesEnabled);
            SetProviderProperty(runtime, "ActiveDirectory", "Domain", draft.ActiveDirectoryDomain);
            SetProviderProperty(runtime, "ActiveDirectory", "Server", draft.ActiveDirectoryServer);
            SetProviderProperty(runtime, "ActiveDirectory", "DefaultUserContainer", draft.ActiveDirectoryDefaultUserContainer);
            SetProviderProperty(runtime, "ExchangeOnPremises", "Server", draft.ExchangeOnPremisesServer);
            SetProviderProperty(runtime, "ExchangeOnPremises", "ConnectionUri", draft.ExchangeOnPremisesConnectionUri);
            SetProviderProperty(runtime, "ExchangeOnPremises", "Authentication", draft.ExchangeOnPremisesAuthentication);
            hybridConnection["Server"] = draft.HybridConnectionServer;
            hybridConnection["RemoteRunEnabled"] = !string.IsNullOrWhiteSpace(draft.HybridConnectionServer);

            config["TenantId"] = draft.TenantId;
            config["ClientId"] = draft.AppOnlyClientId;
            config["DelegatedClientId"] = draft.AppOnlyClientId;
            config["client_secret"] = draft.SecretReference;
            config["new_user_notification_recipient"] = draft.NotificationRecipient;
            config["new_user_notification_sender"] = draft.NotificationSender;
            wizard["NotificationRecipient"] = draft.NotificationRecipient;
            wizard["NotificationSender"] = draft.NotificationSender;
            wizard["Departments"] = BuildNamedArray(draft.Departments);
            wizard["Locations"] = BuildNamedArray(draft.Locations);
            wizard["JobTitles"] = BuildStringArray(draft.JobTitles);
            wizard["Portfolios"] = BuildStringArray(draft.Portfolios);
            wizard["DefaultLicenseSet"] = BuildStringArray(draft.DefaultLicenseSet);
            wizard["CreateMailboxByDefault"] = draft.CreateMailboxByDefault;
            wizard["SendOnboardingNotification"] = draft.SendOnboardingNotification;
            wizard["RequireManagerValidation"] = draft.RequireManagerValidation;
            config["NewUserWizard"] = wizard;

            branding["WindowTitle"] = draft.WindowTitle;
            branding["DisplayName"] = draft.WindowTitle;
            branding["Organization"] = draft.Organization;
            branding["ThemeName"] = draft.ThemeName;
            branding["PrimaryColor"] = draft.PrimaryColor;
            branding["AccentColor"] = draft.AccentColor;
            branding["BackgroundColor"] = draft.BackgroundColor;
            branding["SurfaceColor"] = draft.SurfaceColor;
            branding["PanelColor"] = draft.SurfaceColor;
            branding["ForegroundColor"] = draft.ForegroundColor;
            branding["MutedTextColor"] = draft.MutedTextColor;
            branding["LogoPath"] = draft.LogoPath;
            branding["Logo"] = draft.LogoPath;
            branding["IconPath"] = draft.IconPath;
            branding["Icon"] = draft.IconPath;
            branding["SplashPath"] = draft.SplashPath;
            branding["Theme"] = draft.ThemeMode;

            SaveObject(runtimePath, runtime);
            SaveObject(configPath, config);
            SaveObject(brandingPath, branding);

            return Task.FromResult(OperationResult<string>.Success($"Saved profile '{draft.ProfileName}'.", correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<string>.Failure(
                correlationId,
                new[] { OperationError.Create("RuntimeProfile.SaveFailed", ex.Message, draft.ProfileName) }));
        }
    }

    public Task<OperationResult<string>> CreateProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var cleanName = CleanName(profileName);
            if (string.IsNullOrWhiteSpace(cleanName))
            {
                return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.NameRequired", "Profile name is required.") }));
            }

            var profilesRoot = GetProfilesRoot(repositoryRoot);
            var target = Path.Combine(profilesRoot, cleanName);
            if (Directory.Exists(target))
            {
                return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.AlreadyExists", "A profile with that name already exists.", cleanName) }));
            }

            var source = Directory.Exists(Path.Combine(profilesRoot, "Simulation"))
                ? Path.Combine(profilesRoot, "Simulation")
                : Directory.EnumerateDirectories(profilesRoot).FirstOrDefault();
            Directory.CreateDirectory(target);
            if (!string.IsNullOrWhiteSpace(source))
            {
                CopyDirectory(source, target);
            }

            var runtimePath = Path.Combine(target, "runtime.json");
            var runtime = LoadObject(runtimePath);
            runtime["ProfileName"] = cleanName;
            runtime["DisplayName"] = cleanName;
            runtime["Organization"] = cleanName;
            runtime["ProfileRoot"] = Path.Combine("profiles", cleanName);
            runtime["IsDefault"] = false;
            SaveObject(runtimePath, runtime);

            return Task.FromResult(OperationResult<string>.Success($"Created profile '{cleanName}'.", correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.CreateFailed", ex.Message, profileName) }));
        }
    }

    public Task<OperationResult<string>> DeleteProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var profilesRoot = GetProfilesRoot(repositoryRoot);
            var profileRoot = GetProfileRoot(repositoryRoot, profileName);
            if (string.Equals(GetActiveProfileName(profilesRoot), profileName, StringComparison.OrdinalIgnoreCase))
            {
                return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.DeleteDefaultBlocked", "Set another profile as default before deleting this profile.", profileName) }));
            }

            Directory.Delete(profileRoot, recursive: true);
            return Task.FromResult(OperationResult<string>.Success($"Deleted profile '{profileName}'.", correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.DeleteFailed", ex.Message, profileName) }));
        }
    }

    public Task<OperationResult<string>> SetDefaultProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var profilesRoot = GetProfilesRoot(repositoryRoot);
            _ = GetProfileRoot(repositoryRoot, profileName);
            SaveObject(Path.Combine(profilesRoot, "active.json"), new JsonObject
            {
                ["ActiveProfile"] = profileName,
                ["UpdatedAtUtc"] = DateTimeOffset.UtcNow.ToString("O")
            });

            foreach (var folder in Directory.EnumerateDirectories(profilesRoot))
            {
                var runtimePath = Path.Combine(folder, "runtime.json");
                if (!File.Exists(runtimePath))
                {
                    continue;
                }

                var runtime = LoadObject(runtimePath);
                runtime["IsDefault"] = string.Equals(Path.GetFileName(folder), profileName, StringComparison.OrdinalIgnoreCase);
                SaveObject(runtimePath, runtime);
            }

            return Task.FromResult(OperationResult<string>.Success($"Set '{profileName}' as default.", correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.SetDefaultFailed", ex.Message, profileName) }));
        }
    }

    public Task<OperationResult<string>> ExportProfileAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        try
        {
            var source = GetProfileRoot(repositoryRoot, profileName);
            var exportRoot = Path.Combine(repositoryRoot, "exports", "profiles");
            Directory.CreateDirectory(exportRoot);
            var target = Path.Combine(exportRoot, $"{profileName}-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}");
            CopyDirectory(source, target);
            return Task.FromResult(OperationResult<string>.Success($"Exported profile to {target}.", correlationId));
        }
        catch (Exception ex)
        {
            return Task.FromResult(OperationResult<string>.Failure(correlationId, new[] { OperationError.Create("RuntimeProfile.ExportFailed", ex.Message, profileName) }));
        }
    }

    private static RuntimeProfileSummary LoadProfileSummary(string profileRoot, string activeProfile)
    {
        var name = Path.GetFileName(profileRoot);
        var runtime = LoadObject(Path.Combine(profileRoot, "runtime.json"));
        var providers = runtime["Providers"] as JsonObject;
        var enabledProviders = providers is null
            ? Array.Empty<string>()
            : providers.Where(pair => pair.Value?["Enabled"]?.GetValue<bool>() == true).Select(pair => pair.Key).ToArray();
        var isDefault = string.Equals(activeProfile, name, StringComparison.OrdinalIgnoreCase) || GetBool(runtime, "IsDefault", false);

        return new RuntimeProfileSummary
        {
            Name = GetString(runtime, "ProfileName", name),
            DisplayName = GetString(runtime, "DisplayName", name),
            RuntimeMode = GetString(runtime, "Mode", "Unknown"),
            CloudEnvironment = GetString(runtime, "Cloud", "Unknown"),
            Organization = GetString(runtime, "Organization", string.Empty),
            Environment = GetString(runtime, "Environment", string.Empty),
            IsValid = File.Exists(Path.Combine(profileRoot, "runtime.json")),
            IsDefault = isDefault,
            EnabledProviders = enabledProviders,
            HealthLabel = isDefault ? "Default" : "Ready",
            BadgeText = isDefault ? "Default" : GetString(runtime, "Mode", "Profile")
        };
    }

    private static JsonObject LoadObject(string path)
    {
        if (!File.Exists(path))
        {
            return new JsonObject();
        }

        return JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject();
    }

    private static void SaveObject(string path, JsonObject value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, value.ToJsonString(JsonOptions));
    }

    private static string GetProfilesRoot(string repositoryRoot) => Path.Combine(repositoryRoot, "profiles");

    private static string GetProfileRoot(string repositoryRoot, string profileName)
    {
        var cleanName = CleanName(profileName);
        var path = Path.Combine(GetProfilesRoot(repositoryRoot), cleanName);
        if (!Directory.Exists(path))
        {
            throw new DirectoryNotFoundException($"Profile '{cleanName}' was not found.");
        }

        return path;
    }

    private static string GetActiveProfileName(string profilesRoot)
    {
        var active = LoadObject(Path.Combine(profilesRoot, "active.json"));
        return GetString(active, "ActiveProfile", string.Empty);
    }

    private static string CleanName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string((value ?? string.Empty).Trim().Where(character => !invalid.Contains(character)).ToArray());
    }

    private static JsonObject EnsureObject(JsonObject parent, string propertyName)
    {
        if (parent[propertyName] is JsonObject existing)
        {
            return existing;
        }

        var created = new JsonObject();
        parent[propertyName] = created;
        return created;
    }

    private static string GetString(JsonObject value, string propertyName, string fallback)
    {
        return value[propertyName]?.GetValue<string>() is { Length: > 0 } text ? text : fallback;
    }

    private static bool GetBool(JsonObject value, string propertyName, bool fallback)
    {
        return value[propertyName]?.GetValue<bool>() ?? fallback;
    }

    private static bool GetProviderEnabled(JsonObject runtime, string providerName)
    {
        return runtime["Providers"]?[providerName]?["Enabled"]?.GetValue<bool>() == true;
    }

    private static void SetProvider(JsonObject runtime, string providerName, bool enabled)
    {
        var providers = EnsureObject(runtime, "Providers");
        var provider = EnsureObject(providers, providerName);
        provider["Enabled"] = enabled;
        provider["Mode"] = enabled ? GetString(provider, "Mode", "Simulation") == "Disabled" ? "Simulation" : GetString(provider, "Mode", "Simulation") : "Disabled";
    }

    private static void SetProviderProperty(JsonObject runtime, string providerName, string propertyName, string value)
    {
        var providers = EnsureObject(runtime, "Providers");
        var provider = EnsureObject(providers, providerName);
        provider[propertyName] = value ?? string.Empty;
    }

    private static JsonObject ParseWizardJson(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return new JsonObject();
        }

        return JsonNode.Parse(json) as JsonObject
            ?? throw new InvalidOperationException("New User Wizard JSON must be a JSON object.");
    }

    private static string FirstNonEmpty(params string[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;

    private static string JoinNames(JsonNode? node)
    {
        return node is JsonArray array
            ? string.Join("; ", array.Select(item => item?["Name"]?.GetValue<string>()).Where(value => !string.IsNullOrWhiteSpace(value)))
            : string.Empty;
    }

    private static string JoinValues(JsonNode? node)
    {
        return node is JsonArray array
            ? string.Join("; ", array.Select(item => item?.GetValue<string>()).Where(value => !string.IsNullOrWhiteSpace(value)))
            : string.Empty;
    }

    private static JsonArray BuildNamedArray(string values)
    {
        var array = new JsonArray();
        var index = 1;
        foreach (var value in SplitValues(values))
        {
            array.Add(new JsonObject { ["Number"] = index++, ["Name"] = value });
        }

        return array;
    }

    private static JsonArray BuildStringArray(string values)
    {
        var array = new JsonArray();
        foreach (var value in SplitValues(values))
        {
            array.Add(value);
        }

        return array;
    }

    private static IEnumerable<string> SplitValues(string values)
    {
        return (values ?? string.Empty)
            .Split(new[] { ';', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(value => !string.IsNullOrWhiteSpace(value));
    }

    private static void CopyDirectory(string source, string target)
    {
        Directory.CreateDirectory(target);
        foreach (var file in Directory.EnumerateFiles(source))
        {
            File.Copy(file, Path.Combine(target, Path.GetFileName(file)), overwrite: true);
        }

        foreach (var directory in Directory.EnumerateDirectories(source))
        {
            CopyDirectory(directory, Path.Combine(target, Path.GetFileName(directory)));
        }
    }
}
