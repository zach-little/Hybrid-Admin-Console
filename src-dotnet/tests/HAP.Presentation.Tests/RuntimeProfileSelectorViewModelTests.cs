using HAP.Application.RuntimeProfiles;
using HAP.Contracts;
using HAP.Presentation.RuntimeProfiles;
using Xunit;

namespace HAP.Presentation.Tests;

public sealed class RuntimeProfileSelectorViewModelTests
{
    [Fact]
    public async Task LoadAsync_PopulatesProfilesAndSelectsDefault()
    {
        var profiles = new[]
        {
            new RuntimeProfileSummary { Name = "Simulation", DisplayName = "Simulation", IsValid = true },
            new RuntimeProfileSummary { Name = "Live", DisplayName = "Live", IsValid = true, IsDefault = true }
        };
        var viewModel = new RuntimeProfileSelectorViewModel(new StubCatalogService(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Success(
            profiles,
            CorrelationId.From("presentation-success"))));

        await viewModel.LoadAsync(@"D:\Atlas");

        Assert.Equal(2, viewModel.Profiles.Count);
        Assert.Equal("Live", viewModel.SelectedProfile?.Name);
        Assert.True(viewModel.IsSelectionValid);
        Assert.False(viewModel.HasError);
        Assert.Contains("Loaded 2", viewModel.ProgressMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task LoadAsync_MapsCatalogFailuresToErrorState()
    {
        var viewModel = new RuntimeProfileSelectorViewModel(new StubCatalogService(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Failure(
            CorrelationId.From("presentation-failure"),
            new[] { OperationError.Create("Catalog.Failed", "Profile catalog failed.") })));

        await viewModel.LoadAsync(@"D:\Atlas");

        Assert.Empty(viewModel.Profiles);
        Assert.Null(viewModel.SelectedProfile);
        Assert.True(viewModel.HasError);
        Assert.Contains("Profile catalog failed.", viewModel.ErrorMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StartSelectedRuntimeAsync_PopulatesProviderHealthAndShutdownClearsIt()
    {
        var profiles = new[]
        {
            new RuntimeProfileSummary { Name = "Simulation", DisplayName = "Simulation", IsValid = true, IsDefault = true }
        };
        var session = new RuntimeSessionSummary
        {
            ProfileName = "Simulation",
            RuntimeMode = "Simulation",
            OverallStatus = "Warning",
            DurationMs = 42,
            ProviderHealth = new[]
            {
                new ProviderHealthSummary { Name = "DirectorySimulator", Mode = "Simulation", Enabled = true, Connected = true, Status = "Connected" }
            }
        };
        var viewModel = new RuntimeProfileSelectorViewModel(
            new StubCatalogService(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Success(profiles, CorrelationId.From("catalog"))),
            new StubRuntimeSessionService(OperationResult<RuntimeSessionSummary>.Success(session, CorrelationId.From("runtime"))));

        await viewModel.LoadAsync(@"D:\Atlas");
        await viewModel.StartSelectedRuntimeAsync(@"D:\Atlas");

        Assert.True(viewModel.IsRuntimeStarted);
        Assert.Equal("Warning", viewModel.RuntimeStatus);
        Assert.Single(viewModel.ProviderHealth);
        Assert.Equal("DirectorySimulator", viewModel.ProviderHealth[0].Name);

        await viewModel.ShutdownRuntimeAsync(@"D:\Atlas");

        Assert.False(viewModel.IsRuntimeStarted);
        Assert.Empty(viewModel.ProviderHealth);
        Assert.Equal("Stopped", viewModel.RuntimeStatus);
    }

    private sealed class StubCatalogService : IRuntimeProfileCatalogService
    {
        private readonly OperationResult<IReadOnlyList<RuntimeProfileSummary>> _result;

        public StubCatalogService(OperationResult<IReadOnlyList<RuntimeProfileSummary>> result)
        {
            _result = result;
        }

        public Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
            string repositoryRoot,
            CorrelationId correlationId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_result);
        }
    }

    private sealed class StubRuntimeSessionService : IRuntimeSessionService
    {
        private readonly OperationResult<RuntimeSessionSummary> _startResult;

        public StubRuntimeSessionService(OperationResult<RuntimeSessionSummary> startResult)
        {
            _startResult = startResult;
        }

        public Task<OperationResult<RuntimeSessionSummary>> StartAsync(
            string repositoryRoot,
            string profileName,
            CorrelationId correlationId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_startResult);
        }

        public Task<OperationResult<bool>> ShutdownAsync(
            string repositoryRoot,
            CorrelationId correlationId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(OperationResult<bool>.Success(true, correlationId));
        }
    }
}
