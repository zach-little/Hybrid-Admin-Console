using System.Text.Json;
using HILOP.Contracts;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace HILOP.Application.Licensing;

public interface ILicenseEnvelopeVerifier
{
    OperationResult<VerifiedLicense> Verify(
        LicenseEnvelope envelope,
        string expectedInstallationId,
        LicensingOptions options,
        CorrelationId correlationId,
        DateTimeOffset? nowUtc = null);
}

public sealed class Ed25519LicenseEnvelopeVerifier : ILicenseEnvelopeVerifier
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Disallow
    };

    public OperationResult<VerifiedLicense> Verify(
        LicenseEnvelope envelope,
        string expectedInstallationId,
        LicensingOptions options,
        CorrelationId correlationId,
        DateTimeOffset? nowUtc = null)
    {
        var errors = ValidateEnvelopeShape(envelope, options).ToList();
        if (errors.Count > 0)
        {
            return Failure(correlationId, errors);
        }

        byte[] payloadBytes;
        byte[] signatureBytes;
        byte[] publicKeyBytes;
        try
        {
            payloadBytes = Base64Url.Decode(envelope.PayloadBase64);
            signatureBytes = Base64Url.Decode(envelope.Signature);
            publicKeyBytes = Base64Url.Decode(options.TrustedPublicKeys[envelope.KeyId]);
        }
        catch (FormatException ex)
        {
            return Failure(correlationId, "Licensing.Base64Malformed", "The license envelope contains malformed base64url data.", ex.Message);
        }

        if (publicKeyBytes.Length != 32)
        {
            return Failure(correlationId, "Licensing.PublicKeyInvalid", "The trusted signing key is not a raw Ed25519 public key.");
        }

        if (!VerifySignature(publicKeyBytes, payloadBytes, signatureBytes))
        {
            return Failure(correlationId, "Licensing.SignatureInvalid", "The license signature is invalid.");
        }

        LicensePayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<LicensePayload>(payloadBytes, JsonOptions);
        }
        catch (JsonException ex)
        {
            return Failure(correlationId, "Licensing.PayloadMalformed", "The verified license payload is not valid JSON.", ex.Message);
        }

        if (payload is null)
        {
            return Failure(correlationId, "Licensing.PayloadEmpty", "The verified license payload is empty.");
        }

        errors.AddRange(ValidatePayload(payload, envelope, expectedInstallationId, options));
        if (errors.Count > 0)
        {
            return Failure(correlationId, errors);
        }

        var state = LicenseStateCalculator.Calculate(payload, options, nowUtc ?? DateTimeOffset.UtcNow);
        return OperationResult<VerifiedLicense>.Success(
            new VerifiedLicense
            {
                Envelope = envelope,
                Payload = payload,
                VerifiedPayloadBytes = payloadBytes,
                State = state,
                ValidatedAtUtc = nowUtc ?? DateTimeOffset.UtcNow
            },
            correlationId,
            status: state.ToString());
    }

    private static IEnumerable<OperationError> ValidateEnvelopeShape(LicenseEnvelope envelope, LicensingOptions options)
    {
        if (!string.Equals(envelope.Algorithm, "Ed25519", StringComparison.Ordinal))
        {
            yield return OperationError.Create("Licensing.AlgorithmUnsupported", "Only Ed25519 license signatures are supported.");
        }

        if (string.IsNullOrWhiteSpace(envelope.KeyId) || !options.TrustedPublicKeys.ContainsKey(envelope.KeyId))
        {
            yield return OperationError.Create("Licensing.SigningKeyUnknown", "The license was signed with an unknown key ID.");
        }

        if (string.IsNullOrWhiteSpace(envelope.PayloadBase64))
        {
            yield return OperationError.Create("Licensing.PayloadMissing", "The license envelope is missing payload_b64.");
        }

        if (string.IsNullOrWhiteSpace(envelope.Signature))
        {
            yield return OperationError.Create("Licensing.SignatureMissing", "The license envelope is missing a signature.");
        }
    }

    private static IEnumerable<OperationError> ValidatePayload(
        LicensePayload payload,
        LicenseEnvelope envelope,
        string expectedInstallationId,
        LicensingOptions options)
    {
        if (!string.Equals(payload.Schema, options.LicenseSchema, StringComparison.Ordinal))
        {
            yield return OperationError.Create("Licensing.SchemaUnsupported", "The license schema is not supported.");
        }

        if (!string.Equals(payload.Product, options.ProductCode, StringComparison.OrdinalIgnoreCase))
        {
            yield return OperationError.Create("Licensing.ProductMismatch", "The license is not valid for HILOP.");
        }

        if (!string.Equals(payload.InstallationId, expectedInstallationId, StringComparison.Ordinal))
        {
            yield return OperationError.Create("Licensing.InstallationMismatch", "The license is not valid for this installation.");
        }

        if (!string.Equals(payload.Signing.Algorithm, envelope.Algorithm, StringComparison.Ordinal) ||
            !string.Equals(payload.Signing.KeyId, envelope.KeyId, StringComparison.Ordinal))
        {
            yield return OperationError.Create("Licensing.SigningMetadataMismatch", "The license signing metadata does not match the envelope.");
        }

        if (string.IsNullOrWhiteSpace(payload.LicenseId) ||
            string.IsNullOrWhiteSpace(payload.LicenseNumber) ||
            string.IsNullOrWhiteSpace(payload.Status))
        {
            yield return OperationError.Create("Licensing.RequiredFieldsMissing", "The verified license payload is missing required identifiers.");
        }
    }

    private static bool VerifySignature(byte[] publicKeyBytes, byte[] payloadBytes, byte[] signatureBytes)
    {
        try
        {
            var signer = new Ed25519Signer();
            signer.Init(false, new Ed25519PublicKeyParameters(publicKeyBytes, 0));
            signer.BlockUpdate(payloadBytes, 0, payloadBytes.Length);
            return signer.VerifySignature(signatureBytes);
        }
        catch
        {
            return false;
        }
    }

    private static OperationResult<VerifiedLicense> Failure(CorrelationId correlationId, string code, string message, string? detail = null)
    {
        return Failure(correlationId, new[] { OperationError.Create(code, message, diagnosticDetail: detail) });
    }

    private static OperationResult<VerifiedLicense> Failure(CorrelationId correlationId, IEnumerable<OperationError> errors)
    {
        return OperationResult<VerifiedLicense>.Failure(correlationId, errors, status: LicenseState.Invalid.ToString());
    }
}

