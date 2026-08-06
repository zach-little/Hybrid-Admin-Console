using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using HAP.Contracts;
using HAP.Extensions.Abstractions;
using HAP.Plugin.Protocol;
using Xunit;

namespace HAP.Extensions.PowerShell.Tests;

public sealed class PowerShellPluginHostProcessTests
{
    private static readonly JsonSerializerOptions ManifestJsonOptions = CreateManifestJsonOptions();

    [Fact]
    public async Task Host_HandshakesInvokesSampleModuleAndShutsDown()
    {
        var solutionRoot = FindSolutionRoot();
        var hostPath = Path.Combine(solutionRoot, "src", "HAP.PowerShellPluginHost", "bin", "Debug", "net10.0", "HAP.PowerShellPluginHost.dll");
        Assert.True(File.Exists(hostPath), $"Plugin host was not built at {hostPath}.");

        using var workspace = TempWorkspace.Create();
        var manifestPath = workspace.WriteSampleProvider();
        using var process = StartHost(hostPath);
        try
        {
            await WriteAsync(process, new HapPluginHandshakeRequest
            {
                CorrelationId = CorrelationId.From("task17-handshake"),
                ClientName = "HAP.Extensions.PowerShell.Tests",
                ProviderId = "contoso.identity",
                ManifestPath = manifestPath
            });
            var handshake = JsonSerializer.Deserialize<HapPluginHandshakeResponse>(
                await ReadLineWithTimeoutAsync(process, TimeSpan.FromSeconds(10)),
                HapPluginProtocol.JsonOptions);

            Assert.NotNull(handshake);
            Assert.True(handshake.Accepted, handshake.Message);

            await WriteAsync(process, new HapPluginOperationRequest
            {
                CorrelationId = CorrelationId.From("task17-operation"),
                ProviderId = "contoso.identity",
                CapabilityId = "identity.user.read",
                Operation = "GetSampleUser",
                Payload = JsonSerializer.SerializeToElement(new { UserPrincipalName = "ada@example.test" }, HapPluginProtocol.JsonOptions)
            });
            var response = JsonSerializer.Deserialize<HapPluginOperationResponse>(
                await ReadLineWithTimeoutAsync(process, TimeSpan.FromSeconds(30)),
                HapPluginProtocol.JsonOptions);

            Assert.NotNull(response);
            Assert.True(response.Succeeded, string.Join("; ", response.Errors.Select(error => error.Message)));
            Assert.Equal("ada@example.test", response.Data?.GetProperty("userPrincipalName").GetString());

            await WriteAsync(process, new HapPluginShutdownRequest { CorrelationId = CorrelationId.From("task17-shutdown") });
            var shutdown = JsonSerializer.Deserialize<HapPluginAcknowledgement>(
                await ReadLineWithTimeoutAsync(process, TimeSpan.FromSeconds(10)),
                HapPluginProtocol.JsonOptions);
            Assert.NotNull(shutdown);
            Assert.True(shutdown.Accepted);
        }
        finally
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
    }

    private static Process StartHost(string hostPath)
    {
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{hostPath}\"",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });
        Assert.NotNull(process);
        return process;
    }

    private static async Task WriteAsync<T>(Process process, T message)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(message, HapPluginProtocol.JsonOptions));
        await process.StandardInput.FlushAsync();
    }

    private static async Task<string> ReadLineWithTimeoutAsync(Process process, TimeSpan timeout)
    {
        var readTask = process.StandardOutput.ReadLineAsync();
        var completed = await Task.WhenAny(readTask, Task.Delay(timeout));
        if (completed != readTask)
        {
            var stderr = await process.StandardError.ReadToEndAsync();
            throw new TimeoutException($"Plugin host did not respond within {timeout}. stderr: {stderr}");
        }

        return await readTask ?? throw new InvalidOperationException("Plugin host closed stdout before responding.");
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "HAP.sln")))
        {
            directory = directory.Parent;
        }

        Assert.NotNull(directory);
        return directory.FullName;
    }

    private static JsonSerializerOptions CreateManifestJsonOptions()
    {
        var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }

    private sealed class TempWorkspace : IDisposable
    {
        private TempWorkspace(string root)
        {
            Root = root;
        }

        private string Root { get; }

        public static TempWorkspace Create()
        {
            var root = Path.Combine(Path.GetTempPath(), "hap-plugin-host-tests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return new TempWorkspace(root);
        }

        public string WriteSampleProvider()
        {
            var modulePath = Path.Combine(Root, "Contoso.Identity.Provider.psm1");
            File.WriteAllText(modulePath, """
function Invoke-HapProviderOperation {
    param(
        [string]$ProviderId,
        [string]$CapabilityId,
        [string]$Operation,
        [string]$PayloadJson
    )

    $payload = $PayloadJson | ConvertFrom-Json
    [pscustomobject]@{
        succeeded = $true
        data = [pscustomobject]@{
            userPrincipalName = [string]$payload.UserPrincipalName
            providerId = $ProviderId
            capabilityId = $CapabilityId
            operation = $Operation
        }
        warnings = @()
        errors = @()
    }
}
Export-ModuleMember -Function Invoke-HapProviderOperation
""");

            var manifest = new HapExtensionManifest
            {
                ManifestVersion = "1.0",
                ProviderId = "contoso.identity",
                DisplayName = "Contoso Identity",
                Publisher = "Contoso",
                ProviderVersion = "1.0.0",
                ApiVersion = "1.0",
                Implementation = HapProviderImplementationKind.PowerShell,
                EntryPoint = new HapExtensionEntryPoint
                {
                    ModulePath = ".\\Contoso.Identity.Provider.psm1",
                    RequiredPowerShellEdition = "PowerShell7",
                    MinimumPowerShellVersion = "7.4"
                },
                Capabilities = new[]
                {
                    new HapExtensionCapabilityDeclaration
                    {
                        Id = "identity.user.read",
                        Operations = new[] { "TestConnection", "GetSampleUser" }
                    }
                }
            };
            var manifestPath = Path.Combine(Root, "manifest.json");
            File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, ManifestJsonOptions));
            return manifestPath;
        }

        public void Dispose()
        {
            if (Directory.Exists(Root))
            {
                Directory.Delete(Root, recursive: true);
            }
        }
    }
}
