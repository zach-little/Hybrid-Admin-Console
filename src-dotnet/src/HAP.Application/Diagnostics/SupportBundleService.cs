using System.Text.Json;
using HAP.Contracts;

namespace HAP.Application.Diagnostics;

public sealed class SupportBundleService
{
    private static readonly string[] SensitiveFragments =
    {
        "secret",
        "password",
        "token",
        "thumbprint",
        "certificate",
        "clientsecret"
    };

    public OperationResult<string> CreateJson(
        SupportBundleRequest request,
        CorrelationId correlationId)
    {
        var bundle = new SupportBundle
        {
            ProductVersion = request.ProductVersion,
            CreatedUtc = DateTimeOffset.UtcNow,
            ConfigurationValues = request.ConfigurationValues
                .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(pair => pair.Key, pair => Redact(pair.Key, pair.Value)),
            RecentEvents = request.RecentEvents.Select(RedactFreeText).ToArray(),
            CapabilityDispositions = request.CapabilityDispositions.ToArray()
        };

        return OperationResult<string>.Success(
            JsonSerializer.Serialize(bundle, new JsonSerializerOptions { WriteIndented = true }),
            correlationId,
            status: "Created");
    }

    private static string Redact(string key, string value)
    {
        return SensitiveFragments.Any(fragment => key.Contains(fragment, StringComparison.OrdinalIgnoreCase))
            ? "[REDACTED]"
            : value;
    }

    private static string RedactFreeText(string value)
    {
        var redacted = value;
        foreach (var fragment in SensitiveFragments)
        {
            redacted = System.Text.RegularExpressions.Regex.Replace(
                redacted,
                $"{fragment}\\s*[:=]\\s*\\S+",
                $"{fragment}=[REDACTED]",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        }

        return redacted;
    }
}
