import AppKit
import SwiftUI

extension Notification.Name {
    static let showBilidownMainWindow = Notification.Name("BilidownShowMainWindow")
}

@MainActor
enum MainWindowPresenter {
    static let identifier = NSUserInterfaceItemIdentifier("BilidownMainWindow")

    @discardableResult
    static func activateExistingWindow() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier == identifier }) else {
            return false
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func show(using openWindow: OpenWindowAction) {
        if !activateExistingWindow() {
            openWindow(id: "main")
            DispatchQueue.main.async {
                _ = activateExistingWindow()
            }
        }
    }
}

struct MainWindowIdentifierView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWindow(for: view)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = MainWindowPresenter.identifier
            window.isReleasedWhenClosed = false
        }
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if !model.activeTasks.isEmpty {
                Text("\(Int(overallProgress * 100))%")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
        .onReceive(NotificationCenter.default.publisher(for: .showBilidownMainWindow)) { _ in
            MainWindowPresenter.show(using: openWindow)
        }
    }

    private var symbol: String {
        if !model.isLoggedIn { return "person.crop.circle.badge.xmark" }
        return model.activeTasks.isEmpty ? "checkmark.circle" : "arrow.down.circle.fill"
    }

    private var accessibilityText: String {
        if !model.isLoggedIn { return "Bilidown 未登录" }
        if model.activeTasks.isEmpty { return "Bilidown 已登录，当前没有下载任务" }
        return "Bilidown 正在下载 \(model.activeTasks.count) 个任务，进度 \(Int(overallProgress * 100))%"
    }

    private var overallProgress: Double {
        guard !model.activeTasks.isEmpty else { return 0 }
        return model.activeTasks.map(\.displayProgress).reduce(0, +) / Double(model.activeTasks.count)
    }
}

struct MenuBarStatusView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconProvider.image)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bilidown").font(.headline)
                    Text(loginDescription)
                        .font(.caption).foregroundStyle(model.isLoggedIn ? .green : .secondary)
                }
                Spacer()
            }

            Divider()

            if model.activeTasks.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("当前没有下载任务")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("正在下载 \(model.activeTasks.count) 项")
                        .font(.subheadline).fontWeight(.semibold)
                    ForEach(model.activeTasks.prefix(5)) { task in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(model.taskTitles[task.id] ?? "任务 #\(task.id)")
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(task.displayProgress * 100))%")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            ProgressView(value: task.displayProgress)
                            Text(task.progressLabel)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("显示 Bilidown") {
                    MainWindowPresenter.show(using: openWindow)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var loginDescription: String {
        guard model.isLoggedIn else { return "未登录" }
        if let profile = model.userProfile { return "已登录 · \(profile.name)" }
        return "已登录"
    }
}

private extension ActiveTask {
    var displayProgress: Double {
        if status == "waiting" { return 0 }
        if mergeProgress > 0 { return max(0, min(mergeProgress, 1)) }
        if videoProgress > 0 { return max(0, min(videoProgress, 1)) }
        return max(0, min(audioProgress, 1))
    }

    var progressLabel: String {
        if status == "waiting" { return "等待下载" }
        if mergeProgress > 0 { return "正在合并" }
        if videoProgress > 0 { return "正在下载视频" }
        return "正在下载音频"
    }
}
