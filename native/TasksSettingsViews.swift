import AppKit
import AVKit
import Combine
import CoreMedia
import SwiftUI

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskRecord] = []
    @Published var active: [Int: ActiveTask] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var search = ""
    @Published var category: TaskCategory = .downloading
    @Published var deleteCandidate: TaskRecord?
    @Published var playerURL: URL?
    private var didChooseInitialCategory = false

    func refresh() async {
        do {
            async let records: [TaskRecord] = APIClient.shared.get(
                "getTaskList",
                query: [URLQueryItem(name: "page", value: "0"), URLQueryItem(name: "pageSize", value: "360")]
            )
            async let running: [ActiveTask] = APIClient.shared.get("getActiveTask")
            let (taskRecords, activeTasks) = try await (records, running)
            tasks = taskRecords
            active = Dictionary(uniqueKeysWithValues: activeTasks.map { ($0.id, $0) })
            if !didChooseInitialCategory {
                category = taskRecords.contains(where: { $0.status != "done" }) ? .downloading : .completed
                didChooseInitialCategory = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPolling() async {
        isLoading = true
        await refresh()
        isLoading = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            await refresh()
        }
    }

    func delete(_ task: TaskRecord) async {
        do {
            _ = try await APIClient.shared.command(
                "deleteTask",
                query: [URLQueryItem(name: "id", value: String(task.id))]
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reveal(_ task: TaskRecord) {
        let url = task.outputURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if FileManager.default.fileExists(atPath: task.folder) {
            NSWorkspace.shared.open(URL(fileURLWithPath: task.folder, isDirectory: true))
        } else {
            errorMessage = "文件或下载目录不存在"
        }
    }

    func progress(for task: TaskRecord) -> (value: Double, label: String)? {
        guard let active = active[task.id], task.status == "running" || task.status == "waiting" else { return nil }
        if task.status == "waiting" { return (0, "等待下载") }
        if active.mergeProgress > 0 { return (active.mergeProgress, "正在合并") }
        if active.videoProgress > 0 { return (active.videoProgress, "正在下载视频") }
        return (active.audioProgress, "正在下载音频")
    }
}

struct TasksView: View {
    @StateObject private var model = TasksViewModel()

    private var filteredTasks: [TaskRecord] {
        let categoryTasks = model.tasks.filter {
            model.category == .completed ? $0.status == "done" : $0.status != "done"
        }
        guard !model.search.isEmpty else { return categoryTasks }
        return categoryTasks.filter {
            $0.title.localizedCaseInsensitiveContains(model.search)
            || $0.owner.localizedCaseInsensitiveContains(model.search)
            || $0.bvid.localizedCaseInsensitiveContains(model.search)
        }
    }

    private var downloadingCount: Int { model.tasks.lazy.filter { $0.status != "done" }.count }
    private var completedCount: Int { model.tasks.lazy.filter { $0.status == "done" }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("任务分类", selection: $model.category) {
                    Text("下载中 \(downloadingCount)").tag(TaskCategory.downloading)
                    Text("已完成 \(completedCount)").tag(TaskCategory.completed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            Group {
            if model.isLoading && model.tasks.isEmpty {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("正在读取下载任务…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.search.isEmpty ? "arrow.down.circle" : "magnifyingglass")
                        .font(.system(size: 46)).foregroundStyle(.secondary)
                    Text(model.search.isEmpty
                         ? (model.category == .completed ? "还没有已完成任务" : "当前没有下载任务")
                         : "没有匹配的任务")
                        .font(.title3).fontWeight(.semibold)
                    Text(model.search.isEmpty
                         ? (model.category == .completed ? "下载完成的内容会显示在这里" : "新建任务后可在这里查看进度")
                         : "请尝试其他关键词")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTasks) { task in
                            TaskRow(
                                task: task,
                                progress: model.progress(for: task),
                                onPlay: {
                                    guard FileManager.default.fileExists(atPath: task.outputURL.path) else {
                                        model.errorMessage = "下载文件不存在"
                                        return
                                    }
                                    model.playerURL = task.outputURL
                                },
                                onReveal: { model.reveal(task) },
                                onDelete: { model.deleteCandidate = task }
                            )
                        }
                    }
                    .padding(18)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
            }
        }
        .navigationTitle("任务列表")
        .searchable(text: $model.search, placement: .toolbar, prompt: "搜索任务")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.refresh() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await model.startPolling() }
        .sheet(item: Binding(
            get: { model.playerURL.map(IdentifiedURL.init) },
            set: { model.playerURL = $0?.url }
        )) { item in
            PlayerView(url: item.url)
        }
        .alert("删除任务", isPresented: Binding(
            get: { model.deleteCandidate != nil },
            set: { if !$0 { model.deleteCandidate = nil } }
        )) {
            Button("取消", role: .cancel) { model.deleteCandidate = nil }
            Button("删除文件和记录", role: .destructive) {
                guard let task = model.deleteCandidate else { return }
                model.deleteCandidate = nil
                Task { await model.delete(task) }
            }
        } message: {
            Text("此操作会删除已下载的文件，无法撤销。")
        }
        .alert("任务操作失败", isPresented: Binding(
            get: { model.errorMessage != nil && model.deleteCandidate == nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
    }
}

struct TaskRow: View {
    let task: TaskRecord
    let progress: (value: Double, label: String)?
    let onPlay: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(url: task.cover)
                .frame(width: 112, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: task.downloadType == "audio" ? "waveform" : "play.fill")
                        .font(.caption2).padding(5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .padding(5)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).fontWeight(.medium).lineLimit(2)
                HStack(spacing: 10) {
                    Text(task.owner)
                    Text(qualityNames[task.format] ?? String(task.format))
                    Text(durationText(task.duration))
                    StatusLabel(status: task.status)
                }
                .font(.caption).foregroundStyle(.secondary)

                if let progress {
                    HStack(spacing: 10) {
                        ProgressView(value: max(0, min(progress.value, 1)))
                        Text("\(progress.label) \(Int(progress.value * 100))%")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                    }
                } else {
                    Text(task.folder).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 5) {
                if task.status == "done" {
                    Button(action: onPlay) { Image(systemName: "play.circle") }
                        .help("在 Bilidown 中播放")
                    Button(action: onReveal) { Image(systemName: "folder") }
                        .help("在 Finder 中显示")
                }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("删除任务")
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.55)) }
    }
}

struct StatusLabel: View {
    let status: String

    var body: some View {
        Text(title)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch status {
        case "done": return "已完成"
        case "running": return "下载中"
        case "waiting": return "等待中"
        case "error": return "失败"
        default: return status
        }
    }

    private var color: Color {
        switch status {
        case "done": return .green
        case "running": return .blue
        case "waiting": return .orange
        case "error": return .red
        default: return .secondary
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    let url: URL
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPreparing = true
    @Published private(set) var errorMessage: String?
    private var preparedURL: URL?
    private var preparationTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    func prepare() {
        guard preparationTask == nil else { return }
        preparationTask = Task {
            do {
                let originalURL = url
                let playbackURL = try await Task.detached(priority: .userInitiated) {
                    try await PreviewMediaPreparer.prepare(url: originalURL)
                }.value
                guard !Task.isCancelled else {
                    if playbackURL != originalURL { try? FileManager.default.removeItem(at: playbackURL) }
                    return
                }

                preparedURL = playbackURL == originalURL ? nil : playbackURL
                let player = AVPlayer(url: playbackURL)
                self.player = player
                isPreparing = false
                player.play()
            } catch {
                isPreparing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        preparationTask?.cancel()
        preparationTask = nil
        player?.pause()
        player = nil
        if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
        preparedURL = nil
    }
}

private enum PreviewMediaPreparer {
    private static let hev1Subtype: FourCharCode = 0x68657631

    static func prepare(url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return url
        }
        let descriptions = try await videoTrack.load(.formatDescriptions)
        guard descriptions.contains(where: { CMFormatDescriptionGetMediaSubType($0) == hev1Subtype }) else {
            return url
        }
        return try makeAppleCompatibleCopy(of: url)
    }

    private static func makeAppleCompatibleCopy(of sourceURL: URL) throws -> URL {
        guard let ffmpegURL = locateFFmpeg() else {
            throw PreviewPreparationError.ffmpegMissing
        }

        let fileManager = FileManager.default
        let previewDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BilidownPreview", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let outputURL = previewDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let errors = Pipe()
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-nostdin", "-v", "error", "-y",
            "-i", sourceURL.path,
            "-map", "0:v:0", "-map", "0:a?",
            "-sn", "-dn", "-c", "copy",
            "-tag:v", "hvc1", "-movflags", "+faststart",
            outputURL.path
        ]
        process.standardOutput = Pipe()
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw PreviewPreparationError.failed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let detail = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? fileManager.removeItem(at: outputURL)
            throw PreviewPreparationError.failed(detail)
        }
        return outputURL
    }

    private static func locateFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}

private enum PreviewPreparationError: LocalizedError {
    case ffmpegMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return "找不到 FFmpeg，无法准备 HEVC 兼容预览"
        case .failed(let detail):
            return detail.isEmpty ? "无法准备这个视频的兼容预览" : "兼容预览准备失败：\(detail)"
        }
    }
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlayerViewModel

    init(url: URL) {
        _model = StateObject(wrappedValue: PlayerViewModel(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player = model.player {
                    NativePlayerView(player: player)
                } else if model.isPreparing {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("正在准备兼容预览…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("无法预览视频").font(.headline)
                        Text(model.errorMessage ?? "未知错误")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    .padding()
                }
            }
            HStack {
                Text(model.url.lastPathComponent)
                    .lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { model.prepare() }
        .onDisappear { model.stop() }
    }
}

/// Uses AVKit's AppKit view directly. SwiftUI's `VideoPlayer` currently crashes
/// while instantiating `_AVKit_SwiftUI` metadata on macOS 27, before playback
/// begins. Keeping the native AVPlayerView avoids that framework path while
/// retaining the standard macOS playback controls and full-screen support.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var downloadFolder = ""
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var confirmLogout = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fields: [String: String] = try await APIClient.shared.get("getFields")
            downloadFolder = fields["download_folder"] ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择下载目录"
        panel.message = "请选择 Bilidown 保存视频和音频的文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: downloadFolder) {
            panel.directoryURL = URL(fileURLWithPath: downloadFolder, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url { downloadFolder = url.path }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            message = try await APIClient.shared.postCommand(
                "saveFields",
                body: [["download_folder", downloadFolder]]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async -> Bool {
        do {
            _ = try await APIClient.shared.command("logout")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = SettingsViewModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("外观").font(.title2).fontWeight(.bold)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("界面外观", systemImage: "circle.lefthalf.filled")
                            .font(.headline)
                        Text("选择后会立即应用，并在下次启动时继续使用。")
                            .font(.callout).foregroundStyle(.secondary)
                        Picker("界面外观", selection: $appearanceMode) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 420)
                    }
                }

                Text("下载").font(.title2).fontWeight(.bold)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("下载目录", systemImage: "folder")
                            .font(.headline)
                        Text("新建任务会保存到这个文件夹。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            TextField("下载目录", text: $model.downloadFolder)
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") { model.chooseFolder() }
                            Button {
                                Task { await model.save() }
                            } label: {
                                if model.isSaving { ProgressView().controlSize(.small) }
                                else { Text("保存") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                model.downloadFolder.isEmpty
                                || model.isSaving
                            )
                        }
                    }
                }

                Text("账户与应用").font(.title2).fontWeight(.bold)
                Card {
                    VStack(spacing: 0) {
                        HStack {
                            Label("哔哩哔哩账户", systemImage: "person.crop.circle")
                            Spacer()
                            Text("已登录").foregroundStyle(.green)
                            Button("退出登录", role: .destructive) { model.confirmLogout = true }
                        }
                        .padding(.vertical, 4)
                        Divider().padding(.vertical, 14)
                        HStack {
                            Label("应用数据", systemImage: "externaldrive")
                            Spacer()
                            Text("~/Library/Application Support/Bilidown")
                                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            Button("显示") {
                                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("Bilidown", isDirectory: true)
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Bilidown \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.0") · SwiftUI 原生版")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(26)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("设置")
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .onChange(of: appearanceMode) { newValue in
            AppearanceController.apply(rawValue: newValue)
        }
        .task { await model.load() }
        .alert("设置", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(model.message ?? "") }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .alert("退出登录", isPresented: $model.confirmLogout) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                Task { if await model.logout() { appModel.setLoggedIn(false) } }
            }
        } message: {
            Text("退出后需要重新扫码才能解析和下载视频。")
        }
    }
}
