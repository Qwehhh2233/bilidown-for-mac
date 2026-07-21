import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

}

struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: Value?
}

struct EmptyPayload: Codable {}

struct UserProfile: Codable, Hashable {
    let mid: Int
    let name: String
    let face: String
}

struct Dimension: Codable, Hashable {
    let width: Int
    let height: Int
    let rotate: Int
}

struct Owner: Codable, Hashable {
    let mid: Int
    let name: String
    let face: String
}

struct Staff: Codable, Hashable {
    let mid: Int
    let title: String
    let name: String
    let face: String
}

struct VideoPage: Codable, Hashable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
    let dimension: Dimension
}

struct VideoEpisode: Codable, Hashable {
    let title: String
    let pages: [VideoPage]
    let bvid: String
}

struct VideoSection: Codable, Hashable {
    let title: String
    let episodes: [VideoEpisode]
}

struct UGCSeason: Codable, Hashable {
    let sections: [VideoSection]?
    let title: String
}

struct VideoInfo: Codable {
    let title: String
    let desc: String
    let pubdate: Int
    let pic: String
    let duration: Int
    let bvid: String
    let pages: [VideoPage]
    let owner: Owner
    let dimension: Dimension
    let staff: [Staff]?
    let ugcSeason: UGCSeason

    enum CodingKeys: String, CodingKey {
        case title, desc, pubdate, pic, duration, bvid, pages, owner, dimension, staff
        case ugcSeason = "ugc_season"
    }
}

struct SeasonArea: Codable, Hashable {
    let id: Int
    let name: String
}

struct SeasonEpisode: Codable, Hashable {
    let bvid: String
    let cid: Int
    let cover: String
    let dimension: Dimension
    let duration: Int
    let epId: Int
    let longTitle: String
    let pubTime: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case bvid, cid, cover, dimension, duration, title
        case epId = "ep_id"
        case longTitle = "long_title"
        case pubTime = "pub_time"
    }
}

struct SeasonSection: Codable, Hashable {
    let title: String
    let episodes: [SeasonEpisode]
}

struct SeasonNewEpisode: Codable {
    let desc: String
    let isNew: Int

    enum CodingKeys: String, CodingKey {
        case desc
        case isNew = "is_new"
    }
}

struct SeasonInfo: Codable {
    let actors: String
    let areas: [SeasonArea]
    let cover: String
    let evaluate: String
    let title: String
    let total: Int
    let episodes: [SeasonEpisode]
    let newEpisode: SeasonNewEpisode
    let section: [SeasonSection]?

    enum CodingKeys: String, CodingKey {
        case actors, areas, cover, evaluate, title, total, episodes, section
        case newEpisode = "new_ep"
    }
}

struct FavoriteUGC: Codable {
    let firstCid: Int

    enum CodingKeys: String, CodingKey {
        case firstCid = "first_cid"
    }
}

struct FavoriteItem: Codable {
    let title: String
    let cover: String
    let intro: String
    let duration: Int
    let upper: Owner
    let pubtime: Int
    let bvid: String
    let ugc: FavoriteUGC
}

struct MediaStream: Codable, Hashable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]
    let bandwidth: Int
    let mimeType: String
    let codecs: String
    let width: Int
    let height: Int
    let frameRate: String
    let codecid: Int
}

struct FlacStream: Codable {
    let audio: MediaStream
}

struct DashInfo: Codable {
    let duration: Int
    let video: [MediaStream]
    let audio: [MediaStream]
    let flac: FlacStream?
}

struct PlayInfo: Codable {
    let acceptQuality: [Int]
    let dash: DashInfo?

    enum CodingKeys: String, CodingKey {
        case acceptQuality = "accept_quality"
        case dash
    }
}

struct NativePage: Identifiable, Hashable {
    let bvid: String
    let cid: Int
    let number: Int
    let title: String
    let badge: String
    let duration: Int

    var id: String { "\(bvid)-\(cid)" }
}

struct NativeSection: Identifiable, Hashable {
    let title: String
    let pages: [NativePage]

    var id: String { title + pages.map(\.id).joined() }
}

struct VideoPresentation {
    enum Kind { case video, season, favorite }

    let kind: Kind
    let title: String
    let description: String
    let cover: String
    let publishDate: String
    let duration: Int
    let owner: Owner
    let staff: [Staff]
    let dimension: Dimension
    let status: String
    let sections: [NativeSection]
    let targetURL: URL?

    var displayOwner: String {
        staff.first?.name ?? owner.name
    }
}

struct TaskCreateRequest: Encodable {
    let bvid: String
    let cid: Int
    let format: Int
    let title: String
    let owner: String
    let cover: String
    let audio: String
    let video: String
    let duration: Int
    let downloadType: String
}

struct TaskRecord: Codable, Identifiable, Hashable {
    let bvid: String
    let cid: Int
    let format: Int
    let title: String
    let owner: String
    let cover: String
    let status: String
    let folder: String
    let audio: String
    let video: String
    let duration: Int
    let downloadType: String
    let fileName: String?
    let id: Int
    let createAt: String

    var outputURL: URL {
        if let fileName, !fileName.isEmpty {
            return URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent(fileName)
        }
        let encodedID = Data(String(id).utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let ext = downloadType == "audio" ? "m4a" : "mp4"
        return URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent("\(title) \(encodedID).\(ext)")
    }
}

struct ActiveTask: Codable, Identifiable {
    let id: Int
    let status: String
    let audioProgress: Double
    let videoProgress: Double
    let mergeProgress: Double
}

enum TaskCategory: String, CaseIterable, Identifiable {
    case downloading = "下载中"
    case completed = "已完成"

    var id: String { rawValue }
}

struct QRInfo: Codable {
    let key: String
    let image: String
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case parse = "视频解析"
    case tasks = "任务列表"
    case settings = "设置"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .parse: return "link.badge.plus"
        case .tasks: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

enum DownloadType: String, CaseIterable, Identifiable {
    case merge
    case video
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "音视频合并"
        case .video: return "仅视频"
        case .audio: return "仅音频"
        }
    }
}

let qualityNames: [Int: String] = [
    127: "超高清 8K", 126: "杜比视界", 125: "真彩 HDR", 120: "超清 4K",
    116: "高清 1080P60", 112: "高清 1080P+", 80: "高清 1080P",
    74: "高清 720P60", 64: "高清 720P", 32: "清晰 480P",
    16: "流畅 360P", 6: "极速 240P"
]

func secureRemoteURL(_ value: String) -> URL? {
    var text = value
    if text.hasPrefix("//") { text = "https:" + text }
    if text.lowercased().hasPrefix("http://") {
        text = "https://" + text.dropFirst("http://".count)
    }
    return URL(string: text)
}

func durationText(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remaining = seconds % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
    return String(format: "%d:%02d", minutes, remaining)
}
