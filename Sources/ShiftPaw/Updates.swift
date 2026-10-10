import AppKit
import Combine
import CryptoKit
import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String) throws {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else {
            throw UpdateError.invalidVersion
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
    }

    static var currentString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }
}

struct AppUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let sha256: String
    let filename: String
}

enum UpdateError: LocalizedError {
    case invalidVersion
    case invalidResponse
    case httpStatus(Int)
    case missingInstaller
    case invalidDownload
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidVersion: "无法识别版本号。"
        case .invalidResponse: "GitHub 返回了无效的更新信息。"
        case .httpStatus(let code): "更新服务暂不可用（HTTP \(code)），请稍后重试。"
        case .missingInstaller: "新版尚未提供适用的 Apple Silicon 安装包。"
        case .invalidDownload: "更新包地址、大小或校验信息无效。"
        case .checksumMismatch: "更新包 SHA-256 校验失败，请重新下载。"
        }
    }
}

protocol UpdateServicing: Sendable {
    func latestUpdate(after version: String) async throws -> AppUpdate?
    func download(_ update: AppUpdate) async throws -> URL
}

struct GitHubUpdateService: UpdateServicing {
    static let endpoint = URL(string: "https://api.github.com/repos/nullinject/ShiftPaw/releases/latest")!
    static let maximumInstallerSize = 200 * 1_024 * 1_024
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestUpdate(after version: String) async throws -> AppUpdate? {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShiftPaw/\(version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, [403, 429].contains(http.statusCode) {
            return try await latestUpdateFromWebsite(after: version)
        }
        try Self.validateResponse(response)
        return try Self.parse(data, currentVersion: version)
    }

    // The public latest-release link also works when the anonymous API quota is exhausted.
    private func latestUpdateFromWebsite(after currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: URL(string: "https://github.com/nullinject/ShiftPaw/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        try Self.validateResponse(response)
        guard let releaseURL = response.url else { throw UpdateError.invalidResponse }
        let version = try Self.version(fromReleaseURL: releaseURL)
        guard try AppVersion(version) > AppVersion(currentVersion) else { return nil }
        let checksumURL = URL(string: "https://github.com/nullinject/ShiftPaw/releases/download/v\(version)/SHA256SUMS.txt")!
        let (checksums, checksumResponse) = try await session.data(for: URLRequest(url: checksumURL, timeoutInterval: 20))
        try Self.validateResponse(checksumResponse)
        return try Self.parseChecksums(checksums, version: version)
    }

    static func version(fromReleaseURL url: URL) throws -> String {
        let tag = url.lastPathComponent
        guard tag.hasPrefix("v"), url.absoluteString == "https://github.com/nullinject/ShiftPaw/releases/tag/\(tag)" else {
            throw UpdateError.invalidResponse
        }
        _ = try AppVersion(tag)
        return String(tag.dropFirst())
    }

    static func parseChecksums(_ data: Data, version: String) throws -> AppUpdate {
        _ = try AppVersion(version)
        guard data.count <= 64 * 1_024, let text = String(data: data, encoding: .utf8) else { throw UpdateError.invalidResponse }
        let filename = "ShiftPaw-\(version)-macOS-arm64.dmg"
        let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == filename else { return nil }
            return String(fields[0]).lowercased()
        }
        guard matches.count == 1 else { throw UpdateError.invalidDownload }
        let update = AppUpdate(version: version,
                               downloadURL: URL(string: "https://github.com/nullinject/ShiftPaw/releases/download/v\(version)/\(filename)")!,
                               sha256: matches[0], filename: filename)
        try validate(update)
        return update
    }

    static func parse(_ data: Data, currentVersion: String) throws -> AppUpdate? {
        guard data.count <= 1_024 * 1_024 else { throw UpdateError.invalidResponse }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard try AppVersion(release.tag_name) > AppVersion(currentVersion) else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let filename = "ShiftPaw-\(version)-macOS-arm64.dmg"
        guard let asset = release.assets.first(where: { $0.name == filename && $0.state == "uploaded" }) else {
            throw UpdateError.missingInstaller
        }
        guard asset.size > 0, asset.size <= maximumInstallerSize,
              let digest = asset.digest, digest.hasPrefix("sha256:"),
              let url = URL(string: asset.browser_download_url) else { throw UpdateError.invalidDownload }
        let checksum = String(digest.dropFirst(7)).lowercased()
        let update = AppUpdate(version: version, downloadURL: url, sha256: checksum, filename: filename)
        try validate(update)
        return update
    }

    static func validate(_ update: AppUpdate) throws {
        _ = try AppVersion(update.version)
        let expected = "https://github.com/nullinject/ShiftPaw/releases/download/v\(update.version)/ShiftPaw-\(update.version)-macOS-arm64.dmg"
        guard update.downloadURL.absoluteString == expected,
              update.filename == "ShiftPaw-\(update.version)-macOS-arm64.dmg",
              update.sha256.count == 64,
              update.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw UpdateError.invalidDownload
        }
    }

