import Foundation
import Testing
@testable import ShiftPaw

struct UpdateTests {
    private let checksum = String(repeating: "a", count: 64)

    @Test("versions compare numerically and reject prerelease or malformed values")
    func comparesVersions() throws {
        #expect(try AppVersion("v1.10.0") > AppVersion("1.9.9"))
        #expect(try AppVersion("1.1.0") == AppVersion("v1.1.0"))
        for invalid in ["1.1", "1.1.0-beta", "-1.0.0", "1..0", "1.0.0/evil", "999999999999999999999999.0.0"] {
            #expect(throws: UpdateError.self) { try AppVersion(invalid) }
        }
    }

    @Test("only a newer stable release with the expected verified installer is offered")
    func selectsInstaller() throws {
        let candidate = try GitHubUpdateService.parse(release(), currentVersion: "1.0.0")
        let update = try #require(candidate)
        #expect(update.version == "1.1.0")
        #expect(update.sha256 == checksum)
        #expect(update.filename == "ShiftPaw-1.1.0-macOS-arm64.dmg")
        #expect(try GitHubUpdateService.parse(release(), currentVersion: "1.1.0") == nil)
        #expect(try GitHubUpdateService.parse(release(), currentVersion: "2.0.0") == nil)
        #expect(try GitHubUpdateService.parse(release(prerelease: true), currentVersion: "1.0.0") == nil)
        #expect(try GitHubUpdateService.parse(release(draft: true), currentVersion: "1.0.0") == nil)
    }

    @Test("untrusted URLs, missing checksums and invalid asset sizes are rejected")
    func rejectsUnsafeInstallers() throws {
        for url in ["http://github.com/nullinject/ShiftPaw/releases/download/v1.1.0/ShiftPaw-1.1.0-macOS-arm64.dmg", "https://example.com/installer.dmg", "https://github.com/other/ShiftPaw/releases/download/v1.1.0/ShiftPaw-1.1.0-macOS-arm64.dmg", "https://github.com/nullinject/ShiftPaw/releases/download/v1.1.0/ShiftPaw-1.1.0-macOS-arm64.dmg?redirect=evil"] {
            #expect(throws: UpdateError.self) { try GitHubUpdateService.parse(release(url: url), currentVersion: "1.0.0") }
        }
        for digest in ["", "md5:abc", "sha256:1234", "sha256:" + String(repeating: "z", count: 64)] {
            #expect(throws: UpdateError.self) { try GitHubUpdateService.parse(release(digest: digest), currentVersion: "1.0.0") }
        }
        for size in [0, -1, GitHubUpdateService.maximumInstallerSize + 1] {
            #expect(throws: UpdateError.self) { try GitHubUpdateService.parse(release(size: size), currentVersion: "1.0.0") }
        }
        #expect(throws: UpdateError.self) { try GitHubUpdateService.parse(release(name: "other.dmg"), currentVersion: "1.0.0") }
    }

    @Test("HTTP failures and corrupt payloads remain failures")
    func rejectsResponses() throws {
        let response = try #require(HTTPURLResponse(url: GitHubUpdateService.endpoint, statusCode: 403, httpVersion: nil, headerFields: nil))
        #expect(throws: UpdateError.self) { try GitHubUpdateService.validateResponse(response) }
        #expect(throws: DecodingError.self) { try GitHubUpdateService.parse(Data("invalid".utf8), currentVersion: "1.0.0") }
    }

