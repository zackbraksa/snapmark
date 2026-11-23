import Combine
import Foundation
import Sparkle

struct UpdaterConfiguration {
    let feedURL: URL
    let publicKey: String

    static func resolve(
        information: [String: Any],
        isRunningTests: Bool = false
    ) -> UpdaterConfiguration? {
        guard !isRunningTests,
              information["SparkleUpdatesEnabled"] as? Bool == true,
              let feedValue = information["SUFeedURL"] as? String,
              let feedURL = URL(string: feedValue),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host != nil,
              feedURL.user == nil,
              feedURL.password == nil,
              let publicKey = information["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: publicKey),
              keyData.count == 32 else {
            return nil
        }

        return UpdaterConfiguration(feedURL: feedURL, publicKey: publicKey)
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    var isAvailable: Bool { controller != nil }

    init(information: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = Bundle.main.bundleURL.pathExtension == "xctest"
            || environment["XCTestConfigurationFilePath"] != nil
        guard UpdaterConfiguration.resolve(information: information, isRunningTests: isRunningTests) != nil else {
            controller = nil
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller = updaterController
        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
