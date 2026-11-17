import Foundation
import OmiWAL

// MARK: - Insight Models
/// Empty body for POST requests with no body
struct EmptyBody: Encodable {}

// MARK: - Local files sync

extension APIClient {

  // MARK: - Sync local files (WAL upload)

  /// Upload-only POST to `/v2/sync-local-files`. Mirrors Flutter `uploadLocalFilesV2`.
  func uploadLocalFilesV2(
    fileURLs: [URL],
    conversationId: String? = nil
  ) async throws -> UploadLocalFilesResult {
    guard await AccountCutoverOfflineUploadAdmission.allowsUploadOffMainActor() else {
      throw APIError.accountCutoverOfflineQueueBlocked
    }
    guard var components = URLComponents(string: baseURL + "v2/sync-local-files") else {
      throw APIError.invalidResponse
    }
    if let conversationId, !conversationId.isEmpty {
      components.queryItems = [URLQueryItem(name: "conversation_id", value: conversationId)]
    }
    guard let url = components.url else {
      throw APIError.syncUploadRejected(reason: "Invalid sync-local-files URL")
    }
    let request = try await buildSyncLocalFilesMultipartRequest(url: url, fileURLs: fileURLs)
    return try await performSyncLocalFilesUpload(request)
  }

  /// Single GET of a sync job's status — no polling loop.
  func fetchSyncJobStatus(jobId: String) async -> SyncJobFetch {
    let endpoint = "v2/sync-local-files/\(jobId)"
    guard let url = URL(string: baseURL + endpoint) else {
      return SyncJobFetch(outcome: .transient)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    // Build the auth header explicitly. If token minting throws (e.g. an account
    // transition races the reconciler, or the Keychain is locked right after
    // login), do NOT fall through and send an UNAUTHENTICATED GET — that returns
    // 401, was misread as `.transient`, and parked the WAL in a forever-retry.
    // Surface `.unauthorized` so the reconciler reverts the WAL for re-upload via
    // the authenticated upload path, which owns the forced refresh. Per
    // INV-AUTH-1 the background poll is session-preserving: it never invalidates
    // the Firebase session itself.
    do {
      request.allHTTPHeaderFields = try await buildHeaders(requireAuth: true)
    } catch {
      return SyncJobFetch(outcome: .unauthorized)
    }

    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse
    else {
      return SyncJobFetch(outcome: .transient)
    }

    // 401/403/404 are durable for this fetch: re-polling won't resolve them, so
    // the reconciler reverts the WAL to `.miss` for re-upload (the backend
    // dedupes by conversation/timestamp) instead of polling forever.
    switch SyncJobFetchOutcome.forStatusCode(http.statusCode) {
    case .ok:
      do {
        let status = try decoder.decode(SyncJobStatusResponse.self, from: data)
        return SyncJobFetch(outcome: .ok, status: status)
      } catch {
        return SyncJobFetch(outcome: .transient)
      }
    case let outcome:
      return SyncJobFetch(outcome: outcome)
    }
  }

  private func buildSyncLocalFilesMultipartRequest(url: URL, fileURLs: [URL]) async throws -> URLRequest {
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    var headers = try await buildHeaders(requireAuth: true)
    headers.removeValue(forKey: "Content-Type")
    request.allHTTPHeaderFields = headers
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    let lineBreak = "\r\n"
    for fileURL in fileURLs {
      // Legacy desktop WAL files on disk may still use byte-length `_fsN` tokens;
      // normalize at upload time so the backend Opus decoder gets sample-frame size.
      let fileName = WALSyncUploadFileName.normalizedForUpload(fileURL.lastPathComponent)
      let fileData = try Data(contentsOf: fileURL)
      body.append(Data("--\(boundary)\(lineBreak)".utf8))
      body.append(
        Data(
          "Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\(lineBreak)"
            .utf8))
      body.append(Data("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)".utf8))
      body.append(fileData)
      body.append(Data(lineBreak.utf8))
    }
    body.append(Data("--\(boundary)--\(lineBreak)".utf8))
    request.httpBody = body
    return request
  }

  private func performSyncLocalFilesUpload(_ request: URLRequest, retriedAuth: Bool = false) async throws
    -> UploadLocalFilesResult
  {
    let (data, http) = try await performAuthenticatedData(for: request, retriedAuth: retriedAuth)

    if http.statusCode == 200 {
      let completed = try decoder.decode(SyncLocalFilesResultResponse.self, from: data)
      // A legacy synchronous path can return 200 even when one or more
      // segments failed. Treat it as a retryable upload failure so WALService
      // preserves the local recording instead of acknowledging it as synced.
      if completed.failedSegments > 0 {
        throw APIError.syncUploadRejected(reason: "Transcription incomplete; retrying retained audio")
      }
      return .done(completed)
    }
    if http.statusCode == 202 {
      let start = try decoder.decode(SyncJobStartResponse.self, from: data)
      guard !start.jobId.isEmpty else {
        throw APIError.syncUploadRejected(reason: "Upload accepted but no job id returned")
      }
      return .queued(jobId: start.jobId)
    }
    if http.statusCode == 429 {
      let retryAfter = Self.parseRetryAfterSeconds(from: http)
      throw APIError.syncRateLimited(retryAfterSeconds: retryAfter)
    }
    if http.statusCode == 400 {
      throw APIError.syncUploadRejected(reason: "Audio file could not be processed by server")
    }
    if http.statusCode == 413 {
      throw APIError.syncUploadRejected(reason: "Audio file is too large to upload")
    }
    if http.statusCode >= 500 {
      throw APIError.syncUploadRejected(reason: "Server is temporarily unavailable")
    }
    throw APIError.syncUploadRejected(reason: "Upload failed unexpectedly")
  }

  private static func parseRetryAfterSeconds(from response: HTTPURLResponse) -> Int? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
    return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
  }

}
/// Response shape for `POST /v2/files` — mirrors backend `FileChat` model.
struct ChatFileResponse: Codable {
  let id: String
  let name: String?
  let mimeType: String?
  let thumbnail: String?
  let thumbName: String?
  let openaiFileId: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case thumbnail
    case mimeType = "mime_type"
    case thumbName = "thumb_name"
    case openaiFileId = "openai_file_id"
  }
}

