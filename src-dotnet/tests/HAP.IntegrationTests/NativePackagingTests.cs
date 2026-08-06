using Xunit;

namespace HAP.IntegrationTests;

public sealed class NativePackagingTests
{
    [Fact]
    public void PublishProfile_IsFrameworkDependentAndTargetsWindowsX64()
    {
        var profile = FindRepositoryFile(Path.Combine("src", "HAP.App", "Properties", "PublishProfiles", "NativeFrameworkDependent.pubxml"));
        var text = File.ReadAllText(profile);

        Assert.Contains("<RuntimeIdentifier>win-x64</RuntimeIdentifier>", text);
        Assert.Contains("<SelfContained>false</SelfContained>", text);
        Assert.Contains("native-framework-dependent", text);
    }

    private static string FindRepositoryFile(string relativePath)
    {
        var current = AppContext.BaseDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            var candidate = Path.Combine(current, relativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            var parent = Directory.GetParent(current);
            if (parent is null)
            {
                break;
            }

            current = parent.FullName;
        }

        throw new FileNotFoundException($"Could not find {relativePath}.");
    }
}
