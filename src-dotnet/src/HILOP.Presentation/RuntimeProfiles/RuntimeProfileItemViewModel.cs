using HILOP.Application.RuntimeProfiles;

namespace HILOP.Presentation.RuntimeProfiles;

public sealed class RuntimeProfileItemViewModel
{
    public RuntimeProfileItemViewModel(RuntimeProfileSummary profile)
    {
        Profile = profile ?? throw new ArgumentNullException(nameof(profile));
    }

    public RuntimeProfileSummary Profile { get; }

    public string Name => Profile.Name;

    public string DisplayName => string.IsNullOrWhiteSpace(Profile.DisplayName) ? Profile.Name : Profile.DisplayName;

    public string RuntimeMode => Profile.RuntimeMode;

    public string Environment => Profile.Environment;

    public string CloudEnvironment => Profile.CloudEnvironment;

    public string Organization => Profile.Organization;

    public bool IsValid => Profile.IsValid;

    public bool IsDefault => Profile.IsDefault;

    public bool IsLastUsed => Profile.IsLastUsed;

    public string BadgeText => Profile.BadgeText;

    public string HealthLabel => Profile.HealthLabel;

    public string ProviderSummary => Profile.EnabledProviders.Count == 0
        ? "No providers"
        : string.Join(", ", Profile.EnabledProviders);

    public string ValidationMessage => IsValid
        ? "Ready"
        : FirstNonEmpty(Profile.ErrorMessage, Profile.Warnings.FirstOrDefault(), "Profile has validation issues.");

    private static string FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }
}