public static class LicenseStateCalculator
{
    public static LicenseState Calculate(LicensePayload payload, LicensingOptions options, DateTimeOffset nowUtc)
    {
        var status = payload.Status.Trim().ToLowerInvariant();
        if (status is "revoked" or "suspended")
        {
            return LicenseState.Revoked;
        }

        if (status is "expired")
        {
            return LicenseState.Expired;
        }

        if (payload.NotBefore is { } notBefore && nowUtc < notBefore)
        {
            return LicenseState.Invalid;
        }

        if (payload.GraceUntil is { } graceUntil &&
            payload.ExpiresAt is { } expiresAt &&
            nowUtc > expiresAt &&
            nowUtc <= graceUntil)
        {
            return LicenseState.GracePeriod;
        }

        if (payload.ExpiresAt is { } expires && nowUtc > expires)
        {
            return LicenseState.Expired;
        }

        if (status is "grace_period")
        {
            return LicenseState.GracePeriod;
        }

        if (string.Equals(payload.LicenseType, "trial", StringComparison.OrdinalIgnoreCase))
        {
            return LicenseState.Trial;
        }

        if (payload.ExpiresAt is { } expiring && expiring - nowUtc <= options.ExpiringSoonWindow)
        {
            return LicenseState.ExpiringSoon;
        }

        return status is "active" ? LicenseState.Active : LicenseState.Invalid;
    }
}

public static class LicenseEntitlementEvaluator
{
    public static bool HasBoolean(VerifiedLicense? license, string entitlementKey)
    {
        return license?.IsOperational == true &&
            TryGet(license.Payload, entitlementKey, out var value) &&
            value.ValueKind == JsonValueKind.True;
    }

    public static int? GetNumeric(VerifiedLicense? license, string entitlementKey)
    {
        if (license?.IsOperational != true || !TryGet(license.Payload, entitlementKey, out var value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number) ? number : null;
    }

    public static bool IsWithinNumericLimit(VerifiedLicense? license, string entitlementKey, int currentUsage)
    {
        var limit = GetNumeric(license, entitlementKey);
        return limit.HasValue && currentUsage <= limit.Value;
    }

    private static bool TryGet(LicensePayload payload, string entitlementKey, out JsonElement value)
    {
        foreach (var pair in payload.Entitlements)
        {
            if (string.Equals(pair.Key, entitlementKey, StringComparison.OrdinalIgnoreCase))
            {
                value = pair.Value;
                return true;
            }
        }

        value = default;
        return false;
    }
}

public static class Base64Url
{
    public static byte[] Decode(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new FormatException("Base64url value cannot be empty.");
        }

        var normalized = value.Trim().Replace('-', '+').Replace('_', '/');
        normalized = normalized.PadRight(normalized.Length + ((4 - normalized.Length % 4) % 4), '=');
        return Convert.FromBase64String(normalized);
    }

    public static string Encode(byte[] value)
    {
        return Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}
