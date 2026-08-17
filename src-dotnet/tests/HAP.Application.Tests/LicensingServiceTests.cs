using System.Text;
using System.Text.Json;
using HAP.Application.Licensing;
using HAP.Contracts;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Xunit;

namespace HAP.Application.Tests;

public sealed class LicensingServiceTests
{
    [Fact]
    public void Verifier_AcceptsValidSignedPayloadAndIgnoresConveniencePayload()
    {
        var fixture = LicenseFixture.Create();
        var envelope = fixture.CreateEnvelope(conveniencePayloadOrganization: "Tampered Convenience Payload");

        var result = new Ed25519LicenseEnvelopeVerifier().Verify(
            envelope,
            fixture.InstallationId,
            fixture.Options,
            CorrelationId.From("verify"),
            fixture.Now);

        Assert.True(result.Succeeded);
        Assert.Equal("Little Innovation Tech Test", result.Value!.Payload.Organization);
        Assert.Equal(LicenseState.Active, result.Value.State);
    }

    [Fact]
    public void Verifier_RejectsTamperedPayloadBytes()
    {
        var fixture = LicenseFixture.Create();
        var envelope = fixture.CreateEnvelope() with
        {
            PayloadBase64 = Base64Url.Encode(Encoding.UTF8.GetBytes("{\"schema\":\"hilop-license/v1\",\"product\":\"HILOP\"}"))
        };

        var result = new Ed25519LicenseEnvelopeVerifier().Verify(
            envelope,
            fixture.InstallationId,
            fixture.Options,
            CorrelationId.From("verify"),
            fixture.Now);

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Licensing.SignatureInvalid");
    }

    [Fact]
    public void Verifier_RejectsWrongInstallationAndUnknownKey()
    {
        var fixture = LicenseFixture.Create();
        var envelope = fixture.CreateEnvelope();

        var wrongInstall = new Ed25519LicenseEnvelopeVerifier().Verify(
            envelope,
            "hilop-other",
            fixture.Options,
            CorrelationId.From("verify"),
            fixture.Now);
        var unknownKey = new Ed25519LicenseEnvelopeVerifier().Verify(
            envelope with { KeyId = "unknown" },
            fixture.InstallationId,
            fixture.Options,
            CorrelationId.From("verify"),
            fixture.Now);

        Assert.Contains(wrongInstall.Errors, error => error.Code == "Licensing.InstallationMismatch");
        Assert.Contains(unknownKey.Errors, error => error.Code == "Licensing.SigningKeyUnknown");
    }

    [Fact]
    public void StateCalculator_HandlesTrialGraceExpiredAndRevoked()
    {
        var fixture = LicenseFixture.Create();
        var active = fixture.Payload;

        Assert.Equal(LicenseState.Trial, LicenseStateCalculator.Calculate(active with { LicenseType = "trial" }, fixture.Options, fixture.Now));
        Assert.Equal(LicenseState.GracePeriod, LicenseStateCalculator.Calculate(active with { Status = "grace_period" }, fixture.Options, fixture.Now));
        Assert.Equal(LicenseState.Expired, LicenseStateCalculator.Calculate(active with { ExpiresAt = fixture.Now.AddDays(-2), GraceUntil = fixture.Now.AddDays(-1) }, fixture.Options, fixture.Now));
        Assert.Equal(LicenseState.Revoked, LicenseStateCalculator.Calculate(active with { Status = "revoked" }, fixture.Options, fixture.Now));
    }

    [Fact]
    public void Entitlements_HandleBooleanAndNumericLimits()
    {
        var fixture = LicenseFixture.Create();
        var verified = new VerifiedLicense
        {
            Envelope = fixture.CreateEnvelope(),
            Payload = fixture.Payload,
            VerifiedPayloadBytes = Array.Empty<byte>(),
            State = LicenseState.Active,
            ValidatedAtUtc = fixture.Now
        };

        Assert.True(LicenseEntitlementEvaluator.HasBoolean(verified, HilopEntitlements.ActiveDirectory));
        Assert.False(LicenseEntitlementEvaluator.HasBoolean(verified, HilopEntitlements.ApiAccess));
        Assert.Equal(5000, LicenseEntitlementEvaluator.GetNumeric(verified, HilopEntitlements.ManagedIdentities));
        Assert.True(LicenseEntitlementEvaluator.IsWithinNumericLimit(verified, HilopEntitlements.ManagedIdentities, 5000));
        Assert.False(LicenseEntitlementEvaluator.IsWithinNumericLimit(verified, HilopEntitlements.ManagedIdentities, 5001));
    }

