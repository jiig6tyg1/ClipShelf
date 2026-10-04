import SwiftUI
import ServiceManagement

final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error = ""
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.status = readStatus()
    }
    func refresh() { status = readStatus() }
    func setEnabled(_ enabled: Bool) {
        error = ""
        do {
            if enabled { try register() } else { try unregister() }
        } catch {
            self.error = "ログイン時の起動設定を変更できませんでした。\(error.localizedDescription)"
        }
        refresh()
    }
}
