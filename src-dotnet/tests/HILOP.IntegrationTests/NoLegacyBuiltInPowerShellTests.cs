using Xunit;

namespace HILOP.IntegrationTests;

public sealed class NoLegacyBuiltInPowerShellTests
{
    [Fact]
    public void ProductionSource_DoesNotContainTemporaryLegacyWorkerOrBridge()
    {
        var sourceRoot = FindSourceRoot();
        var productionFiles = Directory.EnumerateFiles(sourceRoot, "*.*", SearchOption.AllDirectories)
            .Where(file => file.EndsWith(".cs", StringComparison.OrdinalIgnoreCase) ||
                           file.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) ||
                           file.EndsWith(".xaml", StringComparison.OrdinalIgnoreCase))
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}HILOP.PowerShellPluginHost{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        var forbidden = new[]
        {
            "HILOP.Providers.LegacyPowerShell",
            "HILOP.LegacyWorker.Protocol",
            "HILOP.LegacyPowerShellWorker",
            "HILOP.LegacyBridge.psm1",
            "System.Management.Automation",
            "powershell.exe",
            "pwsh.exe"
        };

        var approvedDirectPowerShellLaunchFiles = new[]
        {
            "NativeSimulationView.xaml.cs",
            "ExchangeOnlineProvider.cs",
            "ExchangeOnPremisesProvider.cs"
        };

        var hits = productionFiles
            .SelectMany(file =>
            {
                var text = File.ReadAllText(file);
                return forbidden
                    .Where(term => text.Contains(term, StringComparison.OrdinalIgnoreCase) &&
                                   !IsApprovedDirectPowerShellLaunch(file, term, approvedDirectPowerShellLaunchFiles))
                    .Select(term => $"{file}: {term}");
            })
            .ToArray();

        Assert.Empty(hits);
    }

    private static bool IsApprovedDirectPowerShellLaunch(string file, string term, IReadOnlyList<string> approvedFiles)
    {
        return (term.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase) ||
                term.Equals("pwsh.exe", StringComparison.OrdinalIgnoreCase)) &&
               approvedFiles.Any(approved => file.EndsWith(approved, StringComparison.OrdinalIgnoreCase));
    }

    private static string FindSourceRoot()
    {
        var current = AppContext.BaseDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            var candidate = Path.Combine(current, "src");
            if (Directory.Exists(candidate) &&
                Directory.Exists(Path.Combine(candidate, "HILOP.Application")))
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

        throw new DirectoryNotFoundException("Could not locate src-dotnet/src.");
    }
}
