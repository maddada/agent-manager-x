import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterState: NSObject, ObservableObject, SPUUpdaterDelegate {
    enum UpdateStatus: Equatable {
        case idle
        case checking
        case available(version: String)
        case upToDate
        case error(String)
    }

    @Published var canCheckForUpdates = false
    @Published var lastUpdateCheckDate: Date?
    @Published var isAutomaticChecksEnabled = false
    @Published var updateStatus: UpdateStatus = .idle

    var updater: SPUUpdater? {
        didSet {
            bindUpdaterProperties()
            if let updater {
                isAutomaticChecksEnabled = updater.automaticallyChecksForUpdates
            }
        }
    }

    var currentVersionDisplay: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines), buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(shortVersion), .some(buildVersion)) where !shortVersion.isEmpty && !buildVersion.isEmpty:
            return "\(shortVersion) (\(buildVersion))"
        case let (.some(shortVersion), _) where !shortVersion.isEmpty:
            return shortVersion
        case let (_, .some(buildVersion)) where !buildVersion.isEmpty:
            return buildVersion
        default:
            return "Unknown"
        }
    }

    var statusSummary: String {
        switch updateStatus {
        case .idle:
            return "Sparkle is ready."
        case .checking:
            return "Checking for updates..."
        case let .available(version):
            return "Version \(version) is available."
        case .upToDate:
            return "You’re up to date."
        case let .error(message):
            return message
        }
    }

    private var cancellables = Set<AnyCancellable>()

    func checkForUpdates() {
        guard let updater else {
            updateStatus = .error("Updater is not configured.")
            return
        }

        updateStatus = .checking
        updater.checkForUpdates()
    }

    func toggleAutomaticChecks() {
        guard let updater else {
            return
        }

        updater.automaticallyChecksForUpdates.toggle()
        isAutomaticChecksEnabled = updater.automaticallyChecksForUpdates
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
#if arch(arm64)
        "https://raw.githubusercontent.com/maddada/agent-manager-x/main/appcast.xml"
#else
        "https://raw.githubusercontent.com/maddada/agent-manager-x/main/appcast-x64.xml"
#endif
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStatus = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        if case .checking = updateStatus {
            updateStatus = .upToDate
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError

        if let reasonValue = nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber,
           let reason = SPUNoUpdateFoundReason(rawValue: OSStatus(reasonValue.int32Value))
        {
            switch reason {
            case .onLatestVersion, .onNewerThanLatestVersion:
                updateStatus = .upToDate
                return
            case .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64, .unknown:
                break
            @unknown default:
                break
            }
        }

        updateStatus = .error(error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        updateStatus = .error("Failed to download \(item.displayVersionString): \(error.localizedDescription)")
    }

    private func bindUpdaterProperties() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        guard let updater else {
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canCheckForUpdates, on: self)
            .store(in: &cancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: \.lastUpdateCheckDate, on: self)
            .store(in: &cancellables)
    }
}
