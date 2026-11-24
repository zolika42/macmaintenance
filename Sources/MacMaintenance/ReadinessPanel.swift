#if os(macOS)
import SwiftUI
import AppKit
import MaintenanceCore

struct ProtectionSummary: View {
    let results: [CommandResult]
    let hu: Bool
    var body: some View {
        GroupBox(hu ? "Rendszervédelem" : "System protection") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(ProtectionCheck.allCases, id: \.rawValue) { check in
                    let result = results.first { $0.title == check.rawValue }
                    let state = check.evaluate(output: result?.output ?? "", status: result?.status)
                    HStack {
                        Image(systemName: state == .enabled ? "checkmark.shield" : state == .disabled ? "exclamationmark.shield" : "questionmark.circle")
                            .foregroundStyle(state == .enabled ? Color.green : state == .disabled ? Color.orange : Color.secondary)
                        Text(check.rawValue).fontWeight(.medium)
                        Spacer()
                        Text(state == .enabled ? (hu ? "Bekapcsolva" : "Enabled") : state == .disabled ? (hu ? "Kikapcsolva" : "Disabled") : (hu ? "Nem igazolt" : "Unverified")).font(.caption)
                    }.padding(5)
                }
            }
            Text(hu ? "Csak a sikeres, ismert állapotkimenet értelmezhető. Ez nem teljes biztonsági minősítés." : "Only recognized successful output is classified. This is not a complete security assessment.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
@MainActor struct PermissionsPanel: View {
    let hu: Bool
    @State private var findings: [String: DirectoryAccess] = [:]
    @State private var checked: Date?
    @State private var checking = false
    private let paths = ["Library/Mail", "Library/Safari", "Library/Messages"]
    var body: some View {
        GroupBox(hu ? "Hozzáférések · Full Disk Access" : "Permissions · Full Disk Access") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(hu ? "Hozzáférés tesztelése" : "Test access") { Task { await probe() } }.disabled(checking)
                    Button(hu ? "Rendszerbeállítások" : "System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                    }
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    if let checked { Text(checked.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(paths, id: \.self) { path in
                    HStack { Text("~/" + path).font(.caption.monospaced()); Spacer(); Text(label(findings[path])).font(.caption).foregroundStyle(.secondary) }
                }
                Text(hu ? "Csak könyvtármegnyitási próba, tartalom olvasása nélkül. Nem bizonyítja a Full Disk Access jogosultságot; az engedélyt a macOS-ben te állítod be. Engedélymódosítás után indítsd újra az appot." : "Directory-open probe only; no contents read. It does not prove Full Disk Access. You control permission in macOS. Restart after changing access.").font(.caption).foregroundStyle(.secondary)
            }
        }.task { await probe() }
    }
    private func label(_ state: DirectoryAccess?) -> String {
        switch state {
        case .accessible: hu ? "Elérhető" : "Accessible"
        case .denied: hu ? "Hozzáférés megtagadva" : "Denied"
        case .missing: hu ? "Nem található" : "Missing"
        case .unavailable: hu ? "Nem ellenőrizhető" : "Unavailable"
        case nil: hu ? "Nem vizsgált" : "Not checked"
        }
    }
    private func probe() async {
        guard !checking else { return }; checking = true; defer { checking = false }
        let paths = self.paths
        findings = await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Dictionary(uniqueKeysWithValues: paths.map { ($0, PermissionProbe.directory(home.appendingPathComponent($0, isDirectory: true))) })
        }.value
        checked = Date()
    }
}
#endif
