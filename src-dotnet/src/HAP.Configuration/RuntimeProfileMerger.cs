namespace HAP.Configuration;

public static class RuntimeProfileMerger
{
    public static RuntimeProfile Merge(RuntimeProfile baseline, RuntimeProfile overlay)
    {
        var providers = baseline.Providers
            .Concat(overlay.Providers)
            .GroupBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase);

        var extensions = baseline.Extensions
            .Concat(overlay.Extensions)
            .GroupBy(item => item.ProviderInstanceId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .OrderBy(item => item.ProviderInstanceId, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return baseline with
        {
            ProfileName = UseOverlay(overlay.ProfileName, baseline.ProfileName),
            DisplayName = UseOverlay(overlay.DisplayName, baseline.DisplayName),
            Organization = UseOverlay(overlay.Organization, baseline.Organization),
            ProfileRoot = UseOverlay(overlay.ProfileRoot, baseline.ProfileRoot),
            ProfileLayout = UseOverlay(overlay.ProfileLayout, baseline.ProfileLayout),
            Mode = overlay.Mode,
            Cloud = UseOverlay(overlay.Cloud, baseline.Cloud),
            Environment = UseOverlay(overlay.Environment, baseline.Environment),
            TenantId = UseOverlay(overlay.TenantId, baseline.TenantId),
            SimulationMode = overlay.SimulationMode,
            IsDefault = overlay.IsDefault,
            Authentication = MergeAuthentication(baseline.Authentication, overlay.Authentication),
            Providers = providers,
            Extensions = extensions
        };
    }

    private static RuntimeAuthenticationSettings MergeAuthentication(
        RuntimeAuthenticationSettings baseline,
        RuntimeAuthenticationSettings overlay)
    {
        return baseline with
        {
            Cloud = UseOverlay(overlay.Cloud, baseline.Cloud),
            AppOnly = baseline.AppOnly with
            {
                Enabled = overlay.AppOnly.Enabled,
                TenantId = UseOverlay(overlay.AppOnly.TenantId, baseline.AppOnly.TenantId),
                TenantDomain = UseOverlay(overlay.AppOnly.TenantDomain, baseline.AppOnly.TenantDomain),
                ClientId = UseOverlay(overlay.AppOnly.ClientId, baseline.AppOnly.ClientId),
                CredentialMode = UseOverlay(overlay.AppOnly.CredentialMode, baseline.AppOnly.CredentialMode),
                CertificateThumbprint = UseOverlay(overlay.AppOnly.CertificateThumbprint, baseline.AppOnly.CertificateThumbprint),
                CertificatePath = UseOverlay(overlay.AppOnly.CertificatePath, baseline.AppOnly.CertificatePath),
                SecretReference = UseOverlay(overlay.AppOnly.SecretReference, baseline.AppOnly.SecretReference)
            },
            Delegated = baseline.Delegated with
            {
                Enabled = overlay.Delegated.Enabled,
                PromptWhenRequired = overlay.Delegated.PromptWhenRequired,
                ClientId = UseOverlay(overlay.Delegated.ClientId, baseline.Delegated.ClientId)
            }
        };
    }

    private static string UseOverlay(string overlay, string baseline)
    {
        return string.IsNullOrWhiteSpace(overlay) ? baseline : overlay;
    }
}