    static func validateResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        guard response.statusCode == 200 else { throw UpdateError.httpStatus(response.statusCode) }
    }

    func download(_ update: AppUpdate) async throws -> URL {
        try Self.validate(update)
        let request = URLRequest(url: update.downloadURL, timeoutInterval: 180)
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Self.validateResponse(response)
        try Self.verifyInstaller(at: temporaryURL, checksum: update.sha256)
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ShiftPaw/Updates/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(update.filename)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func verifyInstaller(at url: URL, checksum: String) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumInstallerSize else { throw UpdateError.invalidDownload }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw UpdateError.checksumMismatch }
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
        let browser_download_url: String
        let digest: String?
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableUpdate: AppUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var statusText = "尚未检查更新"
    @Published private(set) var installerURL: URL?
    let currentVersion: String
    private let service: any UpdateServicing
    private var automaticTask: Task<Void, Never>?
    private var automaticChecksEnabled: Bool?

    init(service: any UpdateServicing = GitHubUpdateService(), currentVersion: String = AppVersion.currentString) {
        self.service = service
        self.currentVersion = currentVersion
    }

    deinit { automaticTask?.cancel() }

    func configureAutomaticChecks(_ enabled: Bool) {
        guard automaticChecksEnabled != enabled else { return }
        automaticChecksEnabled = enabled
        automaticTask?.cancel()
        automaticTask = nil
        guard enabled else { return }
        automaticTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdates()
                do {
                    try await Task.sleep(for: .seconds(6 * 60 * 60))
                } catch { return }
            }
        }
    }

    func checkForUpdates() async {
        guard !isChecking, !isDownloading else { return }
        isChecking = true
        statusText = "正在检查更新…"
        defer { isChecking = false }
        do {
            let update = try await service.latestUpdate(after: currentVersion)
            try Task.checkCancellation()
            if update != availableUpdate { installerURL = nil }
            availableUpdate = update
            statusText = update.map { "发现新版本 \($0.version)" } ?? "已是最新版本 \(currentVersion)"
        } catch is CancellationError {
            statusText = "检查已取消"
        } catch {
            statusText = "检查失败：\(error.localizedDescription)"
        }
    }

    func downloadUpdate() async {
        guard !isChecking, !isDownloading, let update = availableUpdate else { return }
        isDownloading = true
        statusText = "正在下载 \(update.version)…"
        defer { isDownloading = false }
        do {
            installerURL = try await service.download(update)
            statusText = "下载与校验完成，请打开安装包"
        } catch {
            statusText = "下载失败：\(error.localizedDescription)"
        }
    }

    func openInstaller() {
        guard let installerURL else { return }
        if NSWorkspace.shared.open(installerURL) {
            statusText = "退出应用后，将新版拖入 Applications 替换，再重新打开"
        } else {
            statusText = "无法打开安装包，请重试"
        }
    }
}
