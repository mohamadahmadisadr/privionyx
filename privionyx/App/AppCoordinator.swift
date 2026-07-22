import Observation

@MainActor
@Observable
final class AppCoordinator {
    var selectedTab: AppTab = .dashboard
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case addReceipt
    case assistant
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            "Home"
        case .addReceipt:
            "Camera"
        case .assistant:
            "Assistant"
        case .settings:
            "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            "house"
        case .addReceipt:
            "camera"
        case .assistant:
            "bubble.left"
        case .settings:
            "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard:
            "house.fill"
        case .addReceipt:
            "camera.fill"
        case .assistant:
            "bubble.left.fill"
        case .settings:
            "gearshape.fill"
        }
    }
}
