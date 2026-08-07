namespace HAP.Application.RuntimeProfiles;

public sealed record RuntimeProfileConfigurationDraft
{
    public string ProfileName { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Organization { get; init; } = string.Empty;

    public string Environment { get; init; } = string.Empty;

    public string RuntimeMode { get; init; } = string.Empty;

    public string CloudEnvironment { get; init; } = string.Empty;

    public string TenantId { get; init; } = string.Empty;

    public bool AppOnlyEnabled { get; init; }

    public string AppOnlyTenantDomain { get; init; } = string.Empty;

    public string AppOnlyClientId { get; init; } = string.Empty;

    public string AppOnlyCredentialMode { get; init; } = string.Empty;

    public string CertificateThumbprint { get; init; } = string.Empty;

    public string CertificatePath { get; init; } = string.Empty;

    public string SecretReference { get; init; } = string.Empty;

    public bool DelegatedEnabled { get; init; }

    public bool DelegatedPromptWhenRequired { get; init; }

    public string ActiveDirectoryDomain { get; init; } = string.Empty;

    public string ActiveDirectoryServer { get; init; } = string.Empty;

    public string ActiveDirectoryDefaultUserContainer { get; init; } = string.Empty;

    public string ExchangeOnPremisesServer { get; init; } = string.Empty;

    public string ExchangeOnPremisesConnectionUri { get; init; } = string.Empty;

    public string ExchangeOnPremisesAuthentication { get; init; } = string.Empty;

    public string HybridConnectionServer { get; init; } = string.Empty;

    public string NotificationRecipient { get; init; } = string.Empty;

    public string NotificationSender { get; init; } = string.Empty;

    public string Departments { get; init; } = string.Empty;

    public string Locations { get; init; } = string.Empty;

    public string JobTitles { get; init; } = string.Empty;

    public string Portfolios { get; init; } = string.Empty;

    public string DefaultLicenseSet { get; init; } = string.Empty;

    public string NewUserWizardJson { get; init; } = string.Empty;

    public bool DirectorySimulatorEnabled { get; init; }

    public bool ActiveDirectoryEnabled { get; init; }

    public bool MicrosoftGraphEnabled { get; init; }

    public bool ExchangeOnlineEnabled { get; init; }

    public bool ExchangeOnPremisesEnabled { get; init; }

    public bool CreateMailboxByDefault { get; init; }

    public bool SendOnboardingNotification { get; init; }

    public bool RequireManagerValidation { get; init; }

    public string WindowTitle { get; init; } = string.Empty;

    public string ThemeName { get; init; } = string.Empty;

    public string PrimaryColor { get; init; } = string.Empty;

    public string AccentColor { get; init; } = string.Empty;

    public string BackgroundColor { get; init; } = string.Empty;

    public string SurfaceColor { get; init; } = string.Empty;

    public string ForegroundColor { get; init; } = string.Empty;

    public string MutedTextColor { get; init; } = string.Empty;

    public string LogoPath { get; init; } = string.Empty;

    public string IconPath { get; init; } = string.Empty;

    public string SplashPath { get; init; } = string.Empty;

    public string ThemeMode { get; init; } = string.Empty;
}