    @Test("rate-limit fallback accepts only the official stable release redirect and checksum")
    func validatesWebsiteFallback() throws {
        let official = try #require(URL(string: "https://github.com/nullinject/ShiftPaw/releases/tag/v1.1.0"))
        #expect(try GitHubUpdateService.version(fromReleaseURL: official) == "1.1.0")
        for address in ["https://example.com/releases/tag/v1.1.0", "https://github.com/other/ShiftPaw/releases/tag/v1.1.0", "https://github.com/nullinject/ShiftPaw/releases/tag/v1.1.0-beta", "https://github.com/nullinject/ShiftPaw/releases/tag/v1.1.0?unsafe=true"] {
            let url = try #require(URL(string: address))
            #expect(throws: UpdateError.self) { try GitHubUpdateService.version(fromReleaseURL: url) }
        }
        let line = checksum + "  ShiftPaw-1.1.0-macOS-arm64.dmg\n"
        let update = try GitHubUpdateService.parseChecksums(Data(line.utf8), version: "1.1.0")
        #expect(update.sha256 == checksum)
        #expect(throws: UpdateError.self) { try GitHubUpdateService.parseChecksums(Data((line + line).utf8), version: "1.1.0") }
        #expect(throws: UpdateError.self) { try GitHubUpdateService.parseChecksums(Data("bad  ShiftPaw-1.1.0-macOS-arm64.dmg".utf8), version: "1.1.0") }
        #expect(throws: UpdateError.self) { try GitHubUpdateService.parseChecksums(Data("".utf8), version: "1.1.0") }
    }

    @Test("downloaded files must match SHA-256 before being offered for installation")
    func verifiesChecksum() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        try GitHubUpdateService.verifyInstaller(at: file, checksum: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(throws: UpdateError.self) { try GitHubUpdateService.verifyInstaller(at: file, checksum: checksum) }
        try Data().write(to: file)
        #expect(throws: UpdateError.self) { try GitHubUpdateService.verifyInstaller(at: file, checksum: checksum) }
    }

    @Test("automatic update preference defaults for old files and remains disabled after saving")
    func migratesUpdatePreference() throws {
        var settings = DutySettings.default
        settings.automaticallyChecksForUpdates = false
        let clean = try settings.sanitized()
        #expect(!clean.automaticallyChecksForUpdates)
        let data = try JSONEncoder().encode(clean)
        #expect(try JSONDecoder().decode(DutySettings.self, from: data).automaticallyChecksForUpdates == false)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "automaticallyChecksForUpdates")
        let migrated = try JSONDecoder().decode(DutySettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.automaticallyChecksForUpdates)
        #expect(migrated.events == settings.events)
    }

    @Test("checking and downloading expose verified results to the interface")
    @MainActor func updatesController() async throws {
        let candidate = try GitHubUpdateService.parse(release(), currentVersion: "1.0.0")
        let update = try #require(candidate)
        let controller = UpdateController(service: StubUpdateService(update: update), currentVersion: "1.0.0")
        await controller.checkForUpdates()
        #expect(controller.availableUpdate == update)
        #expect(!controller.isChecking)
        await controller.downloadUpdate()
        #expect(controller.installerURL?.lastPathComponent == update.filename)
        #expect(!controller.isDownloading)
        let offline = UpdateController(service: StubUpdateService(update: nil, fails: true), currentVersion: "1.1.0")
        await offline.checkForUpdates()
        #expect(offline.statusText.contains("检查失败"))
        #expect(!offline.isChecking)
    }

    private func release(prerelease: Bool = false, draft: Bool = false, url: String? = nil, digest: String? = nil, size: Int = 100, name: String = "ShiftPaw-1.1.0-macOS-arm64.dmg") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": "v1.1.0", "draft": draft, "prerelease": prerelease,
            "assets": [["name": name, "state": "uploaded", "size": size,
                        "browser_download_url": url ?? "https://github.com/nullinject/ShiftPaw/releases/download/v1.1.0/ShiftPaw-1.1.0-macOS-arm64.dmg",
                        "digest": digest ?? "sha256:" + checksum]]
        ])
    }
}

private struct StubUpdateService: UpdateServicing {
    let update: AppUpdate?
    var fails = false

    func latestUpdate(after version: String) async throws -> AppUpdate? {
        if fails { throw URLError(.notConnectedToInternet) }
        return update
    }

    func download(_ update: AppUpdate) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(update.filename)")
    }
}