/// Response from rating a message
struct MessageStatusResponse: Codable {
  let status: String
}

// MARK: - Sync local files (WAL upload)

/// Outcome of POST `/v2/sync-local-files` — exactly one of `jobId` (202) or `completed` (200).
enum UploadLocalFilesResult: Equatable {
  case queued(jobId: String)
  case done(SyncLocalFilesResultResponse)

  var jobId: String? {
    if case .queued(let jobId) = self { return jobId }
    return nil
  }
}

struct SyncLocalFilesResultResponse: Codable, Equatable {
  let newMemories: [String]
  let updatedMemories: [String]
  let failedSegments: Int
  let totalSegments: Int
  let errors: [String]

  enum CodingKeys: String, CodingKey {
    case newMemories = "new_memories"
    case updatedMemories = "updated_memories"
    case failedSegments = "failed_segments"
    case totalSegments = "total_segments"
    case errors
  }
}

struct SyncJobStartResponse: Codable, Equatable {
  let jobId: String
  let status: String
  let totalFiles: Int
  let totalSegments: Int
  let pollAfterMs: Int

  enum CodingKeys: String, CodingKey {
    case jobId = "job_id"
    case status
    case totalFiles = "total_files"
    case totalSegments = "total_segments"
    case pollAfterMs = "poll_after_ms"
  }
}

struct SyncJobStatusResponse: Codable, Equatable {
  let jobId: String
  let status: String
  let totalSegments: Int
  let processedSegments: Int
  let successfulSegments: Int
  let failedSegments: Int
  let result: SyncLocalFilesResultResponse?
  let error: String?

  var isTerminal: Bool {
    status == "completed" || status == "partial_failure" || status == "failed"
  }

  enum CodingKeys: String, CodingKey {
    case jobId = "job_id"
    case status
    case totalSegments = "total_segments"
    case processedSegments = "processed_segments"
    case successfulSegments = "successful_segments"
    case failedSegments = "failed_segments"
    case result
    case error
  }
}

enum SyncJobFetchOutcome: Equatable {
  case ok
  case notFound
  case forbidden
  case unauthorized
  case transient

  /// Pure HTTP-status → outcome mapping for a sync-job status GET. `.ok` means
  /// the 200 body still must be decoded by the caller (a decode failure is
  /// `.transient`); every other case is terminal for this fetch. Extracted so
  /// the mapping is unit-testable without a URLSession.
  static func forStatusCode(_ statusCode: Int) -> SyncJobFetchOutcome {
    switch statusCode {
    case 200: return .ok
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    default: return .transient
    }
  }
}

struct SyncJobFetch: Equatable {
  let outcome: SyncJobFetchOutcome
  let status: SyncJobStatusResponse?

  init(outcome: SyncJobFetchOutcome, status: SyncJobStatusResponse? = nil) {
    self.outcome = outcome
    self.status = status
  }
}

