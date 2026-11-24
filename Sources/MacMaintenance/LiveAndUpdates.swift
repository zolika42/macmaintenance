#if os(macOS)
import SwiftUI
import Charts
import AppKit
@preconcurrency import UserNotifications
import MaintenanceCore

private enum LiveSampler {
    static func output(_ executable: String, _ arguments: [String], timeout: TimeInterval = 4) -> String? {
        let result = Runner.run(.init("Live sample", executable, arguments), timeout: timeout)
        return result.status == 0 ? result.output : nil
    }
    static func sample(previous: MonitorReading?) -> MonitorReading {
        let cpu = output("/usr/bin/top", ["-l", "2", "-s", "1", "-n", "0"], timeout: 5).flatMap(MonitorParsing.cpu)
        let memory = output("/usr/bin/vm_stat", []).flatMap(MonitorParsing.memory)
        let swap = output("/usr/sbin/sysctl", ["-n", "vm.swapusage"]).flatMap(MonitorParsing.swap)
        let battery = output("/usr/bin/pmset", ["-g", "batt"]).flatMap(MonitorParsing.battery)
        let network = output("/usr/sbin/netstat", ["-ibn"]).map(MonitorParsing.network) ?? [:]
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unavailable"
        }
        return .init(cpu: cpu, memoryBytes: memory, totalMemory: ProcessInfo.processInfo.physicalMemory, swapBytes: swap, battery: battery?.0, batteryState: battery?.1, thermal: thermal, network: network, previous: previous)
    }
    static func cycles() -> UInt64? { output("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-d", "1"]).flatMap(MonitorParsing.batteryCycles) }
}
@MainActor final class LiveMonitor: ObservableObject {
    @Published private(set) var samples: [MonitorReading] = []
    @Published private(set) var running = false
    @Published private(set) var cycleCount: UInt64?
    @Published private(set) var cycleBusy = false
    private var loop: Task<Void, Never>?
    var latest: MonitorReading? { samples.last }
    func start() {
        guard !running else { return }
        running = true
        loop = Task { [weak self] in
            var previous: MonitorReading?
            while !Task.isCancelled {
                let old = previous
                let worker = Task.detached(priority: .utility) { LiveSampler.sample(previous: old) }
                let sample = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self else { return }
                previous = sample
                self.samples.append(sample)
                if self.samples.count > 120 { self.samples.removeFirst(self.samples.count - 120) }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil; running = false }
    func refreshCycles() async {
        guard !cycleBusy else { return }; cycleBusy = true; defer { cycleBusy = false }
        cycleCount = await Task.detached(priority: .utility) { LiveSampler.cycles() }.value
    }
}
@MainActor struct MonitorPanel: View {
    @ObservedObject var live: LiveMonitor
    let hu: Bool
    private func t(_ a: String, _ b: String) -> String { hu ? a : b }
    private func percent(_ x: Double?) -> String { x.map { String(format: "%.1f%%", $0) } ?? "—" }
    private func bytes(_ x: UInt64?) -> String { x.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "—" }
    private func rate(_ x: Double?) -> String { guard let x, x.isFinite, x >= 0, x < Double(Int64.max) else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(x), countStyle: .file) + "/s" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { if live.running { live.stop() } else { live.start() } } label: { Label(live.running ? t("Szünet", "Pause") : t("Indítás", "Start"), systemImage: live.running ? "pause.circle" : "play.circle") }.buttonStyle(.borderedProminent)
                    if live.running { ProgressView().controlSize(.small) }
                    Text(live.running ? t("Mintavétel folyamatban", "Sampling") : t("Szüneteltetve", "Paused")).foregroundStyle(.secondary)
                    Spacer()
                    if let latest = live.latest { Text(latest.date.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary) }
                }
                if let latest = live.latest {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("CPU", percent(latest.cpu), "cpu", t("Összes mag terhelése", "Aggregate CPU load"))
                        metric(t("RAM – becslés", "RAM estimate"), percent(latest.memoryPercent), "memorychip", bytes(latest.memoryBytes) + " / " + bytes(latest.totalMemory))
                        metric("Swap", bytes(latest.swapBytes), "internaldrive", t("Használt swap", "Swap used"))
                        metric(t("Akkumulátor", "Battery"), percent(latest.battery), "battery.75percent", latest.batteryState ?? t("Nem elérhető", "Unavailable"))
                        metric(t("Hőállapot", "Thermal state"), latest.thermal, "thermometer.medium", t("macOS állapotjelzés, nem Celsius", "macOS state, not degrees"))
                        metric(t("Hálózat", "Network"), "↓ " + rate(latest.downloadRate), "network", "↑ " + rate(latest.uploadRate))
                    }
                    GroupBox(t("CPU és memória", "CPU and memory")) {
                        Chart {
                            ForEach(live.samples) { sample in
                                if let value = sample.cpu { LineMark(x: .value("Time", sample.date), y: .value("Percent", value)).foregroundStyle(by: .value("Metric", "CPU")) }
                                if let value = sample.memoryPercent { LineMark(x: .value("Time", sample.date), y: .value("Percent", value)).foregroundStyle(by: .value("Metric", "RAM")) }
                            }
                        }.chartYScale(domain: 0.0...100.0).frame(height: 165).padding(.top, 8)
                    }
                    GroupBox(t("Hálózati sebesség (MB/s)", "Network throughput (MB/s)")) {
                        Chart {
                            ForEach(live.samples) { sample in
                                if let value = sample.downloadRate { LineMark(x: .value("Time", sample.date), y: .value("MB/s", value / 1_000_000)).foregroundStyle(by: .value("Direction", t("Letöltés", "Receive"))) }
                                if let value = sample.uploadRate { LineMark(x: .value("Time", sample.date), y: .value("MB/s", value / 1_000_000)).foregroundStyle(by: .value("Direction", t("Feltöltés", "Send"))) }
                            }
                        }.frame(height: 145).padding(.top, 8)
                        Text(t("Csak en* interfészek link-számlálói. Az első minta, interfészváltás és számláló-reset után nincs sebességadat.", "en* link counters only. No rate on first sample, interface changes or counter resets.")).font(.caption).foregroundStyle(.secondary)
                    }
                } else { ContentUnavailableView(t("Még nincs minta", "No sample yet"), systemImage: "waveform.path.ecg", description: Text(t("Indítsd a monitorozást.", "Start monitoring."))) }
                GroupBox(t("Akkumulátordiagnosztika", "Battery diagnostics")) {
                    HStack { Text(t("Ciklusszám", "Cycle count")); Spacer(); Text(live.cycleCount.map { String($0) } ?? "—").monospacedDigit(); Button(t("Lekérdezés", "Refresh")) { Task { await live.refreshCycles() } }.disabled(live.cycleBusy) }.padding(5)
                }
                Text(t("A RAM-becslés aktív + wired + tömörített fizikai lapokat mér, nem az Aktivitásfigyelő pontos értékét. A minták csak memóriában maradnak (legfeljebb 120). A mintavétel az app futása alatt folytatódik, amíg le nem állítod.", "RAM estimates active + wired + compressed physical pages, not the exact Activity Monitor figure. Up to 120 samples are held in memory only. Sampling continues while the app runs until paused.")).font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
        }.task { if live.samples.isEmpty && !live.running { live.start() }; if live.cycleCount == nil { await live.refreshCycles() } }
    }
    private func metric(_ title: String, _ value: String, _ icon: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) { Text(title).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit(); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor final class UpdateCenter: ObservableObject {
    static var defaultFolder: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let development = home.appendingPathComponent("Projects/mac-maintenance/Releases", isDirectory: true)
        if (try? development.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink == false }) == true { return development.path }
        return home.appendingPathComponent("Library/Application Support/MacMaintenance/Releases", isDirectory: true).path
    }
    let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    @Published private(set) var folder: String
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "updates.automatic"); if automatic { Task { await check() } } } }
    @Published var notifications: Bool { didSet { UserDefaults.standard.set(notifications, forKey: "updates.notifications") } }
    @Published private(set) var result: ReleaseCheck?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published var notice = ""
    @Published var onlineEnabled = UserDefaults.standard.bool(forKey: "updates.online") {
        didSet {
            UserDefaults.standard.set(onlineEnabled, forKey: "updates.online")
            if onlineEnabled { Task { await check() } }
            else { onlineGeneration = UUID(); checkWork?.cancel(); downloadWork?.cancel(); onlineRelease = nil; onlineNotice = "" }
        }
    }
    @Published var automaticDownload = UserDefaults.standard.bool(forKey: "updates.automaticDownload") {
        didSet {
            UserDefaults.standard.set(automaticDownload, forKey: "updates.automaticDownload")
            if automaticDownload && onlineEnabled { Task { await check() } }
            else if autoDownloadInProgress { downloadWork?.cancel() }
        }
    }
    private var onlineGeneration = UUID()
    private var checkWork: Task<SignedRelease, Error>?
    private var downloadWork: Task<URL, Error>?
    private var autoDownloadInProgress = false
    func cancelOnlineWork() {
        onlineGeneration = UUID()
        checkWork?.cancel(); downloadWork?.cancel()
        onlineNotice = "Online operation cancelled. / Internetes művelet megszakítva."
    }
    private func fetchOnline(_ key: Data) async throws -> SignedRelease {
        let worker = Task { try await OnlineUpdates.check(publicKey: key) }
        checkWork = worker; defer { checkWork = nil }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private func fetchDMG(_ release: SignedRelease, key: Data) async throws -> URL {
        let worker = Task { try await OnlineUpdates.download(release, publicKey: key) }
        downloadWork = worker; defer { downloadWork = nil }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private var autoDownloaded: SignedRelease?
    private var autoDownloadedURL: URL?
    @Published private(set) var onlineRelease: SignedRelease?
    @Published private(set) var onlineNotice = ""
    private var publicKey: Data? {
        guard let url = Bundle.main.url(forResource: "UpdatePublicKey", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func downloadOnline() async {
        guard !checking, onlineEnabled, let release = onlineRelease, let key = publicKey,
              let current = ReleaseVersion(installed), let remote = release.releaseVersion, remote > current else { return }
        checking = true; defer { checking = false }
        let generation = onlineGeneration
        do {
            let url = try await fetchDMG(release, key: key)
            guard onlineEnabled, generation == onlineGeneration else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onlineNotice = "Verified DMG downloaded. Install manually. / Ellenőrzött DMG letöltve."
        } catch { if onlineEnabled && generation == onlineGeneration { onlineNotice = "Online download failed: " + error.localizedDescription } }
    }
    private var loop: Task<Void, Never>?
    var available: LocalRelease? { if case .available(let release) = result { return release }; return nil }
    init() {
        let defaults = UserDefaults.standard
        folder = defaults.string(forKey: "updates.folder") ?? Self.defaultFolder
        automatic = defaults.object(forKey: "updates.automatic") as? Bool ?? false
        notifications = defaults.bool(forKey: "updates.notifications")
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if self?.automatic == true { await self?.check() }
                do { try await Task.sleep(for: .seconds(900)) } catch { return }
            }
        }
    }
    func chooseFolder() {
        guard !checking else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setFolder(url.path) }
    }
    func setFolder(_ path: String) {
        guard !checking else { return }; folder = path; result = nil; lastChecked = nil; UserDefaults.standard.set(path, forKey: "updates.folder")
        Task { await check() }
    }
    func check() async {
        guard !checking else { return }
        guard let version = ReleaseVersion(installed) else { result = .invalid("Installed app version unavailable"); return }
        checking = true; defer { checking = false }
        let generation = onlineGeneration
        let path = folder
        result = await Task.detached(priority: .utility) { LocalUpdates.check(folder: URL(fileURLWithPath: path, isDirectory: true), current: version, hash: LocalUpdates.sha256) }.value
        if onlineEnabled && generation == onlineGeneration {
            onlineRelease = nil
            if let key = publicKey {
                do {
                    let release = try await fetchOnline(key)
                    if onlineEnabled, generation == onlineGeneration, let remote = release.releaseVersion, remote > version {
                        onlineRelease = release; onlineNotice = "Verified online release: " + release.version
                        if autoDownloaded == release, let url = autoDownloadedURL, FileManager.default.fileExists(atPath: url.path) { onlineNotice = "Verified DMG downloaded. Install manually: " + url.path }
                        if notifications { await notifyVersion(release.version) }
                        if automaticDownload && onlineEnabled && generation == onlineGeneration && (autoDownloaded != release || autoDownloadedURL.map { !FileManager.default.fileExists(atPath: $0.path) } != false) {
                            do {
                                autoDownloadInProgress = true
                                defer { autoDownloadInProgress = false }
                                let url = try await fetchDMG(release, key: key)
                                if onlineEnabled && automaticDownload && generation == onlineGeneration {
                                    autoDownloaded = release; autoDownloadedURL = url
                                    onlineNotice = "Verified DMG downloaded. Install manually: " + url.path
                                }
                            } catch { if onlineEnabled && automaticDownload && generation == onlineGeneration { onlineNotice = "Automatic download failed: " + error.localizedDescription } }
                        }
                    } else if onlineEnabled && generation == onlineGeneration { onlineNotice = "No newer verified online release." }
                } catch { if onlineEnabled && generation == onlineGeneration { onlineNotice = "Online verification failed: " + error.localizedDescription } }
            } else { onlineNotice = "Publisher key missing; online updates disabled." }
        }
        lastChecked = Date()
        if let release = available, notifications { await notify(release) }
    }
    func enableNotifications() async {
        do {
            notifications = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !notifications { notice = "Notifications unavailable or denied. / Az értesítés nincs engedélyezve." }
            else if let release = available { await notify(release) }
        } catch { notifications = false; notice = error.localizedDescription }
    }
    private func notify(_ release: LocalRelease) async {
        await notifyVersion(release.version.description)
    }
    private func notifyVersion(_ key: String) async {
        guard UserDefaults.standard.string(forKey: "updates.lastNotified") != key else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let hu = UserDefaults.standard.object(forKey: "hungarian") as? Bool ?? true
        let content = UNMutableNotificationContent(); content.title = "MacMaintenance \(key)"; content.body = hu ? "Új kiadás érhető el. Nyisd meg a Frissítések menüt." : "A new release is available. Open Updates."; content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "macmaintenance-update-\(key)", content: content, trigger: nil)); UserDefaults.standard.set(key, forKey: "updates.lastNotified") } catch { notice = error.localizedDescription }
    }
    func revealVerifiedRelease() async {
        guard !checking, let expected = available else { return }
        await check()
        guard let actual = available, actual == expected else { notice = "Release changed. Review again. / A kiadás megváltozott, ellenőrizd újra."; return }
        NSWorkspace.shared.activateFileViewerSelecting([actual.file])
    }
}
@MainActor struct UpdatesPanel: View {
    @ObservedObject var updates: UpdateCenter
    let hu: Bool
    private func t(_ a: String, _ b: String) -> String { hu ? a : b }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: updates.available == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill").font(.system(size: 42)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 5) { Text("MacMaintenance \(updates.installed)").font(.title2.bold()); Text(status).foregroundStyle(.secondary).textSelection(.enabled); if let date = updates.lastChecked { Text(t("Utolsó ellenőrzés: ", "Last checked: ") + date.formatted()).font(.caption).foregroundStyle(.secondary) } }
                        Spacer()
                        if updates.checking { ProgressView().controlSize(.small) }
                    }.padding(10)
                }
                HStack {
                    Button { Task { await updates.check() } } label: { Label(t("Frissítések keresése", "Check for updates"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(updates.checking)
                    if updates.available != nil { Button { Task { await updates.revealVerifiedRelease() } } label: { Label(t("Ellenőrzött DMG megjelenítése", "Reveal verified DMG"), systemImage: "folder") }.disabled(updates.checking) }
                }
                GroupBox(t("Automatikus frissítéskeresés", "Automatic update checks")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(t("Induláskor és 15 percenként, amíg az app fut", "At startup and every 15 minutes while running"), isOn: $updates.automatic)
                        if updates.notifications { Toggle(t("macOS értesítések", "macOS notifications"), isOn: $updates.notifications) }
                        else { Button(t("macOS értesítések engedélyezése", "Enable macOS notifications")) { Task { await updates.enableNotifications() } } }
                        Text(t("Új kiadáskor a programban figyelmeztetés jelenik meg; az opcionális rendszerértesítéshez macOS-engedély kell.", "New releases show an in-app notice; optional system notifications require macOS permission.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox(t("Hitelesített internetes frissítés", "Signed online updates")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(t("Online verziókeresés engedélyezése (GitHub)", "Enable online version checks (GitHub)"), isOn: $updates.onlineEnabled)
                        Toggle(t("Új, hitelesített DMG automatikus letöltése", "Automatically download new verified DMG"), isOn: $updates.automaticDownload).disabled(!updates.onlineEnabled)
                        Text(updates.onlineNotice).font(.caption).textSelection(.enabled)
                        if updates.checking && updates.onlineEnabled { Button(t("Internetes művelet megszakítása", "Cancel online operation")) { updates.cancelOnlineWork() } }
                        if updates.onlineRelease != nil { Button(t("Ellenőrzött DMG letöltése", "Download verified DMG")) { Task { await updates.downloadOnline() } }.disabled(updates.checking) }
                        Text(t("A kiadó aláírását és a DMG SHA-256 értékét ellenőrizzük; nincs automatikus telepítés.", "Publisher signature and DMG SHA-256 are checked; no automatic installation.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox(t("Helyi kiadási forrás", "Local release source")) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(updates.folder).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        HStack { Button(t("Mappa kiválasztása", "Choose folder")) { updates.chooseFolder() }.disabled(updates.checking); Button(t("Alapértelmezett", "Reset default")) { updates.setFolder(UpdateCenter.defaultFolder) }.disabled(updates.checking); Button(t("Mappa megnyitása", "Open folder")) { NSWorkspace.shared.open(URL(fileURLWithPath: updates.folder, isDirectory: true)) } }
                        Text(t("A make release hozza létre a DMG-t és a hozzá tartozó .sha256 fájlt. Mindkettő legyen ebben a mappában. A SHA-256 integritást ellenőriz, nem a kiadó hitelességét. Kizárólag saját, megbízható forrásból telepíts.", "make release creates the DMG and its .sha256 file. Both must be in this folder. SHA-256 checks integrity, not publisher authenticity. Install only from your own trusted source.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !updates.notice.isEmpty { Text(updates.notice).foregroundStyle(.orange).textSelection(.enabled) }
                Text(t("A helyi keresés csak olvas. Az online keresés opcionális; nincs automatikus telepítés vagy háttérdaemon.", "Local checks are read-only. Online checks are optional; no automatic installation or background daemon.")).font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 10)
        }
    }
    private var status: String {
        guard let result = updates.result else { return t("Még nincs ellenőrzés.", "Not checked yet.") }
        switch result {
        case .current: return t("Nincs újabb kiadás a helyi forrásban.", "No newer release in the local source.")
        case .available(let release): return t("Új kiadás érhető el: ", "New release available: ") + release.version.description
        case .unavailable(let message): return t("A forrás nem elérhető: ", "Source unavailable: ") + message
        case .invalid(let message): return t("Ellenőrzési hiba: ", "Verification error: ") + message
        }
    }
}
#endif
