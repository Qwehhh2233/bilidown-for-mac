import AppKit
import Combine
import SwiftUI

@MainActor
enum AppIconProvider {
    static let image: NSImage = {
        guard let url = Bundle.main.url(forResource: "BilidownPink", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        return image
    }()
}

@MainActor
enum AppearanceController {
    static func apply(rawValue: String?) {
        let mode = AppAppearance(rawValue: rawValue ?? "") ?? .system
        let appearance: NSAppearance?
        switch mode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        let windows = NSApp.windows
        windows.forEach { $0.disableScreenUpdatesUntilFlush() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            NSApp.appearance = appearance
            windows.forEach { $0.appearance = appearance }
        }
        windows.forEach {
            $0.contentView?.needsDisplay = true
            $0.displayIfNeeded()
        }
    }
}

final class BackendService {
    private var process: Process?
    private var logHandle: FileHandle?

    func start() throws {
        guard process?.isRunning != true else { return }
        guard let resources = Bundle.main.resourceURL else {
            throw APIError.server("找不到 App 资源目录")
        }

        let fileManager = FileManager.default
        let backendRoot = resources.appendingPathComponent("backend", isDirectory: true)
        let executable = backendRoot.appendingPathComponent("bilidown")
        let staticSource = backendRoot.appendingPathComponent("static", isDirectory: true)
        let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilidown", isDirectory: true)
        let downloadDirectory = supportRoot.appendingPathComponent("download", isDirectory: true)
        let staticLink = supportRoot.appendingPathComponent("static")

        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staticLink)
        try fileManager.createSymbolicLink(at: staticLink, withDestinationURL: staticSource)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            resources.appendingPathComponent("bridge-bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ].joined(separator: ":")
        environment["BILIDOWN_HEADLESS"] = "1"

        let logURL = supportRoot.appendingPathComponent("bilidown.log")
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = supportRoot
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { _ in try? handle.close() }
        try process.run()

        self.process = process
        self.logHandle = handle
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
        try? logHandle?.close()
        logHandle = nil
    }
}

@MainActor
final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    let backend = BackendService()
    private(set) var startupError: String?
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceController.apply(rawValue: UserDefaults.standard.string(forKey: "appearanceMode"))
        applyApplicationIcon()
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.applyApplicationIcon() }
        }
        do {
            try backend.start()
        } catch {
            startupError = error.localizedDescription
        }
        scheduleMenuConfiguration()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyApplicationIcon()
        scheduleMenuConfiguration()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        applyApplicationIcon()
        sender.activate(ignoringOtherApps: true)
        if !MainWindowPresenter.activateExistingWindow() {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showBilidownMainWindow, object: nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        backend.stop()
    }

    private func applyApplicationIcon() {
        let icon = AppIconProvider.image
        NSApp.applicationIconImage = icon
        let dockIconView = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        dockIconView.image = icon
        dockIconView.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = dockIconView
        NSApp.dockTile.display()
    }

    private func scheduleMenuConfiguration() {
        DispatchQueue.main.async { [weak self] in self?.configureMainMenu() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.configureMainMenu()
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "主菜单")

        let appMenu = NSMenu(title: "Bilidown")
        appMenu.addItem(menuItem("关于 Bilidown", action: "orderFrontStandardAboutPanel:", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("隐藏 Bilidown", action: "hide:", shortcut: "h", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出 Bilidown", action: "terminate:", shortcut: "q", target: NSApp))
        addTopLevelMenu(appMenu, title: "Bilidown", to: mainMenu)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(menuItem("撤销", action: "undo:", shortcut: "z"))
        editMenu.addItem(menuItem("重做", action: "redo:", shortcut: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("剪切", action: "cut:", shortcut: "x"))
        editMenu.addItem(menuItem("拷贝", action: "copy:", shortcut: "c"))
        editMenu.addItem(menuItem("粘贴", action: "paste:", shortcut: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("全选", action: "selectAll:", shortcut: "a"))
        addTopLevelMenu(editMenu, title: "编辑", to: mainMenu)

        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(menuItem(
            "进入全屏幕",
            action: "toggleFullScreen:",
            shortcut: "f",
            modifiers: [.command, .control]
        ))
        addTopLevelMenu(viewMenu, title: "显示", to: mainMenu)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(menuItem("关闭", action: "performClose:", shortcut: "w"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem("最小化", action: "performMiniaturize:", shortcut: "m"))
        windowMenu.addItem(menuItem("缩放", action: "performZoom:"))
        addTopLevelMenu(windowMenu, title: "窗口", to: mainMenu)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = nil
    }

    private func addTopLevelMenu(_ submenu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }

    private func menuItem(
        _ title: String,
        action: String,
        shortcut: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: shortcut)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var backendReady = false
    @Published var isLoggedIn = false
    @Published var userProfile: UserProfile?
    @Published var activeTasks: [ActiveTask] = []
    @Published var taskTitles: [Int: String] = [:]
    @Published var startupMessage = "正在启动下载服务…"
    @Published var startupError: String?
    private var downloadMonitorTask: Task<Void, Never>?

    func bootstrap(delegate: NativeAppDelegate) async {
        if let error = delegate.startupError {
            startupError = error
            return
        }

        for attempt in 0..<40 {
            do {
                let response: APIEnvelope<EmptyPayload> = try await APIClient.shared.envelope("checkLogin")
                isLoggedIn = response.success
                if response.success { await loadUserProfile() }
                backendReady = true
                startupMessage = ""
                return
            } catch {
                if attempt == 39 {
                    startupError = "无法连接 Bilidown 后端：\(error.localizedDescription)"
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func setLoggedIn(_ value: Bool) {
        isLoggedIn = value
        if value {
            Task { await loadUserProfile() }
        } else {
            userProfile = nil
        }
    }

    func loadUserProfile() async {
        userProfile = try? await APIClient.shared.getUserProfile()
    }

    func startDownloadMonitoring() {
        guard downloadMonitorTask == nil else { return }
        downloadMonitorTask = Task { await monitorDownloads() }
    }

    private func monitorDownloads() async {
        while !Task.isCancelled {
            do {
                async let active: [ActiveTask] = APIClient.shared.get("getActiveTask")
                async let records: [TaskRecord] = APIClient.shared.get(
                    "getTaskList",
                    query: [URLQueryItem(name: "page", value: "0"), URLQueryItem(name: "pageSize", value: "360")]
                )
                let (latestActive, latestRecords) = try await (active, records)
                activeTasks = latestActive.filter { $0.status == "running" || $0.status == "waiting" }
                taskTitles = Dictionary(uniqueKeysWithValues: latestRecords.map { ($0.id, $0.title) })
            } catch {
                // The backend can be briefly unavailable during launch; keep the last known status.
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }
}

@main
struct BilidownNativeApp: App {
    @NSApplicationDelegateAdaptor(NativeAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Bilidown", id: "main") {
            RootView(appDelegate: appDelegate)
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .background(MainWindowIdentifierView())
                .task {
                    if !model.backendReady && model.startupError == nil {
                        await model.bootstrap(delegate: appDelegate)
                    }
                    guard model.backendReady else { return }
                    model.startDownloadMonitoring()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commandsRemoved()

        MenuBarExtra {
            MenuBarStatusView(model: model)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
