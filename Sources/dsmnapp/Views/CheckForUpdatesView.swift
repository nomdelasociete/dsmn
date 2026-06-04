import Combine
import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    private let updateController: SoftwareUpdateController?
    private let updater: SPUUpdater?
    @StateObject private var viewModel: CheckForUpdatesViewModel

    init(updateController: SoftwareUpdateController?) {
        let updater = updateController?.updater
        self.updateController = updateController
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates...") {
            updateController?.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater?) {
        guard let updater else {
            return
        }

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
    }
}
