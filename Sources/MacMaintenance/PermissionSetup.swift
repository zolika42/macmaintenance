#if os(macOS)
import SwiftUI
import AppKit
import UserNotifications
import MaintenanceCore

@MainActor struct PermissionSetup: View {
    let hu: Bool
    @ObservedObject var updates: UpdateCenter
    let finish: () -> Void
    @State private var reviewedAppManagement = false
    @State private var reviewedDiskAccess = false
    @State private var testingAdmin = false
    @State private var adminResult = ""
    @State private var notificationStatus = ""
    @Environment(\.scenePhase) private var scenePhase
    private func t(_ h: String, _ e: String) -> String { hu ? h : e }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Első indítás · jogosultságok", "First launch · permissions")).font(.title.bold())
            Text(t("A macOS védi a többi alkalmazást és az adataidat. Az engedélyeket te adod meg; a MacMaintenance nem tárol jelszót, és nem kapcsolja ki a rendszer védelmét.", "macOS protects other applications and your data. You grant access; MacMaintenance never stores your password or disables system protection.")).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !PermissionSetupPolicy.installedPath(Bundle.main.bundleURL.path, home: FileManager.default.homeDirectoryForCurrentUser.path) {
                        Label(t("Előbb másold az alkalmazást az Applications mappába, majd onnan indítsd el. A lemezképről adott engedély nem feltétlenül érvényes a telepített példányra.", "Copy the app to Applications first and launch that copy. Permissions given to a mounted disk image may not apply to the installed app."), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    PermissionsPanel(hu: hu)
                    Toggle(t("Átnéztem a Full Disk Access beállítást", "I reviewed Full Disk Access settings"), isOn: $reviewedDiskAccess)
                    GroupBox(t("Alkalmazáskezelés · App Management", "App Management")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("Engedélyezd a MacMaintenance számára más alkalmazások módosítását és eltávolítását. Nincs megbízható nyilvános API a jogosultság lekérdezésére; nem végzünk próbatörlést.", "Allow MacMaintenance to update and remove other apps. There is no reliable public status API; we do not delete a test app to infer access.")).font(.callout)
                            Button(t("App Management megnyitása", "Open App Management")) { openSettings("Privacy_AppBundles") }
                            Toggle(t("Átnéztem az App Management beállítást", "I reviewed App Management settings"), isOn: $reviewedAppManagement)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox(t("Adminisztrátori hitelesítés", "Administrator authorization")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("A próba csak a root felhasználó azonosítóját olvassa. A rendszer későbbi eltávolításkor ismét kérhet hitelesítést; ez nem állandó engedély.", "The test only reads the root user ID. macOS may ask again during a later removal; this is not a persistent grant.")).font(.callout)
                            HStack {
                                Button(t("Natív hitelesítési próba", "Test native authorization")) { Task { await testAdmin() } }.disabled(testingAdmin)
                                if testingAdmin { ProgressView().controlSize(.small) }
                            }
                            if !adminResult.isEmpty { Text(adminResult).font(.caption).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox(t("Fájlok, mappák és értesítések", "Files, folders and notifications")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("A Dokumentumok, Asztal és Letöltések hozzáférését csak az adott funkció használatakor kérjük, ha a macOS megköveteli. Az értesítés opcionális.", "Documents, Desktop and Downloads access is requested only when the relevant feature needs it and macOS requires it. Notifications are optional.")).font(.callout)
                            HStack {
                                Button(t("Fájlok és mappák", "Files & Folders")) { openSettings("Privacy_FilesAndFolders") }
                                Button(t("Értesítések engedélyezése", "Enable notifications")) { Task { await updates.enableNotifications(); await refreshNotifications() } }
                            }
                            if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(2)
            }
            Divider()
            Text(t("A beállítások áttekintése nem bizonyítja az összes jogosultság meglétét. Ha nincs hozzáférés, a funkció ezt jelzi. A varázsló később újranyitható.", "Reviewing settings does not prove that all access is granted. Features report denied access. You can reopen this setup later.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(t("Korlátozott módban folytatom", "Continue with limited access")) { finish() }.disabled(testingAdmin)
                Spacer()
                Button(t("Beállítások áttekintve", "Settings reviewed")) { finish() }.buttonStyle(.borderedProminent).disabled(!reviewedDiskAccess || !reviewedAppManagement || testingAdmin)
            }
        }.padding(24).frame(minWidth: 720, idealWidth: 790, minHeight: 620, idealHeight: 760)
            .interactiveDismissDisabled()
            .task { await refreshNotifications() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshNotifications() } } }
    }
    private func testAdmin() async {
        guard !testingAdmin else { return }; testingAdmin = true; defer { testingAdmin = false }
        let result = await Task.detached(priority: .utility) { ServiceRemoval.testAdministratorAuthorization() }.value
        adminResult = result.status == 0 && result.output == "0" ? t("A hitelesítési próba sikerült.", "Authorization test passed.") : t("A próba nem sikerült vagy megszakadt: ", "Test failed or cancelled: ") + result.output
    }
    private func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        switch status {
        case .authorized, .provisional: notificationStatus = t("Értesítések engedélyezve", "Notifications allowed")
        case .denied: notificationStatus = t("Értesítések megtagadva", "Notifications denied")
        case .notDetermined: notificationStatus = t("Még nincs döntés", "Not yet decided")
        @unknown default: notificationStatus = t("Nem ellenőrizhető", "Unknown")
        }
    }
}
#endif