    [Fact]
    public async Task FileStore_PreservesInstallationIdAndProtectsCredential()
    {
        var path = Path.Combine(Path.GetTempPath(), "hilop-licensing-tests", Guid.NewGuid().ToString("N"));
        var store = new FileLocalLicenseStore(path, new TestSecretProtector());

        var first = await store.GetOrCreateInstallationIdAsync();
        var second = await store.GetOrCreateInstallationIdAsync();
        await store.SaveInstallationCredentialAsync("hinst_secret");

        Assert.Equal(first, second);
        Assert.Equal("hinst_secret", await store.LoadInstallationCredentialAsync());
        Assert.DoesNotContain("hinst_secret", await File.ReadAllTextAsync(Path.Combine(path, "installation-credential.bin")));
    }

    [Fact]
    public async Task LicensingService_RefreshKeepsValidCachedLicenseWhenServerUnavailable()
    {
        var fixture = LicenseFixture.Create();
        var store = new MemoryLicenseStore(fixture.InstallationId, "hinst_secret", fixture.CreateEnvelope());
        var service = new LicensingService(
            fixture.Options,
            store,
            new FakeLicensingApiClient(refreshResult: LicensingErrors.Failure<LicensingApiRefreshResponse>(CorrelationId.From("api"), "Network", "Offline.")));

        var result = await service.RefreshAsync(CorrelationId.From("refresh"));

        Assert.True(result.Succeeded);
        Assert.True(result.Value!.ServerUnavailable);
        Assert.Equal(LicenseState.Active, result.Value.State);
    }

    private sealed class LicenseFixture
    {
        private readonly Ed25519PrivateKeyParameters _privateKey;

        private LicenseFixture(Ed25519PrivateKeyParameters privateKey, LicensingOptions options, LicensePayload payload)
        {
            _privateKey = privateKey;
            Options = options;
            Payload = payload;
        }

        public LicensingOptions Options { get; }

        public LicensePayload Payload { get; }

        public string InstallationId => Payload.InstallationId;

        public DateTimeOffset Now { get; } = DateTimeOffset.Parse("2026-08-17T12:00:00Z");

        public static LicenseFixture Create()
        {
            var privateKey = new Ed25519PrivateKeyParameters(new byte[]
            {
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
            }, 0);
            var publicKey = privateKey.GeneratePublicKey().GetEncoded();
            var options = new LicensingOptions
            {
                TrustedPublicKeys = new Dictionary<string, string> { ["test-key"] = Base64Url.Encode(publicKey) },
                StorageDirectory = Path.Combine(Path.GetTempPath(), "hilop-licensing-tests")
            };
            var entitlements = new Dictionary<string, JsonElement>
            {
                [HilopEntitlements.ActiveDirectory] = JsonSerializer.SerializeToElement(true),
                [HilopEntitlements.ApiAccess] = JsonSerializer.SerializeToElement(false),
                [HilopEntitlements.ManagedIdentities] = JsonSerializer.SerializeToElement(5000),
                [HilopEntitlements.Administrators] = JsonSerializer.SerializeToElement(10),
                [HilopEntitlements.Directories] = JsonSerializer.SerializeToElement(5)
            };
            var payload = new LicensePayload
            {
                Schema = "hilop-license/v1",
                LicenseId = Guid.NewGuid().ToString(),
                LicenseNumber = "HIL-2026-TEST",
                InstallationId = "hilop-test-installation",
                Product = "HILOP",
                Organization = "Little Innovation Tech Test",
                LicenseType = "subscription",
                Edition = "professional",
                Status = "active",
                IssuedAt = DateTimeOffset.Parse("2026-08-17T12:00:00Z"),
                NotBefore = DateTimeOffset.Parse("2026-08-01T00:00:00Z"),
                ExpiresAt = DateTimeOffset.Parse("2027-08-01T00:00:00Z"),
                GraceUntil = DateTimeOffset.Parse("2027-08-15T00:00:00Z"),
                Entitlements = entitlements,
                Signing = new LicenseSigningInfo { Algorithm = "Ed25519", KeyId = "test-key" }
            };

            return new LicenseFixture(privateKey, options, payload);
        }

