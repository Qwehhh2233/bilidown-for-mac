import Combine
import SwiftUI

private enum ParsedIdentifier {
    case video(String)
    case episode(Int)
    case season(Int)
    case favorite(Int)
}

@MainActor
final class ParseViewModel: ObservableObject {
    @Published var input = ""
    @Published var result: VideoPresentation?
    @Published var selectedSection = 0
    @Published var selectedPages: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDownloadSheet = false

    func loadRecommendationIfNeeded() async {
        guard result == nil, !isLoading else { return }
        do {
            let ids: [String] = try await APIClient.shared.get("getPopularVideos")
            if let id = ids.randomElement() { await load(.video(id), updateInput: false) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func parseInput() async {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            errorMessage = "请输入视频链接或 BV/EP/SS 号"
            return
        }

        do {
            var resolved = source
            if source.lowercased().hasPrefix("https://b23.tv/") {
                resolved = try await APIClient.shared.get(
                    "getRedirectedLocation",
                    query: [URLQueryItem(name: "url", value: source)]
                )
            }
            guard let identifier = Self.identifier(from: resolved) else {
                throw APIError.server("无法识别该链接，请输入 BV、EP、SS 号或对应链接")
            }
            await load(identifier, updateInput: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ identifier: ParsedIdentifier, updateInput: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let presentation: VideoPresentation
            switch identifier {
            case .video(let bvid):
                let info: VideoInfo = try await APIClient.shared.get(
                    "getVideoInfo",
                    query: [URLQueryItem(name: "bvid", value: bvid)]
                )
                presentation = Self.presentation(from: info)
                if updateInput { input = bvid }
            case .episode(let id):
                let info: SeasonInfo = try await APIClient.shared.get(
                    "getSeasonInfo",
                    query: [URLQueryItem(name: "epid", value: String(id))]
                )
                presentation = Self.presentation(from: info, target: "ep\(id)")
                if updateInput { input = "ep\(id)" }
            case .season(let id):
                let info: SeasonInfo = try await APIClient.shared.get(
                    "getSeasonInfo",
                    query: [URLQueryItem(name: "ssid", value: String(id))]
                )
                presentation = Self.presentation(from: info, target: "ss\(id)")
                if updateInput { input = "ss\(id)" }
            case .favorite(let id):
                let items: [FavoriteItem] = try await APIClient.shared.get(
                    "getFavList",
                    query: [URLQueryItem(name: "mediaId", value: String(id))]
                )
                guard let first = items.first else { throw APIError.server("收藏夹中没有视频") }
                presentation = Self.presentation(from: items, first: first)
            }

            result = presentation
            selectedSection = 0
            selectedPages = Set(presentation.sections.first?.pages.prefix(1).map(\.id) ?? [])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var currentPages: [NativePage] {
        guard let result, result.sections.indices.contains(selectedSection) else { return [] }
        return result.sections[selectedSection].pages
    }

    func toggle(_ page: NativePage) {
        if selectedPages.contains(page.id) { selectedPages.remove(page.id) }
        else { selectedPages.insert(page.id) }
    }

    private static func identifier(from source: String) -> ParsedIdentifier? {
        if let range = source.range(of: "BV1[A-Za-z0-9]+", options: .regularExpression) {
            return .video(String(source[range]))
        }
        if let range = source.range(of: "(?:ep|ss)[0-9]+", options: .regularExpression) {
            let token = String(source[range])
            let value = Int(token.dropFirst(2)) ?? 0
            return token.hasPrefix("ep") ? .episode(value) : .season(value)
        }
        if let url = URLComponents(string: source),
           let fid = url.queryItems?.first(where: { $0.name == "fid" })?.value,
           let id = Int(fid) {
            return .favorite(id)
        }
        if let range = source.range(of: "ml[0-9]+", options: .regularExpression),
           let id = Int(source[range].dropFirst(2)) {
            return .favorite(id)
        }
        return nil
    }

    private static func presentation(from info: VideoInfo) -> VideoPresentation {
        let sections: [NativeSection]
        if let sourceSections = info.ugcSeason.sections, !sourceSections.isEmpty {
            sections = sourceSections.map { section in
                var index = 0
                let pages = section.episodes.flatMap { episode in
                    episode.pages.map { page in
                        index += 1
                        return NativePage(
                            bvid: episode.bvid, cid: page.cid, number: index,
                            title: episode.title, badge: String(index), duration: page.duration
                        )
                    }
                }
                return NativeSection(title: section.title, pages: pages)
            }
        } else {
            sections = [NativeSection(title: "正片", pages: info.pages.map { page in
                NativePage(
                    bvid: info.bvid, cid: page.cid, number: page.page,
                    title: page.part, badge: String(page.page), duration: page.duration
                )
            })]
        }

        return VideoPresentation(
            kind: .video,
            title: info.title,
            description: info.desc,
            cover: info.pic,
            publishDate: Date(timeIntervalSince1970: TimeInterval(info.pubdate)).formatted(date: .numeric, time: .shortened),
            duration: info.duration,
            owner: info.owner,
            staff: info.staff ?? [],
            dimension: info.dimension,
            status: "",
            sections: sections,
            targetURL: URL(string: "https://www.bilibili.com/video/\(info.bvid)")
        )
    }

    private static func presentation(from info: SeasonInfo, target: String) -> VideoPresentation {
        func page(_ episode: SeasonEpisode, index: Int) -> NativePage {
            let title = episode.longTitle.isEmpty
                ? (Int(episode.title) == nil ? episode.title : "第 \(episode.title) 集")
                : episode.longTitle
            return NativePage(
                bvid: episode.bvid, cid: episode.cid, number: index + 1,
                title: title, badge: episode.title, duration: episode.duration
            )
        }

        var sections = [NativeSection(
            title: "正片",
            pages: info.episodes.enumerated().map { page($0.element, index: $0.offset) }
        )]
        sections += (info.section ?? []).map { section in
            NativeSection(
                title: section.title,
                pages: section.episodes.enumerated().map { page($0.element, index: $0.offset) }
            )
        }

        return VideoPresentation(
            kind: .season,
            title: info.title,
            description: info.evaluate,
            cover: info.cover,
            publishDate: "",
            duration: info.episodes.reduce(0) { $0 + $1.duration },
            owner: Owner(mid: 0, name: info.actors, face: ""),
            staff: [],
            dimension: info.episodes.first?.dimension ?? Dimension(width: 0, height: 0, rotate: 0),
            status: info.newEpisode.desc,
            sections: sections,
            targetURL: URL(string: "https://www.bilibili.com/bangumi/play/\(target)")
        )
    }

    private static func presentation(from items: [FavoriteItem], first: FavoriteItem) -> VideoPresentation {
        let pages = items.enumerated().map { index, item in
            NativePage(
                bvid: item.bvid, cid: item.ugc.firstCid, number: index + 1,
                title: item.title, badge: String(index + 1), duration: item.duration
            )
        }
        return VideoPresentation(
            kind: .favorite,
            title: first.title,
            description: first.intro,
            cover: first.cover,
            publishDate: Date(timeIntervalSince1970: TimeInterval(first.pubtime)).formatted(date: .numeric, time: .shortened),
            duration: first.duration,
            owner: first.upper,
            staff: [],
            dimension: Dimension(width: 0, height: 0, rotate: 0),
            status: "",
            sections: [NativeSection(title: "收藏夹", pages: pages)],
            targetURL: URL(string: "https://www.bilibili.com/video/\(first.bvid)")
        )
    }
}

struct ParseView: View {
    @StateObject private var model = ParseViewModel()
    @FocusState private var isInputFocused: Bool

    let onTasksCreated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.isLoading && model.result == nil {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("正在读取视频信息…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let result = model.result {
                    resultView(result)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 46)).foregroundStyle(.secondary)
                        Text("输入视频链接开始解析").font(.title3).fontWeight(.semibold)
                        Text("支持 BV、EP、SS、b23.tv 和收藏夹链接")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("视频解析")
        .task { await model.loadRecommendationIfNeeded() }
        .alert("解析失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $model.showDownloadSheet) {
            if let result = model.result {
                DownloadSheet(
                    presentation: result,
                    pages: model.currentPages.filter { model.selectedPages.contains($0.id) },
                    onCreated: {
                        model.showDownloadSheet = false
                        onTasksCreated()
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("粘贴视频链接", systemImage: "link.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("支持 BV、EP、SS、b23.tv 和收藏夹链接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isInputFocused ? Color.accentColor : .secondary)

                    TextField("粘贴 B 站链接或输入 BV/EP/SS 号", text: $model.input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .focused($isInputFocused)
                        .onSubmit { Task { await model.parseInput() } }

                    if !model.input.isEmpty {
                        Button { model.input = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清空输入")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            Color.accentColor.opacity(isInputFocused ? 1 : 0.5),
                            lineWidth: isInputFocused ? 2 : 1.25
                        )
                }
                .shadow(
                    color: Color.accentColor.opacity(isInputFocused ? 0.2 : 0.08),
                    radius: isInputFocused ? 7 : 3,
                    y: 1
                )

                Button {
                    Task { await model.parseInput() }
                } label: {
                    Label("解析视频", systemImage: "sparkle.magnifyingglass")
                        .frame(minWidth: 78)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isLoading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .background(.bar)
    }

    private func resultView(_ result: VideoPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    HStack(alignment: .top, spacing: 20) {
                        ArtworkView(url: result.cover)
                            .frame(width: 320, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                if !result.owner.face.isEmpty {
                                    ArtworkView(url: result.owner.face)
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2) }
                                        .padding(10)
                                }
                            }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(result.title).font(.title2).fontWeight(.bold).textSelection(.enabled)
                                Spacer()
                                if let target = result.targetURL {
                                    Link(destination: target) { Image(systemName: "arrow.up.right.square") }
                                }
                            }
                            Label(result.displayOwner, systemImage: "person.crop.circle")
                            HStack(spacing: 18) {
                                if result.dimension.width > 0 {
                                    Label("\(result.dimension.width) × \(result.dimension.height)", systemImage: "rectangle.inset.filled")
                                }
                                Label(durationText(result.duration), systemImage: "clock")
                                if !result.publishDate.isEmpty {
                                    Label(result.publishDate, systemImage: "calendar")
                                }
                            }
                            .font(.callout).foregroundStyle(.secondary)
                            if !result.status.isEmpty {
                                Text(result.status).font(.callout).foregroundStyle(.secondary)
                            }
                            Text(result.description.isEmpty ? "暂无简介" : result.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("选择分集").font(.headline)
                            Spacer()
                            Text("已选择 \(model.selectedPages.count) 项")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("全部选择") {
                                model.selectedPages = Set(model.currentPages.map(\.id))
                            }
                            Button("清除") { model.selectedPages.removeAll() }
                        }

                        if result.sections.count > 1 {
                            Picker("分区", selection: $model.selectedSection) {
                                ForEach(Array(result.sections.enumerated()), id: \.offset) { index, section in
                                    Text(section.title).tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: model.selectedSection) { _ in model.selectedPages.removeAll() }
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(model.currentPages) { page in
                                Button { model.toggle(page) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: model.selectedPages.contains(page.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(model.selectedPages.contains(page.id) ? .blue : .secondary)
                                        Text(page.badge).font(.caption).foregroundStyle(.secondary).frame(width: 34)
                                        Text(page.title).lineLimit(1)
                                        Spacer()
                                        Text(durationText(page.duration)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                model.showDownloadSheet = true
                            } label: {
                                Label("准备下载", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.selectedPages.isEmpty)
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

struct DownloadChoice: Identifiable {
    let page: NativePage
    let playInfo: PlayInfo
    var selected = true
    var quality: Int

    var id: String { page.id }
    var qualities: [Int] {
        Array(Set(playInfo.dash?.video.map(\.id) ?? playInfo.acceptQuality)).sorted(by: >)
    }
}

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var choices: [DownloadChoice] = []
    @Published var loadingCurrent = 0
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var downloadType: DownloadType = .merge
    @Published var preferredCodec = 12
    @Published var preferHiRes = true

    let presentation: VideoPresentation
    let pages: [NativePage]

    init(presentation: VideoPresentation, pages: [NativePage]) {
        self.presentation = presentation
        self.pages = pages
    }

    func prepare() async {
        guard !isLoading, choices.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        for page in pages {
            do {
                let info: PlayInfo = try await APIClient.shared.get(
                    "getPlayInfo",
                    query: [
                        URLQueryItem(name: "bvid", value: page.bvid),
                        URLQueryItem(name: "cid", value: String(page.cid))
                    ]
                )
                guard let dash = info.dash else { throw APIError.server("没有可用的媒体流") }
                let quality = Set(dash.video.map(\.id)).max() ?? info.acceptQuality.first ?? 80
                choices.append(DownloadChoice(page: page, playInfo: info, quality: quality))
            } catch {
                errorMessage = "\(page.title)：\(error.localizedDescription)"
            }
            loadingCurrent += 1
        }
    }

    func createTasks() async -> Bool {
        let selected = choices.filter(\.selected)
        guard !selected.isEmpty else { return false }
        isCreating = true
        defer { isCreating = false }

        do {
            let requests = try selected.map { choice -> TaskCreateRequest in
                guard let dash = choice.playInfo.dash else { throw APIError.server("媒体信息不完整") }
                let codecs = [preferredCodec, 12, 7, 13].reduce(into: [Int]()) { result, value in
                    if !result.contains(value) { result.append(value) }
                }
                guard let video = codecs.lazy.compactMap({ code in
                    dash.video.first { $0.id == choice.quality && $0.codecid == code }
                }).first else { throw APIError.server("找不到所选清晰度的视频流") }
                guard let audio = preferHiRes ? (dash.flac?.audio ?? dash.audio.max(by: { $0.id < $1.id })) : dash.audio.max(by: { $0.id < $1.id }) else {
                    throw APIError.server("找不到音频流")
                }
                let owner = presentation.displayOwner.trimmingCharacters(in: .whitespacesAndNewlines)
                let quality = qualityNames[choice.quality] ?? "清晰度 \(choice.quality)"
                let titleParts = [
                    pages.count > 1 ? "[\(presentation.title)]" : "",
                    pages.count > 1 ? "[\(choice.page.badge)]" : "",
                    choice.page.title,
                    owner.isEmpty ? "" : "[\(owner)]",
                    "[\(quality)]",
                    "[\(durationText(dash.duration))]"
                ].filter { !$0.isEmpty }

                return TaskCreateRequest(
                    bvid: choice.page.bvid, cid: choice.page.cid, format: choice.quality,
                    title: titleParts.joined(separator: " "), owner: owner,
                    cover: presentation.cover, audio: audio.baseUrl, video: video.baseUrl,
                    duration: dash.duration, downloadType: downloadType.rawValue
                )
            }
            _ = try await APIClient.shared.postCommand("createTask", body: requests)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct DownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DownloadViewModel

    let onCreated: () -> Void

    init(presentation: VideoPresentation, pages: [NativePage], onCreated: @escaping () -> Void) {
        _model = StateObject(wrappedValue: DownloadViewModel(presentation: presentation, pages: pages))
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载选项").font(.title2).fontWeight(.bold)
                    Text(model.presentation.title).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).font(.title2).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()

            if model.isLoading {
                VStack(spacing: 15) {
                    ProgressView(value: Double(model.loadingCurrent), total: Double(max(model.pages.count, 1)))
                        .frame(width: 320)
                    Text("正在读取清晰度（\(model.loadingCurrent)/\(model.pages.count)）")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($model.choices) { $choice in
                            HStack(spacing: 12) {
                                Toggle("", isOn: $choice.selected).labelsHidden()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.page.title).lineLimit(1)
                                    Text(durationText(choice.page.duration)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("清晰度", selection: $choice.quality) {
                                    ForEach(choice.qualities, id: \.self) { quality in
                                        Text(qualityNames[quality] ?? String(quality)).tag(quality)
                                    }
                                }
                                .labelsHidden().frame(width: 170)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack(spacing: 14) {
                Picker("下载内容", selection: $model.downloadType) {
                    ForEach(DownloadType.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 190)
                Picker("视频编码", selection: $model.preferredCodec) {
                    Text("HEVC").tag(12)
                    Text("AVC").tag(7)
                    Text("AV1").tag(13)
                }
                .frame(width: 150)
                Toggle("优先 Hi-Res 音频", isOn: $model.preferHiRes)
                Spacer()
                Button("取消") { dismiss() }
                Button {
                    Task { if await model.createTasks() { onCreated() } }
                } label: {
                    if model.isCreating { ProgressView().controlSize(.small) }
                    else { Text("开始下载") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.isCreating || !model.choices.contains { $0.selected })
            }
            .padding(16)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .task { await model.prepare() }
        .alert("下载失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
    }
}
