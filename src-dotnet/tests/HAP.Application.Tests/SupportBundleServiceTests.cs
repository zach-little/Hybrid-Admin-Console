using HAP.Application.Diagnostics;
using HAP.Contracts;
using Xunit;

namespace HAP.Application.Tests;

public sealed class SupportBundleServiceTests
{
    [Fact]
    public void CreateJson_RedactsSensitiveConfigurationAndEvents()
    {
        var service = new SupportBundleService();

        var result = service.CreateJson(
            new SupportBundleRequest
            {
                ProductVersion = "1.0.0-test",
                ConfigurationValues = new Dictionary<string, string>
                {
                    ["TenantId"] = "tenant-1",
                    ["ClientSecret"] = "super-secret",
                    ["CertificateThumbprint"] = "abc123"
                },
                RecentEvents = new[] { "Token=abc123 was refreshed", "Profile loaded" },
                CapabilityDispositions = new[] { "ExchangeOnline.MailboxForwarding=Deferred" }
            },
            CorrelationId.From("support-bundle"));

        Assert.True(result.Succeeded);
        Assert.Contains("tenant-1", result.Value);
        Assert.DoesNotContain("super-secret", result.Value);
        Assert.DoesNotContain("abc123", result.Value);
        Assert.Contains("[REDACTED]", result.Value);
    }
}