        public LicenseEnvelope CreateEnvelope(string? conveniencePayloadOrganization = null)
        {
            var payloadBytes = JsonSerializer.SerializeToUtf8Bytes(Payload, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
            });
            var signer = new Ed25519Signer();
            signer.Init(true, _privateKey);
            signer.BlockUpdate(payloadBytes, 0, payloadBytes.Length);
            var signature = signer.GenerateSignature();

            var conveniencePayload = conveniencePayloadOrganization is null
                ? JsonSerializer.SerializeToElement(Payload, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower })
                : JsonSerializer.SerializeToElement(Payload with { Organization = conveniencePayloadOrganization }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower });

            return new LicenseEnvelope
            {
                DocumentId = Guid.NewGuid().ToString(),
                Payload = conveniencePayload,
                PayloadBase64 = Base64Url.Encode(payloadBytes),
                Signature = Base64Url.Encode(signature),
                Algorithm = "Ed25519",
                KeyId = "test-key"
            };
        }
    }

    private sealed class TestSecretProtector : ISecretProtector
    {
        public string Protect(string secret) => Convert.ToBase64String(Encoding.UTF8.GetBytes(secret));

        public string Unprotect(string protectedSecret) => Encoding.UTF8.GetString(Convert.FromBase64String(protectedSecret));
    }

    private sealed class MemoryLicenseStore : ILocalLicenseStore
    {
        private readonly string _installationId;
        private string? _credential;
        private LicenseEnvelope? _envelope;

        public MemoryLicenseStore(string installationId, string? credential, LicenseEnvelope? envelope)
        {
            _installationId = installationId;
            _credential = credential;
            _envelope = envelope;
        }

        public Task<string> GetOrCreateInstallationIdAsync(CancellationToken cancellationToken = default) => Task.FromResult(_installationId);

        public Task<LicenseEnvelope?> LoadLicenseEnvelopeAsync(CancellationToken cancellationToken = default) => Task.FromResult(_envelope);

        public Task SaveLicenseEnvelopeAsync(LicenseEnvelope envelope, CancellationToken cancellationToken = default)
        {
            _envelope = envelope;
            return Task.CompletedTask;
        }

        public Task<string?> LoadInstallationCredentialAsync(CancellationToken cancellationToken = default) => Task.FromResult(_credential);

        public Task SaveInstallationCredentialAsync(string credential, CancellationToken cancellationToken = default)
        {
            _credential = credential;
            return Task.CompletedTask;
        }

        public Task ClearInstallationCredentialAsync(CancellationToken cancellationToken = default)
        {
            _credential = null;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeLicensingApiClient : ILicensingApiClient
    {
        private readonly OperationResult<LicensingApiRefreshResponse>? _refreshResult;

        public FakeLicensingApiClient(OperationResult<LicensingApiRefreshResponse>? refreshResult = null)
        {
            _refreshResult = refreshResult;
        }

        public Task<OperationResult<LicensingApiActivationResponse>> ActivateAsync(string installationId, LicenseActivationRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(LicensingErrors.Failure<LicensingApiActivationResponse>(correlationId, "NotImplemented", "Not implemented."));
        }

        public Task<OperationResult<LicensingApiRefreshResponse>> RefreshAsync(string installationCredential, LicenseRefreshRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_refreshResult ?? LicensingErrors.Failure<LicensingApiRefreshResponse>(correlationId, "NotConfigured", "No response configured."));
        }

        public Task<OperationResult<string>> DeactivateAsync(string installationCredential, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(OperationResult<string>.Success("OK", correlationId));
        }
    }
}
