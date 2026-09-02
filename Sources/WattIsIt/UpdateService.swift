import Foundation

struct AppUpdate: Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL
}

enum UpdateService {
    private static let repositoryOwner = "shay2000"
    private static let repositoryName = "watt-is-it"
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest"
    )!

    static func fetchLatestUpdate(currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("WattIsIt/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard
            let releaseVersion = SemanticVersion(tag: release.tagName),
            let installedVersion = SemanticVersion(tag: currentVersion),
            releaseVersion > installedVersion
        else {
            return nil
        }

        guard let asset = release.assets.first(where: isSupportedDMG) else {
            throw UpdateError.missingDMG
        }

        return AppUpdate(
            version: releaseVersion.description,
            releaseURL: release.htmlURL,
            downloadURL: asset.browserDownloadURL
        )
    }

    static func downloadDMG(for update: AppUpdate) async throws -> URL {
        var request = URLRequest(url: update.downloadURL)
        request.timeoutInterval = 60
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validate(response)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("WattIsIt-\(update.version)-\(UUID().uuidString).dmg")

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func isSupportedDMG(_ asset: GitHubAsset) -> Bool {
        guard
            asset.name.hasPrefix("WattIsIt-"),
            asset.name.hasSuffix("-macOS-arm64.dmg"),
            asset.browserDownloadURL.host == "github.com"
        else {
            return false
        }

        return asset.browserDownloadURL.path.hasPrefix(
            "/\(repositoryOwner)/\(repositoryName)/releases/download/"
        )
    }

    private static func validate(_ response: URLResponse) throws {
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UpdateError.httpFailure(statusCode: statusCode)
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    private let components: [Int]

    init?(tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = normalized.split(separator: ".")

        guard
            !parts.isEmpty,
            parts.count <= 3,
            parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
            let values = Optional(parts.compactMap { Int($0) }),
            values.count == parts.count
        else {
            return nil
        }

        components = values + Array(repeating: 0, count: 3 - values.count)
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

enum UpdateError: LocalizedError {
    case httpFailure(statusCode: Int)
    case missingDMG
    case invalidUpdateBundle
    case cannotUpdateFromDiskImage
    case installationCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .httpFailure(statusCode):
            if statusCode == 403 {
                return "GitHub temporarily rate-limited the update check."
            }
            return "GitHub returned an unexpected response (\(statusCode))."
        case .missingDMG:
            return "The latest GitHub release does not contain an Apple silicon DMG."
        case .invalidUpdateBundle:
            return "The downloaded update is not a valid Watt is it? app."
        case .cannotUpdateFromDiskImage:
            return "Open Watt is it? from Applications before installing an update."
        case let .installationCommandFailed(command):
            return "macOS could not install the update (\(command))."
        }
    }
}

enum UpdateInstaller {
    private static let bundleIdentifier = "com.wattisit.app"

    static func prepareInstallation(dmgURL: URL, replacing appURL: URL) throws {
        let fileManager = FileManager.default
        defer {
            try? fileManager.removeItem(at: dmgURL)
        }

        guard
            appURL.pathExtension == "app",
            fileManager.fileExists(atPath: appURL.path)
        else {
            throw UpdateError.invalidUpdateBundle
        }

        guard !appURL.path.hasPrefix("/Volumes/") else {
            throw UpdateError.cannotUpdateFromDiskImage
        }

        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WattIsIt-install-\(UUID().uuidString)", isDirectory: true)
        let mountPoint = workRoot.appendingPathComponent("mounted", isDirectory: true)
        let stagedApp = workRoot.appendingPathComponent("WattIsIt.app", isDirectory: true)

        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        var mounted = false
        do {
            try run(
                "/usr/bin/hdiutil",
                arguments: [
                    "attach",
                    "-nobrowse",
                    "-readonly",
                    "-mountpoint",
                    mountPoint.path,
                    dmgURL.path
                ]
            )
            mounted = true

            let sourceApp = mountPoint.appendingPathComponent("WattIsIt.app", isDirectory: true)
            guard fileManager.fileExists(atPath: sourceApp.path) else {
                throw UpdateError.invalidUpdateBundle
            }

            try validateBundle(at: sourceApp)
            try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", sourceApp.path])
            try fileManager.copyItem(at: sourceApp, to: stagedApp)

            try run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path])
            mounted = false
        } catch {
            if mounted {
                _ = try? run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path])
            }
            try? fileManager.removeItem(at: workRoot)
            throw error
        }

        let backupApp = workRoot.appendingPathComponent(
            "WattIsIt-backup-\(UUID().uuidString).app",
            isDirectory: true
        )
        let scriptURL = workRoot.appendingPathComponent("install.sh")
        let script = installationScript(
            stagedApp: stagedApp,
            currentApp: appURL,
            backupApp: backupApp,
            workRoot: workRoot
        )

        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func validateBundle(at appURL: URL) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: infoData,
            options: [],
            format: nil
        )
        guard
            let info = propertyList as? [String: Any],
            info["CFBundleIdentifier"] as? String == bundleIdentifier,
            info["CFBundleExecutable"] as? String == "WattIsIt"
        else {
            throw UpdateError.invalidUpdateBundle
        }
    }

    private static func installationScript(
        stagedApp: URL,
        currentApp: URL,
        backupApp: URL,
        workRoot: URL
    ) -> String {
        """
        #!/bin/sh
        set -eu

        /bin/sleep 1
        target=\(shellQuote(currentApp.path))
        staged=\(shellQuote(stagedApp.path))
        backup=\(shellQuote(backupApp.path))
        work=\(shellQuote(workRoot.path))

        if [ -e \"$backup\" ]; then
            /bin/rm -rf \"$backup\"
        fi

        if ! /bin/mv \"$target\" \"$backup\"; then
            /bin/rm -rf \"$work\"
            exit 1
        fi

        if ! /bin/mv \"$staged\" \"$target\"; then
            /bin/mv \"$backup\" \"$target\"
            /bin/rm -rf \"$work\"
            exit 1
        fi

        /usr/bin/open -n \"$target\" || true
        /bin/sleep 1
        /bin/rm -rf \"$backup\" \"$work\"
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private static func run(_ executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WattIsIt-output-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        var outputHandleClosed = false
        defer {
            if !outputHandleClosed {
                try? outputHandle.close()
            }
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        process.waitUntilExit()

        try? outputHandle.close()
        outputHandleClosed = true

        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateError.installationCommandFailed(
                outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return outputText
    }
}
