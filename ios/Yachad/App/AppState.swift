import Foundation
import Combine

/// App-wide session state. There is no login: `deviceIdentity` is a random
/// id generated once per install (see DeviceIdentity.swift) and `myAreas`
/// is the list of areas this device has created or joined (in any status —
/// pending, approved, rejected), refreshed after every area-membership
/// change so the UI can route between "waiting for approval" and the real
/// dashboard.
@MainActor
final class AppState: ObservableObject {
    @Published var locale: AppLocale
    @Published var myAreas: [AreaMembership] = []
    @Published var selectedAreaID: UUID?
    @Published var isLoadingAreas = false
    @Published var lastError: String?

    let device: DeviceIdentity
    let areaService: AreaService

    init() {
        let device = DeviceIdentity.shared
        self.device = device
        self.locale = AppLocale(rawValue: UserDefaults.standard.string(forKey: "yachad.locale") ?? "") ?? .systemDefault
        self.areaService = AreaService(device: device)
    }

    var selectedMembership: AreaMembership? {
        myAreas.first { $0.area.id == selectedAreaID }
    }

    func setLocale(_ locale: AppLocale) {
        self.locale = locale
        UserDefaults.standard.set(locale.rawValue, forKey: "yachad.locale")
    }

    func refreshAreas() async {
        isLoadingAreas = true
        defer { isLoadingAreas = false }
        do {
            let areas = try await areaService.fetchMyAreas()
            myAreas = areas
            if let selectedAreaID, areas.contains(where: { $0.area.id == selectedAreaID }) == false {
                self.selectedAreaID = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
