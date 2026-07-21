import AppKit
import Combine
import SwiftUI

@MainActor
final class RootViewState: ObservableObject {
    @Published var selection: SidebarItem? = .parse
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var state = RootViewState()

    let appDelegate: NativeAppDelegate

    var body: some View {
        Group {
            if let error = appModel.startupError {
                StartupErrorView(message: error)
            } else if !appModel.backendReady {
                StartupView(message: appModel.startupMessage)
            } else if !appModel.isLoggedIn {
                LoginView()
            } else {
                NavigationSplitView {
                    List(SidebarItem.allCases, selection: $state.selection) { item in
                        Label(item.rawValue, systemImage: item.symbol)
                            .tag(item)
                            .padding(.vertical, 4)
                    }
                    .navigationTitle("Bilidown")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 10) {
                            UserAvatarView(url: appModel.userProfile?.face ?? "")
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: "ID：" + (appModel.userProfile?.name ?? "加载中…"))
                                    .font(.caption).fontWeight(.semibold).lineLimit(1)
                                Text(verbatim: appModel.userProfile.map { "UID：" + String($0.mid) } ?? "UID：—")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                    }
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selection ?? .parse {
        case .parse:
            ParseView(onTasksCreated: { state.selection = .tasks })
        case .tasks:
            TasksView()
        case .settings:
            SettingsView()
        }
    }
}

struct UserAvatarView: View {
    let url: String

    var body: some View {
        AsyncImage(url: secureRemoteURL(url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.14)
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(Circle())
        .overlay { Circle().stroke(.separator.opacity(0.7)) }
    }
}

struct StartupView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: AppIconProvider.image)
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            ProgressView().controlSize(.large)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Bilidown 无法启动").font(.title2).fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("退出应用") { NSApp.terminate(nil) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var qrImage: NSImage?
    @Published var qrKey = ""
    @Published var status = "正在生成登录二维码…"
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadQR() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let info: QRInfo = try await APIClient.shared.get("getQRInfo")
            qrKey = info.key
            qrImage = Self.decodeDataImage(info.image)
            status = "请使用哔哩哔哩 App 扫码登录"
        } catch {
            errorMessage = error.localizedDescription
            status = "二维码加载失败"
        }
    }

    func pollLogin() async -> Bool {
        guard !qrKey.isEmpty else { return false }
        do {
            let response: APIEnvelope<EmptyPayload> = try await APIClient.shared.envelope(
                "getQRStatus",
                query: [URLQueryItem(name: "key", value: qrKey)]
            )
            if response.success {
                status = "登录成功"
                return true
            }
            status = response.message
        } catch {
            status = error.localizedDescription
        }
        return false
    }

    private static func decodeDataImage(_ value: String) -> NSImage? {
        guard let comma = value.firstIndex(of: ","),
              let data = Data(base64Encoded: String(value[value.index(after: comma)...])) else { return nil }
        return NSImage(data: data)
    }
}

struct LoginView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = LoginViewModel()

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 14) {
                Image(nsImage: AppIconProvider.image)
                    .resizable()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("登录 Bilidown").font(.title).fontWeight(.bold)
                    Text("登录后即可解析并下载哔哩哔哩视频")
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if let image = model.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 268, height: 268)
                        .overlay { ProgressView().controlSize(.large) }
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)

            Text(model.status)
                .foregroundStyle(model.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))

            Button("刷新二维码") { Task { await model.loadQR() } }
                .disabled(model.isLoading)
        }
        .padding(50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await model.loadQR() }
        .task(id: model.qrKey) {
            guard !model.qrKey.isEmpty else { return }
            while !Task.isCancelled {
                if await model.pollLogin() {
                    appModel.setLoggedIn(true)
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

struct ArtworkView: View {
    let url: String

    var body: some View {
        AsyncImage(url: secureRemoteURL(url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "photo")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            default:
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                }
            }
        }
        .clipped()
    }
}
