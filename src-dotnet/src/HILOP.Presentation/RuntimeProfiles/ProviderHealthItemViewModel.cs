using HILOP.Application.RuntimeProfiles;

namespace HILOP.Presentation.RuntimeProfiles;

public sealed class ProviderHealthItemViewModel
{
    public ProviderHealthItemViewModel(ProviderHealthSummary health)
    {
        Health = health ?? throw new ArgumentNullException(nameof(health));
    }

    public ProviderHealthSummary Health { get; }

    public string Name => Health.Name;

    public string Mode => Health.Mode;

    public string Status => Health.Status;

    public string Message => string.IsNullOrWhiteSpace(Health.Message) ? Health.LastError : Health.Message;

    public bool Enabled => Health.Enabled;

    public bool Required => Health.Required;

    public bool Connected => Health.Connected;
}
