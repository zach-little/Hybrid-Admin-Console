using System.Text.Json;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public static class LegacyWorkerResponseMapper
{
    public static OperationResult<T> ToOperationResult<T>(LegacyWorkerResponse response)
    {
        if (!response.Succeeded)
        {
            return OperationResult<T>.Failure(
                response.CorrelationId,
                response.Errors.Count == 0
                    ? new[] { OperationError.Create("LegacyWorker.EmptyFailure", "Legacy worker returned failure without structured errors.") }
                    : response.Errors,
                response.Warnings,
                response.Status);
        }

        try
        {
            if (!response.Data.HasValue)
            {
                return OperationResult<T>.Failure(
                    response.CorrelationId,
                    new[] { OperationError.Create("LegacyWorker.EmptyData", "Legacy worker returned success without data.") },
                    response.Warnings,
                    response.Status);
            }

            var value = response.Data.Value.Deserialize<T>(LegacyWorkerProtocol.JsonOptions);
            if (value is null)
            {
                return OperationResult<T>.Failure(
                    response.CorrelationId,
                    new[] { OperationError.Create("LegacyWorker.EmptyData", "Legacy worker returned success without data.") },
                    response.Warnings,
                    response.Status);
            }

            return OperationResult<T>.Success(value, response.CorrelationId, response.Warnings, response.Status);
        }
        catch (JsonException ex)
        {
            return OperationResult<T>.Failure(
                response.CorrelationId,
                new[] { OperationError.Create("LegacyWorker.DataInvalid", "Legacy worker returned data that could not be mapped.", diagnosticDetail: ex.Message) },
                response.Warnings,
                response.Status);
        }
    }
}
