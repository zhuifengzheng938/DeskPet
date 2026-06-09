import SwiftUI
import AppKit
import Observation

public enum DeskPetMain {
    @MainActor
    public static func run() {
        DeskPetApp.main()
    }
}

struct DeskPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var pet = PetModel()

    var body: some Scene {
        Window("DeskPet", id: "desk-pet") {
            DeskPetView(pet: pet)
                .frame(width: 248, height: 352)
                .background(WindowConfigurator())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DeskPet") {
                    pet.react(to: .greet)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var toggleObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        toggleObserver = DistributedNotificationCenter.default().addObserver(
            forName: .deskPetToggleRequested,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                DesktopPetWindowController.togglePetWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    deinit {
        if let toggleObserver {
            DistributedNotificationCenter.default().removeObserver(toggleObserver)
        }
    }
}

extension Notification.Name {
    static let deskPetToggleRequested = Notification.Name("DeskPetToggleRequested")
}

enum DesktopPetWindowController {
    @MainActor
    static func togglePetWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "DeskPet" }) ?? NSApp.windows.first else {
            return
        }

        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
            return
        }

        window.level = .floating
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@Observable
@MainActor
final class PetModel {
    var mood: PetMood = .curious
    var message = "我在这里。可以和我聊天，也可以让我帮你操作电脑。"
    var folderURL: URL?
    var hopCount = 0
    var isBlinking = false
    var sparkle = false
    var isChatOpen = false
    var chatInput = ""
    var activeAppStyle: ActiveAppStyle = .normal
    var activeAppName = ""
    var chatMessages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "你可以说：打开 Safari、截图、查看电量、打开下载、常显示程序坞、来一句哲学名言、推荐一首民谣。")
    ]

    @ObservationIgnored private var activeAppObserver: NSObjectProtocol?
    private var moodIndex = 0
    private var quoteIndex = 0
    private let moods: [PetMood] = [.curious, .happy, .focused, .playful, .sleepy]

    init() {
        startActiveAppMonitoring()
    }

    var folderTitle: String {
        folderURL?.lastPathComponent ?? "未选择文件夹"
    }

    var canOpenFolder: Bool {
        folderURL != nil
    }

    @MainActor
    func react(to action: PetAction) {
        switch action {
        case .tap:
            moodIndex = (moodIndex + 1) % moods.count
            mood = moods[moodIndex]
            message = mood.tapMessage
            hopCount += 1
            sparkle.toggle()
            blinkSoon()
        case .greet:
            mood = .happy
            message = "你好呀，我准备好陪你办公了。"
            hopCount += 1
            blinkSoon()
        case .chooseFolder:
            chooseFolder()
        case .openFolder:
            openFolder()
        case .toggleChat:
            isChatOpen.toggle()
            mood = .focused
            message = isChatOpen ? "我在听。说说你想让我做什么。" : "聊天先收起来，需要时再叫我。"
        case .philosophyQuote:
            expressPhilosophyQuote()
        case .dailyFolkSong:
            recommendDailyFolkSong()
        case .nudge:
            mood = .playful
            message = "嘿，我在。需要我帮你操作电脑吗？"
            hopCount += 1
            sparkle.toggle()
        }
    }

    func sendChat() {
        let trimmedInput = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        chatInput = ""
        chatMessages.append(ChatMessage(role: .user, text: trimmedInput))

        let response = ComputerAssistant.handle(trimmedInput)
        chatMessages.append(ChatMessage(role: .assistant, text: response.message))
        mood = response.succeeded ? .happy : .curious
        message = response.message
        hopCount += 1
        sparkle = response.succeeded
        blinkSoon()
    }

    private func expressPhilosophyQuote() {
        let quote = PhilosophyQuoteLibrary.next(after: quoteIndex)
        quoteIndex += 1
        mood = .focused
        message = quote.petExpression
        chatMessages.append(ChatMessage(role: .assistant, text: quote.chatText))
        hopCount += 1
        sparkle = true
        blinkSoon()
    }

    private func recommendDailyFolkSong() {
        let song = FolkSongLibrary.today()
        mood = .playful
        message = song.petExpression
        chatMessages.append(ChatMessage(role: .assistant, text: song.chatText))
        hopCount += 1
        sparkle = true
        blinkSoon()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择桌宠要打开的文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
            mood = .focused
            message = "记住了：\(url.lastPathComponent)。需要时我可以帮你打开它。"
            hopCount += 1
        }
    }

    private func openFolder() {
        guard let folderURL else {
            mood = .curious
            message = "先告诉我要打开哪个文件夹。"
            chooseFolder()
            return
        }

        NSWorkspace.shared.open(folderURL)
        mood = .happy
        message = "已经帮你打开 \(folderURL.lastPathComponent)。"
        hopCount += 1
        sparkle = true
    }

    private func blinkSoon() {
        isBlinking = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            isBlinking = false
        }
    }

    private func startActiveAppMonitoring() {
        updateActiveApp(NSWorkspace.shared.frontmostApplication)

        activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                self?.updateActiveApp(app)
            }
        }
    }

    private func updateActiveApp(_ app: NSRunningApplication?) {
        let bundleIdentifier = app?.bundleIdentifier ?? ""
        guard !bundleIdentifier.hasPrefix("com.local.DeskPet") else { return }

        let appName = app?.localizedName ?? ""
        let nextStyle = ActiveAppStyle.detect(bundleIdentifier: bundleIdentifier, appName: appName)
        guard nextStyle != activeAppStyle || appName != activeAppName else { return }

        activeAppStyle = nextStyle
        activeAppName = appName

        guard nextStyle != .normal else { return }

        mood = nextStyle.mood
    }
}

enum PetAction {
    case tap
    case greet
    case chooseFolder
    case openFolder
    case toggleChat
    case philosophyQuote
    case dailyFolkSong
    case nudge
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
}

enum ChatRole {
    case user
    case assistant
}

struct AssistantResponse {
    let message: String
    let succeeded: Bool
}

struct AppSize {
    let name: String
    let kilobytes: Int64
}

enum ActiveAppStyle: Equatable {
    case normal
    case coding
    case reading
    case music
    case chat
    case ai

    static func detect(bundleIdentifier: String, appName: String) -> ActiveAppStyle {
        let bundle = bundleIdentifier.lowercased()
        let name = appName.lowercased()

        if bundle.contains("vscode")
            || bundle.contains("visualstudiocode")
            || bundle.contains("com.microsoft.vscode")
            || bundle.contains("com.apple.dt.xcode")
            || bundle.contains("jetbrains")
            || name.contains("visual studio code")
            || name.contains("vscode")
            || name == "code"
            || name.contains("xcode")
            || name.contains("cursor")
            || name.contains("trae") {
            return .coding
        }

        if bundle.contains("wps")
            || bundle.contains("kingsoft")
            || name.contains("wps")
            || name.contains("writer")
            || name.contains("pages")
            || name.contains("preview")
            || name.contains("预览") {
            return .reading
        }

        if bundle.contains("qqmusic")
            || bundle.contains("music")
            || bundle.contains("spotify")
            || bundle.contains("netease")
            || name.contains("qq音乐")
            || name.contains("音乐")
            || name.contains("music")
            || name.contains("spotify")
            || name.contains("网易云音乐") {
            return .music
        }

        if bundle.contains("wechat")
            || bundle.contains("tencent.qq")
            || bundle.contains("telegram")
            || bundle.contains("discord")
            || bundle.contains("slack")
            || bundle.contains("lark")
            || bundle.contains("feishu")
            || bundle.contains("dingtalk")
            || bundle.contains("teams")
            || name.contains("微信")
            || name == "qq"
            || name.contains("telegram")
            || name.contains("discord")
            || name.contains("slack")
            || name.contains("飞书")
            || name.contains("lark")
            || name.contains("钉钉")
            || name.contains("teams") {
            return .chat
        }

        if bundle.contains("chatgpt")
            || bundle.contains("openai")
            || bundle.contains("claude")
            || bundle.contains("poe")
            || bundle.contains("gemini")
            || bundle.contains("perplexity")
            || bundle.contains("copilot")
            || name.contains("chatgpt")
            || name.contains("claude")
            || name.contains("poe")
            || name.contains("gemini")
            || name.contains("perplexity")
            || name.contains("copilot")
            || name.contains("通义")
            || name.contains("豆包")
            || name.contains("kimi") {
            return .ai
        }

        return .normal
    }

    var mood: PetMood {
        switch self {
        case .normal: .curious
        case .coding: .focused
        case .reading: .focused
        case .music: .playful
        case .chat: .happy
        case .ai: .focused
        }
    }

}

struct PhilosophyQuote {
    let author: String
    let text: String
    let expression: String

    var chatText: String {
        "\(author)：\(text)\n我理解成：\(expression)"
    }

    var petExpression: String {
        "\(author)：\(text)\n\(expression)"
    }
}

enum PhilosophyQuoteLibrary {
    private static let quotes: [PhilosophyQuote] = [
        PhilosophyQuote(author: "苏格拉底", text: "未经审视的人生不值得过。", expression: "先停一下，问问自己真正想要什么。"),
        PhilosophyQuote(author: "亚里士多德", text: "幸福取决于我们自己。", expression: "今天可以从一个可控的小行动开始。"),
        PhilosophyQuote(author: "笛卡尔", text: "我思故我在。", expression: "只要你还在思考，方向就还能被校准。"),
        PhilosophyQuote(author: "康德", text: "仰望星空与心中的道德律令。", expression: "做决定时，别只看效率，也看原则。"),
        PhilosophyQuote(author: "尼采", text: "成为你自己。", expression: "别急着迎合，把自己的节奏找回来。"),
        PhilosophyQuote(author: "维特根斯坦", text: "凡是能够说的，都能够说清楚。", expression: "把问题说清楚，问题就已经小了一半。"),
        PhilosophyQuote(author: "西蒙娜·德·波伏娃", text: "人不是生而为自己，而是逐渐成为自己。", expression: "允许自己在行动中慢慢成形。"),
        PhilosophyQuote(author: "加缪", text: "重要的不是治愈，而是带着病痛活下去。", expression: "不完美也可以继续推进。")
    ]

    static func next(after index: Int) -> PhilosophyQuote {
        quotes[index % quotes.count]
    }

    static func random() -> PhilosophyQuote {
        quotes.randomElement() ?? quotes[0]
    }
}

struct FolkSongRecommendation {
    let title: String
    let artist: String
    let region: String
    let reason: String

    var chatText: String {
        "今日民谣推荐：\(artist) - \(title)\n地区：\(region)\n推荐理由：\(reason)"
    }

    var petExpression: String {
        "今日民谣：\(title)\n\(artist)。\(reason)"
    }
}

enum FolkSongLibrary {
    private static let songs: [FolkSongRecommendation] = [
        FolkSongRecommendation(title: "成都", artist: "赵雷", region: "中国", reason: "旋律很稳，适合慢慢收拾一天的心情。"),
        FolkSongRecommendation(title: "平凡之路", artist: "朴树", region: "中国", reason: "适合在需要重新出发时听。"),
        FolkSongRecommendation(title: "米店", artist: "张玮玮", region: "中国", reason: "简单、温柔，有旧日生活的纹理。"),
        FolkSongRecommendation(title: "漠河舞厅", artist: "柳爽", region: "中国", reason: "带一点冷色叙事，适合夜里听。"),
        FolkSongRecommendation(title: "Five Hundred Miles", artist: "The Brothers Four", region: "美国", reason: "经典 folk，干净又有远行感。"),
        FolkSongRecommendation(title: "Blowin' in the Wind", artist: "Bob Dylan", region: "美国", reason: "问题比答案更重要，适合思考时听。"),
        FolkSongRecommendation(title: "The Sound of Silence", artist: "Simon & Garfunkel", region: "美国", reason: "安静但有重量，适合降低噪音。"),
        FolkSongRecommendation(title: "Scarborough Fair", artist: "Simon & Garfunkel", region: "英国/美国", reason: "旋律清澈，像给大脑做一次重启。"),
        FolkSongRecommendation(title: "Take Me Home, Country Roads", artist: "John Denver", region: "美国", reason: "直接、温暖，适合补一点归属感。"),
        FolkSongRecommendation(title: "Hallelujah", artist: "Leonard Cohen", region: "加拿大", reason: "有沉静的力量，适合慢下来。"),
        FolkSongRecommendation(title: "Suzanne", artist: "Leonard Cohen", region: "加拿大", reason: "诗意很强，适合独处时听。"),
        FolkSongRecommendation(title: "The Parting Glass", artist: "The High Kings", region: "爱尔兰", reason: "传统民谣气质，适合一天结束时。")
    ]

    static func today(calendar: Calendar = .current, date: Date = Date()) -> FolkSongRecommendation {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return songs[day % songs.count]
    }
}

enum ComputerAssistant {
    static func handle(_ input: String) -> AssistantResponse {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if wantsDailyFolkSong(normalized) {
            return AssistantResponse(message: FolkSongLibrary.today().chatText, succeeded: true)
        }

        if wantsPhilosophyQuote(normalized) {
            let quote = PhilosophyQuoteLibrary.random()
            return AssistantResponse(message: quote.chatText, succeeded: true)
        }

        if wantsDockAlwaysVisible(normalized) {
            return setDockAutohide(false)
        }

        if wantsDockAutoHidden(normalized) {
            return setDockAutohide(true)
        }

        if let simpleAction = simpleAction(for: normalized) {
            return simpleAction
        }

        if let settingURL = settingsURL(for: normalized) {
            return openURL(settingURL, successMessage: "好了，已经打开对应的系统设置。")
        }

        if let locationURL = commonLocationURL(for: normalized) {
            return openURL(locationURL, successMessage: "好了，已经打开 \(locationURL.lastPathComponent)。")
        }

        if let folderName = extractFolderName(from: normalized) {
            return openFolder(named: folderName)
        }

        if wantsAppStorageReport(normalized) {
            return appStorageReport()
        }

        if let appName = extractAppName(from: normalized) {
            return openApp(named: appName)
        }

        return AssistantResponse(
            message: "这句我还不会执行。现在我能处理：打开 App/文件夹、截图、查电量/磁盘、打开常用目录/系统设置、锁屏、程序坞设置、哲学名言、每日民谣。",
            succeeded: false
        )
    }

    private static func wantsDailyFolkSong(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let mentionsFolk = compact.contains("民谣")
            || compact.lowercased().contains("folk")
            || compact.contains("民歌")
        let wantsRecommendation = compact.contains("推荐")
            || compact.contains("来一首")
            || compact.contains("听什么")
            || compact.contains("今日")
            || compact.contains("每天")
            || compact.contains("一首")
        return mentionsFolk && wantsRecommendation
    }

    private static func wantsPhilosophyQuote(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let mentionsQuote = compact.contains("名言")
            || compact.contains("格言")
            || compact.contains("金句")
            || compact.contains("来一句")
            || compact.contains("说一句")
        let mentionsPhilosophy = compact.contains("哲学")
            || compact.contains("哲学家")
            || compact.contains("苏格拉底")
            || compact.contains("尼采")
            || compact.contains("康德")
        return mentionsPhilosophy && mentionsQuote
    }

    private static func wantsDockAlwaysVisible(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact.contains("常显示") && compact.contains("程序坞")
            || compact.contains("一直显示") && compact.contains("程序坞")
            || compact.contains("不要隐藏") && compact.contains("程序坞")
    }

    private static func wantsDockAutoHidden(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact.contains("自动隐藏") && compact.contains("程序坞")
            || compact.contains("隐藏") && compact.contains("程序坞")
            || compact.contains("收起") && compact.contains("程序坞")
    }

    private static func wantsAppStorageReport(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        let mentionsApps = compact.contains("应用") || compact.contains("app") || compact.contains("程序")
        let mentionsStorage = compact.contains("占空间")
            || compact.contains("占用空间")
            || compact.contains("空间排行")
            || compact.contains("大小排行")
            || compact.contains("容量")
            || compact.contains("多大")
        return mentionsApps && mentionsStorage
    }

    private static func setDockAutohide(_ enabled: Bool) -> AssistantResponse {
        do {
            try run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"])
            _ = try? run("/usr/bin/killall", ["Dock"])
            return AssistantResponse(
                message: enabled ? "好了，程序坞会自动隐藏。" : "好了，程序坞会常显示。",
                succeeded: true
            )
        } catch {
            return AssistantResponse(message: "我没能修改程序坞设置：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func simpleAction(for text: String) -> AssistantResponse? {
        let compact = text.replacingOccurrences(of: " ", with: "")

        if compact.contains("截图") || compact.contains("截屏") {
            return takeScreenshot()
        }

        if compact.contains("电量") || compact.contains("电池") {
            return batteryReport()
        }

        if compact.contains("磁盘") && (compact.contains("空间") || compact.contains("容量")) {
            return diskSpaceReport()
        }

        if compact.contains("ip地址") || compact.contains("IP地址") || compact.contains("本机ip") || compact.contains("本机IP") {
            return ipAddressReport()
        }

        if compact.contains("内存") || compact.contains("内存压力") {
            return memoryPressureReport()
        }

        if compact.contains("锁屏") || compact.contains("锁定屏幕") {
            return lockScreen()
        }

        if compact.contains("睡眠") || compact.contains("让电脑休眠") {
            return sleepDisplay()
        }

        if compact.contains("重启Finder") || compact.contains("重启访达") {
            return restartFinder()
        }

        if compact.contains("显示隐藏文件") || compact.contains("显示隐藏文件夹") {
            return setHiddenFilesVisible(true)
        }

        if compact.contains("隐藏隐藏文件") || compact.contains("不显示隐藏文件") {
            return setHiddenFilesVisible(false)
        }

        if compact.contains("清空废纸篓") || compact.contains("清空垃圾桶") {
            return emptyTrash()
        }

        return nil
    }

    private static func settingsURL(for text: String) -> URL? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.contains("设置") || compact.contains("系统设置") else { return nil }

        if compact.contains("蓝牙") {
            return URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")
        }
        if compact.contains("网络") || compact.contains("wifi") || compact.contains("WiFi") || compact.contains("无线") {
            return URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
        }
        if compact.contains("显示器") || compact.contains("屏幕") {
            return URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")
        }
        if compact.contains("声音") || compact.contains("音量") {
            return URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
        }
        if compact.contains("电池") {
            return URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        }
        if compact.contains("隐私") || compact.contains("安全") {
            return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        }

        return URL(string: "x-apple.systempreferences:")
    }

    private static func commonLocationURL(for text: String) -> URL? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.contains("打开") else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser
        if compact.contains("桌面") {
            return home.appendingPathComponent("Desktop")
        }
        if compact.contains("下载") {
            return home.appendingPathComponent("Downloads")
        }
        if compact.contains("文稿") || compact.contains("文档") {
            return home.appendingPathComponent("Documents")
        }
        if compact.contains("应用程序") || compact == "打开应用" {
            return URL(fileURLWithPath: "/Applications")
        }
        if compact.contains("废纸篓") {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        }

        return nil
    }

    private static func extractFolderName(from text: String) -> String? {
        let patterns = [
            #"名为\s*[“"']?(.+?)[”"']?\s*的文件夹"#,
            #"叫\s*[“"']?(.+?)[”"']?\s*的文件夹"#,
            #"打开\s*[“"']?(.+?)[”"']?\s*文件夹"#,
            #"打开文件夹\s*[“"']?(.+?)[”"']?$"#
        ]

        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                return cleanFolderName(match)
            }
        }

        return nil
    }

    private static func extractAppName(from text: String) -> String? {
        let patterns = [
            #"打开\s*名为\s*[“"']?(.+?)[”"']?\s*(?:的)?(?:app|App|应用|应用程序|程序)$"#,
            #"启动\s*名为\s*[“"']?(.+?)[”"']?\s*(?:的)?(?:app|App|应用|应用程序|程序)$"#,
            #"打开\s*[“"']?(.+?)[”"']?\s*(?:app|App|应用|应用程序|程序)$"#,
            #"启动\s*[“"']?(.+?)[”"']?\s*(?:app|App|应用|应用程序|程序)$"#,
            #"帮我打开\s*[“"']?(.+?)[”"']?$"#,
            #"帮我启动\s*[“"']?(.+?)[”"']?$"#,
            #"打开\s*[“"']?(.+?)[”"']?$"#,
            #"启动\s*[“"']?(.+?)[”"']?$"#
        ]

        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                let appName = cleanAppName(match)
                if !appName.isEmpty && !appName.contains("文件夹") && !appName.contains("程序坞") {
                    return appName
                }
            }
        }

        return nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private static func cleanFolderName(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t。。，,！!？?\"'“”‘’"))
    }

    private static func cleanAppName(_ text: String) -> String {
        var result = text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t。。，,！!？?\"'“”‘’"))
        for suffix in ["应用程序", "应用", "程序", "App", "app"] {
            if result.hasSuffix(suffix) {
                result.removeLast(suffix.count)
                result = result.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t。。，,！!？?\"'“”‘’"))
            }
        }
        return result
    }

    private static func openFolder(named folderName: String) -> AssistantResponse {
        guard !folderName.isEmpty else {
            return AssistantResponse(message: "告诉我文件夹名字，我就去找。", succeeded: false)
        }

        guard let folderURL = findFolder(named: folderName) else {
            return AssistantResponse(message: "我没有找到名为 \(folderName) 的文件夹。", succeeded: false)
        }

        NSWorkspace.shared.open(folderURL)
        return AssistantResponse(message: "找到了，已经打开 \(folderURL.lastPathComponent)。", succeeded: true)
    }

    private static func openApp(named appName: String) -> AssistantResponse {
        guard !appName.isEmpty else {
            return AssistantResponse(message: "告诉我 App 名字，我就去打开。", succeeded: false)
        }

        guard let appURL = findApp(named: appName) else {
            return AssistantResponse(message: "我没有找到名为 \(appName) 的 App。", succeeded: false)
        }

        if NSWorkspace.shared.open(appURL) {
            return AssistantResponse(message: "好了，已经打开 \(appURL.deletingPathExtension().lastPathComponent)。", succeeded: true)
        }

        return AssistantResponse(message: "我找到了 \(appName)，但没能启动它。", succeeded: false)
    }

    private static func openURL(_ url: URL, successMessage: String) -> AssistantResponse {
        if NSWorkspace.shared.open(url) {
            return AssistantResponse(message: successMessage, succeeded: true)
        }

        return AssistantResponse(message: "我没能打开这个位置。", succeeded: false)
    }

    private static func takeScreenshot() -> AssistantResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "DeskPet-\(formatter.string(from: Date())).png"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(fileName)

        do {
            try run("/usr/sbin/screencapture", ["-x", url.path])
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return AssistantResponse(message: "截图已保存到桌面：\(fileName)", succeeded: true)
        } catch {
            return AssistantResponse(message: "截图失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func batteryReport() -> AssistantResponse {
        do {
            let output = try run("/usr/bin/pmset", ["-g", "batt"])
            let lines = output.split(separator: "\n").map(String.init)
            guard let detail = lines.first(where: { $0.contains("%") }) else {
                return AssistantResponse(message: "我没有读到电池信息，可能是台式机或外接电源状态特殊。", succeeded: false)
            }
            return AssistantResponse(message: "电池状态：\(detail.trimmingCharacters(in: .whitespaces))", succeeded: true)
        } catch {
            return AssistantResponse(message: "读取电量失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func diskSpaceReport() -> AssistantResponse {
        do {
            let output = try run("/bin/df", ["-H", "/"])
            let lines = output.split(separator: "\n").map(String.init)
            guard lines.count >= 2 else {
                return AssistantResponse(message: "我没有读到磁盘空间。", succeeded: false)
            }
            let columns = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard columns.count >= 5 else {
                return AssistantResponse(message: "磁盘空间信息格式有点奇怪。", succeeded: false)
            }
            return AssistantResponse(message: "磁盘：总 \(columns[1])，已用 \(columns[2])，可用 \(columns[3])，使用率 \(columns[4])。", succeeded: true)
        } catch {
            return AssistantResponse(message: "读取磁盘空间失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func ipAddressReport() -> AssistantResponse {
        do {
            let output = try run("/usr/sbin/ipconfig", ["getifaddr", "en0"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                return AssistantResponse(message: "当前 Wi-Fi IP：\(output)", succeeded: true)
            }
        } catch {
            // Fall through to en1.
        }

        do {
            let output = try run("/usr/sbin/ipconfig", ["getifaddr", "en1"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                return AssistantResponse(message: "当前网络 IP：\(output)", succeeded: true)
            }
        } catch {
            return AssistantResponse(message: "我没有读到本机 IP。", succeeded: false)
        }

        return AssistantResponse(message: "我没有读到本机 IP。", succeeded: false)
    }

    private static func memoryPressureReport() -> AssistantResponse {
        do {
            let output = try run("/usr/bin/memory_pressure", [])
            let lines = output.split(separator: "\n").map(String.init)
            let systemLine = lines.first(where: { $0.localizedCaseInsensitiveContains("System-wide memory free percentage") })
            let pressureLine = lines.first(where: { $0.localizedCaseInsensitiveContains("The system has") })
            let summary = [systemLine, pressureLine]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")

            return AssistantResponse(message: summary.isEmpty ? "已读取内存压力，但系统没有返回摘要。" : summary, succeeded: true)
        } catch {
            return AssistantResponse(message: "读取内存压力失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func lockScreen() -> AssistantResponse {
        do {
            try run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
            return AssistantResponse(message: "已锁屏。", succeeded: true)
        } catch {
            return AssistantResponse(message: "锁屏失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func sleepDisplay() -> AssistantResponse {
        do {
            try run("/usr/bin/pmset", ["displaysleepnow"])
            return AssistantResponse(message: "已让屏幕进入睡眠。", succeeded: true)
        } catch {
            return AssistantResponse(message: "休眠失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func restartFinder() -> AssistantResponse {
        do {
            try run("/usr/bin/killall", ["Finder"])
            return AssistantResponse(message: "已重启 Finder。", succeeded: true)
        } catch {
            return AssistantResponse(message: "重启 Finder 失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func setHiddenFilesVisible(_ visible: Bool) -> AssistantResponse {
        do {
            try run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", visible ? "true" : "false"])
            try run("/usr/bin/killall", ["Finder"])
            return AssistantResponse(message: visible ? "已显示隐藏文件。" : "已隐藏隐藏文件。", succeeded: true)
        } catch {
            return AssistantResponse(message: "修改隐藏文件显示失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func emptyTrash() -> AssistantResponse {
        do {
            let script = "tell application \"Finder\" to empty trash"
            try run("/usr/bin/osascript", ["-e", script])
            return AssistantResponse(message: "废纸篓已清空。", succeeded: true)
        } catch {
            return AssistantResponse(message: "清空废纸篓失败：\(error.localizedDescription)", succeeded: false)
        }
    }

    private static func appStorageReport() -> AssistantResponse {
        let appURLs = findInstalledApps()
        guard !appURLs.isEmpty else {
            return AssistantResponse(message: "我没有找到可统计的 App。", succeeded: false)
        }

        let appSizes = appURLs.compactMap { url -> AppSize? in
            guard let sizeInKilobytes = diskUsageInKilobytes(for: url) else { return nil }
            return AppSize(name: url.deletingPathExtension().lastPathComponent, kilobytes: sizeInKilobytes)
        }
        .sorted { $0.kilobytes > $1.kilobytes }

        guard !appSizes.isEmpty else {
            return AssistantResponse(message: "我找到了 App，但暂时没能读取它们的占用空间。", succeeded: false)
        }

        let lines = appSizes.prefix(8).enumerated().map { index, app in
            "\(index + 1). \(app.name) \(formatKilobytes(app.kilobytes))"
        }

        return AssistantResponse(
            message: "占空间最多的 App：\n" + lines.joined(separator: "\n"),
            succeeded: true
        )
    }

    private static func findFolder(named folderName: String) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let commonRoots = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("code"),
            home
        ]

        for root in commonRoots {
            let direct = root.appendingPathComponent(folderName)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: direct.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return direct
            }
        }

        let spotlightMatches = (try? run("/usr/bin/mdfind", ["-name", folderName])) ?? ""
        for line in spotlightMatches.split(separator: "\n").prefix(80) {
            let url = URL(fileURLWithPath: String(line))
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               url.lastPathComponent.localizedCaseInsensitiveCompare(folderName) == .orderedSame {
                return url
            }
        }

        return nil
    }

    private static func findApp(named appName: String) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let normalizedName = appName.hasSuffix(".app") ? String(appName.dropLast(4)) : appName
        let commonRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            home.appendingPathComponent("Applications")
        ]

        for root in commonRoots {
            let direct = root.appendingPathComponent(normalizedName).appendingPathExtension("app")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: direct.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return direct
            }
        }

        for alias in appAliases(for: normalizedName) {
            for root in commonRoots {
                let direct = root.appendingPathComponent(alias).appendingPathExtension("app")
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: direct.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return direct
                }
            }
        }

        let spotlightMatches = (try? run("/usr/bin/mdfind", ["-name", normalizedName])) ?? ""
        for line in spotlightMatches.split(separator: "\n").prefix(120) {
            let url = URL(fileURLWithPath: String(line))
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  url.pathExtension == "app" else {
                continue
            }

            let candidateName = url.deletingPathExtension().lastPathComponent
            if candidateName.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
                || candidateName.localizedCaseInsensitiveContains(normalizedName) {
                return url
            }
        }

        return nil
    }

    private static func findInstalledApps() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            home.appendingPathComponent("Applications")
        ]

        var apps: [URL] = []
        var seenPaths = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                if seenPaths.insert(url.path).inserted {
                    apps.append(url)
                }
                enumerator.skipDescendants()
            }
        }

        return apps
    }

    private static func diskUsageInKilobytes(for url: URL) -> Int64? {
        guard let output = try? run("/usr/bin/du", ["-sk", url.path]) else { return nil }
        guard let firstField = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first else {
            return nil
        }
        return Int64(firstField)
    }

    private static func formatKilobytes(_ kilobytes: Int64) -> String {
        let bytes = Double(kilobytes) * 1024
        let gibibyte = 1024.0 * 1024.0 * 1024.0
        let mebibyte = 1024.0 * 1024.0

        if bytes >= gibibyte {
            return String(format: "%.1f GB", bytes / gibibyte)
        }

        return String(format: "%.0f MB", bytes / mebibyte)
    }

    private static func appAliases(for appName: String) -> [String] {
        switch appName.lowercased() {
        case "微信", "wechat":
            return ["WeChat", "微信"]
        case "浏览器", "chrome", "谷歌", "谷歌浏览器":
            return ["Google Chrome", "Chrome"]
        case "safari", "苹果浏览器":
            return ["Safari"]
        case "备忘录", "notes":
            return ["Notes", "备忘录"]
        case "终端", "terminal":
            return ["Terminal", "终端"]
        case "访达", "finder":
            return ["Finder"]
        default:
            return []
        }
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw AssistantCommandError.failed(stderr.isEmpty ? stdout : stderr)
        }

        return stdout
    }
}

enum AssistantCommandError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

enum PetMood: CaseIterable {
    case curious
    case happy
    case focused
    case playful
    case sleepy

    var face: String {
        switch self {
        case .curious: "^_^"
        case .happy: "o^.^o"
        case .focused: "-_-"
        case .playful: ">_<"
        case .sleepy: "-.- z"
        }
    }

    var tapMessage: String {
        switch self {
        case .curious: "嗯？我听见你了。"
        case .happy: "今天也要顺顺利利。"
        case .focused: "进入专注模式，我会安静一点。"
        case .playful: "再点一下可能会变成别的样子。"
        case .sleepy: "我眯一小会儿，但不会离岗。"
        }
    }

    var bodyColor: Color {
        switch self {
        case .curious: Color(red: 0.23, green: 0.58, blue: 0.92)
        case .happy: Color(red: 0.95, green: 0.45, blue: 0.35)
        case .focused: Color(red: 0.18, green: 0.68, blue: 0.55)
        case .playful: Color(red: 0.91, green: 0.62, blue: 0.18)
        case .sleepy: Color(red: 0.52, green: 0.54, blue: 0.72)
        }
    }

    var accentColor: Color {
        switch self {
        case .curious: Color(red: 1.0, green: 0.84, blue: 0.22)
        case .happy: Color(red: 1.0, green: 0.92, blue: 0.42)
        case .focused: Color(red: 0.67, green: 0.90, blue: 0.82)
        case .playful: Color(red: 0.99, green: 0.35, blue: 0.45)
        case .sleepy: Color(red: 0.78, green: 0.82, blue: 0.95)
        }
    }
}

enum PixelTheme {
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.18)
    static let panel = Color(red: 0.96, green: 0.98, blue: 1.00)
    static let paper = Color(red: 1.00, green: 0.99, blue: 0.97)
    static let screen = Color(red: 0.88, green: 0.96, blue: 1.00)
    static let blue = Color(red: 0.30, green: 0.56, blue: 0.96)
    static let blush = Color(red: 1.0, green: 0.46, blue: 0.62)
    static let rim = Color.white.opacity(0.72)
    static let surfaceOpacity = 0.82
    static let panelOpacity = 0.72
    static let inkOpacity = 0.76
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DeskPetView: View {
    @Bindable var pet: PetModel
    @State private var isHovering = false
    @State private var breathe = false
    @State private var idleLoop = false

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 8) {
                Spacer(minLength: 4)

                PetBody(pet: pet, isHovering: isHovering, breathe: breathe, idleLoop: idleLoop)
                    .frame(width: 148, height: 148)
                    .offset(y: pet.hopCount.isMultiple(of: 2) ? 0 : -6)
                    .scaleEffect(
                        x: pet.hopCount.isMultiple(of: 2) ? 1.0 : 1.05,
                        y: pet.hopCount.isMultiple(of: 2) ? 1.0 : 0.96
                    )
                    .animation(.spring(response: 0.34, dampingFraction: 0.58), value: pet.hopCount)
                    .onTapGesture {
                        pet.react(to: .tap)
                    }
                    .accessibilityLabel("桌宠，当前表情 \(pet.mood.face)")

                SpeechBubble(text: pet.message)
                    .frame(width: 212)

                if pet.isChatOpen {
                    ChatPanel(pet: pet)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isHovering {
                    ControlStrip(pet: pet)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear {
            breathe = true
            idleLoop = true
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
            if hovering {
                pet.react(to: .nudge)
            }
        }
    }
}

struct PetBody: View {
    let pet: PetModel
    let isHovering: Bool
    let breathe: Bool
    let idleLoop: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let bob = CGFloat(sin(phase * 2.4)) * 2.4
            let lean = sin(phase * 1.35) * 1.4
            let shadowScale = 1.0 + CGFloat(cos(phase * 2.4)) * 0.08

            ZStack {
                MascotMotionDots(color: pet.mood.accentColor, phase: phase, isActive: isHovering || pet.sparkle)

                ShadowBlob(color: pet.mood.bodyColor, isCompressed: isHovering)
                    .offset(y: 78)
                    .scaleEffect(x: shadowScale, y: 1.0)

                EarPair(
                    color: pet.mood.bodyColor,
                    accent: pet.mood.accentColor,
                    isHovering: isHovering,
                    idleLoop: idleLoop,
                    phase: phase
                )
                .offset(y: -54 + bob * 0.45)

                PandaPetBody(
                    accent: pet.mood.accentColor,
                    isHovering: isHovering,
                    mood: pet.mood,
                    appStyle: pet.activeAppStyle,
                    phase: phase
                )
                    .offset(y: 34 + bob * 0.45)

                PandaPetHead(
                    accent: pet.mood.accentColor,
                    mood: pet.mood,
                    appStyle: pet.activeAppStyle,
                    isHovering: isHovering,
                    phase: phase
                )
                    .offset(y: bob)
                    .rotationEffect(.degrees(lean))
                    .scaleEffect(breathe ? 1.015 : 0.995)
                    .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: breathe)

                FaceView(mood: pet.mood, isBlinking: pet.isBlinking, isHovering: isHovering, phase: phase)
                    .offset(x: isHovering ? 2 : 0, y: -16 + bob)
                    .animation(.spring(response: 0.32, dampingFraction: 0.62), value: isHovering)

                HStack(spacing: 64) {
                    PandaArm(isHovering: isHovering, side: .left, phase: phase)
                    PandaArm(isHovering: isHovering, side: .right, phase: phase)
                }
                .offset(y: 30 + bob * 0.35)

                HStack(spacing: 38) {
                    Capsule().fill(PixelTheme.ink.opacity(0.40)).frame(width: 24, height: 8)
                    Capsule().fill(PixelTheme.ink.opacity(0.40)).frame(width: 24, height: 8)
                }
                .offset(y: 67 + bob * 0.18)

                if pet.sparkle || isHovering {
                    SparkleRing(color: pet.mood.accentColor, phase: phase)
                        .transition(.opacity.combined(with: .scale))
                }

                ContextAccessory(style: pet.activeAppStyle, accent: pet.mood.accentColor, phase: phase)
            }
        }
    }
}

struct PandaPetHead: View {
    let accent: Color
    let mood: PetMood
    let appStyle: ActiveAppStyle
    let isHovering: Bool
    let phase: TimeInterval

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PixelTheme.ink.opacity(0.13))
                .frame(width: 118, height: 98)
                .offset(x: 4, y: 5)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PixelTheme.paper.opacity(0.94))
                .frame(width: 118, height: 98)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PixelTheme.rim.opacity(0.96), lineWidth: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(PixelTheme.ink.opacity(0.12), lineWidth: 1)
                )

            MascotCrest(accent: accent, phase: phase)
                .offset(y: -51)
                .opacity(appStyle == .ai ? 0 : 1)

            SoftPixel(size: 16, color: Color.white.opacity(0.42), radius: 6)
                .offset(x: -35, y: -26)
        }
    }
}

struct PandaPetBody: View {
    let accent: Color
    let isHovering: Bool
    let mood: PetMood
    let appStyle: ActiveAppStyle
    let phase: TimeInterval

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PixelTheme.ink.opacity(0.11))
                .frame(width: 82, height: 58)
                .offset(x: 4, y: 5)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PixelTheme.paper.opacity(0.88))
                .frame(width: 82, height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PixelTheme.rim.opacity(0.72), lineWidth: 1.5)
                )

            HStack(spacing: 58) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(PixelTheme.ink.opacity(0.88))
                    .frame(width: 20, height: 34)
                    .rotationEffect(.degrees(12))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(PixelTheme.ink.opacity(0.88))
                    .frame(width: 20, height: 34)
                    .rotationEffect(.degrees(-12))
            }
            .offset(y: -4)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .frame(width: 46, height: 34)

            Capsule()
                .fill(accent.opacity(0.68))
                .frame(width: isHovering ? 45 : 38, height: 9)
                .offset(y: -22)
                .scaleEffect(x: 1.0 + CGFloat(sin(phase * 3.0)) * 0.04, y: 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.58), value: isHovering)

            SoftPixel(size: 13, color: accent.opacity(0.62), radius: 5)
                .offset(y: -1)

            if mood == .focused {
                HStack(spacing: 4) {
                    SoftPixel(size: 5, color: PixelTheme.ink.opacity(0.42), radius: 2)
                    SoftPixel(size: 5, color: PixelTheme.ink.opacity(0.42), radius: 2)
                    SoftPixel(size: 5, color: PixelTheme.ink.opacity(0.42), radius: 2)
                }
                .offset(y: 18)
                .opacity(appStyle == .reading || appStyle == .ai ? 0 : 1)
            }
        }
    }
}

struct ContextAccessory: View {
    let style: ActiveAppStyle
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            switch style {
            case .normal:
                EmptyView()
            case .coding:
                CodingAccessory(accent: accent, phase: phase)
                    .offset(y: 42)
            case .reading:
                ReadingAccessory(accent: accent, phase: phase)
                    .offset(y: 43)
            case .music:
                HeadphoneAccessory(accent: accent, phase: phase)
                    .offset(y: -8)
            case .chat:
                ChatAccessory(accent: accent, phase: phase)
                    .offset(x: 44, y: -42)
            case .ai:
                RobotAccessory(accent: accent, phase: phase)
                    .offset(y: -12)
            }
        }
        .allowsHitTesting(false)
        .transition(.scale.combined(with: .opacity))
    }
}

struct ChatAccessory: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            bubble(width: 42, height: 25, opacity: 0.95)
                .offset(x: CGFloat(sin(phase * 2.3)) * 1.2, y: CGFloat(cos(phase * 2.0)) * 1.1)

            bubble(width: 28, height: 18, opacity: 0.78)
                .scaleEffect(0.92)
                .offset(x: -24, y: 24 + CGFloat(sin(phase * 2.6)) * 1.0)
                .opacity(0.86)
        }
    }

    private func bubble(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PixelTheme.paper.opacity(opacity))
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.72), lineWidth: 1.4)
                )
                .shadow(color: PixelTheme.ink.opacity(0.10), radius: 4, x: 0, y: 2)

            HStack(spacing: 3) {
                Circle().fill(accent.opacity(0.82)).frame(width: 4, height: 4)
                Circle().fill(accent.opacity(0.62)).frame(width: 4, height: 4)
                Circle().fill(accent.opacity(0.82)).frame(width: 4, height: 4)
            }
            .offset(x: -10, y: -10)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PixelTheme.paper.opacity(opacity))
                .frame(width: 9, height: 9)
                .rotationEffect(.degrees(35))
                .offset(x: -5, y: 3)
        }
    }
}

struct CodingAccessory: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PixelTheme.ink.opacity(0.90))
                .frame(width: 66, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(accent.opacity(0.80), lineWidth: 1.4)
                )

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    SoftPixel(size: 5, color: Color.green.opacity(0.90), radius: 2)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .frame(width: 22, height: 4)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent.opacity(0.85))
                        .frame(width: 14 + CGFloat(sin(phase * 4.5)) * 4, height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.50))
                        .frame(width: 18, height: 4)
                }
            }

            Capsule()
                .fill(PixelTheme.ink.opacity(0.55))
                .frame(width: 34, height: 5)
                .offset(y: 22)
        }
    }
}

struct ReadingAccessory: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        HStack(spacing: -2) {
            page(rotation: -8, x: 1)
            page(rotation: 8, x: -1)
        }
        .offset(y: CGFloat(sin(phase * 2.1)) * 0.8)
    }

    private func page(rotation: Double, x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(PixelTheme.paper.opacity(0.95))
            .frame(width: 34, height: 34)
            .overlay(
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(PixelTheme.ink.opacity(0.26)).frame(width: 19, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(PixelTheme.ink.opacity(0.20)).frame(width: 16, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.35)).frame(width: 18, height: 3)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelTheme.rim, lineWidth: 1.2))
            .rotationEffect(.degrees(rotation))
            .offset(x: x)
    }
}

struct HeadphoneAccessory: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.58, to: 0.94)
                .stroke(PixelTheme.ink.opacity(0.88), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 126, height: 126)
                .rotationEffect(.degrees(4))

            HStack(spacing: 88) {
                pad
                pad
            }
            .offset(y: 2 + CGFloat(sin(phase * 3.2)) * 1.2)

            HStack(spacing: 10) {
                SoftPixel(size: 5, color: accent.opacity(0.86), radius: 2)
                SoftPixel(size: 4, color: accent.opacity(0.55), radius: 2)
                SoftPixel(size: 5, color: accent.opacity(0.86), radius: 2)
            }
            .offset(y: 55)
        }
    }

    private var pad: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(PixelTheme.ink.opacity(0.92))
            .frame(width: 18, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(0.34))
                    .frame(width: 9, height: 20)
            )
    }
}

struct RobotAccessory: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Capsule()
                    .fill(PixelTheme.ink.opacity(0.78))
                    .frame(width: 4, height: 18)
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 10, height: 10)
                    .scaleEffect(1.0 + CGFloat(sin(phase * 4.0)) * 0.08)
            }
            .offset(y: -55)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PixelTheme.ink.opacity(0.86))
                .frame(width: 64, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.85), lineWidth: 1.5)
                )
                .offset(y: -5)

            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent.opacity(0.95))
                    .frame(width: 10, height: 7)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent.opacity(0.95))
                    .frame(width: 10, height: 7)
            }
            .offset(y: -5)

            HStack(spacing: 72) {
                Circle().fill(accent.opacity(0.72)).frame(width: 8, height: 8)
                Circle().fill(accent.opacity(0.72)).frame(width: 8, height: 8)
            }
            .offset(y: 0)
        }
    }
}

struct SoftPixelBlob: View {
    let color: Color
    let accent: Color

    var body: some View {
        ZStack {
            SoftPixel(size: 72, color: color.opacity(PixelTheme.surfaceOpacity), radius: 24)
                .offset(y: 4)
            SoftPixel(size: 54, color: color.opacity(0.72), radius: 20)
                .offset(x: -30, y: -6)
            SoftPixel(size: 56, color: color.opacity(0.68), radius: 20)
                .offset(x: 30, y: -8)
            SoftPixel(size: 46, color: Color.white.opacity(0.46), radius: 18)
                .offset(x: -18, y: -22)
            SoftPixel(size: 34, color: accent.opacity(0.34), radius: 12)
                .offset(x: 28, y: 20)
        }
    }
}

struct SoftPixelOutline: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .path(in: rect.insetBy(dx: 8, dy: 10))
    }
}

struct SoftPixel: View {
    let size: CGFloat
    let color: Color
    var radius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct EarPair: View {
    let color: Color
    let accent: Color
    let isHovering: Bool
    let idleLoop: Bool
    let phase: TimeInterval

    var body: some View {
        HStack(spacing: 60) {
            ear(rotation: -16, direction: -1)
            ear(rotation: 16, direction: 1)
        }
    }

    private func ear(rotation: Double, direction: Double) -> some View {
        ZStack {
            Circle()
                .fill(PixelTheme.ink.opacity(0.12))
                .frame(width: 42, height: 42)
                .offset(x: 3, y: 4)
            Circle()
                .fill(PixelTheme.ink.opacity(0.94))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(PixelTheme.rim.opacity(0.58), lineWidth: 1.5)
                )
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 17, height: 17)
                .offset(x: -4, y: -3)
        }
        .rotationEffect(.degrees(rotation + direction * (isHovering ? 12 : sin(phase * 2.1) * 4.5)))
        .animation(.spring(response: 0.34, dampingFraction: 0.48), value: isHovering)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: idleLoop)
    }
}

struct MascotCrest: View {
    let accent: Color
    let phase: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(accent.opacity(0.84))
                .frame(width: 10, height: 22)
                .rotationEffect(.degrees(-18 + sin(phase * 2.3) * 3))
            Capsule()
                .fill(accent.opacity(0.96))
                .frame(width: 12, height: 28)
                .offset(y: CGFloat(sin(phase * 2.1)) * -1.6)
            Capsule()
                .fill(accent.opacity(0.70))
                .frame(width: 10, height: 20)
                .rotationEffect(.degrees(18 - sin(phase * 2.2) * 3))
        }
        .shadow(color: accent.opacity(0.20), radius: 5, x: 0, y: 2)
    }
}

enum PandaSide {
    case left
    case right
}

struct PandaArm: View {
    let isHovering: Bool
    let side: PandaSide
    let phase: TimeInterval

    private var direction: CGFloat {
        side == .left ? -1 : 1
    }

    var body: some View {
        let idleSwing = sin(phase * 2.2 + Double(direction)) * 4.0

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(PixelTheme.ink.opacity(0.88))
            .frame(width: 17, height: 28)
            .rotationEffect(.degrees(Double(direction) * (isHovering ? -30 : 10) + idleSwing))
            .offset(x: direction * (isHovering ? -4 : 0), y: isHovering ? -8 : CGFloat(sin(phase * 2.4)) * 1.2)
            .animation(.spring(response: 0.28, dampingFraction: 0.52), value: isHovering)
    }
}

struct FaceView: View {
    let mood: PetMood
    let isBlinking: Bool
    let isHovering: Bool
    let phase: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 38) {
                    Capsule()
                        .fill(PixelTheme.blush.opacity(0.20))
                        .frame(width: 13, height: 6)
                    Capsule()
                        .fill(PixelTheme.blush.opacity(0.20))
                        .frame(width: 13, height: 6)
                }
                .offset(y: 15)

                HStack(spacing: 32) {
                    eye
                    eye
                }
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.58), value: isHovering)
            }

            mouth
        }
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(PixelTheme.ink)
            .frame(width: isHovering ? 13 : 11, height: isBlinking || mood == .sleepy ? 3 : 14)
        .animation(.easeInOut(duration: 0.12), value: isBlinking)
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .happy:
            ArcSmile()
                .stroke(PixelTheme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 22, height: 11)
        case .focused:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(PixelTheme.ink)
                .frame(width: 22, height: 3)
        case .playful:
            ArcSmile()
                .stroke(PixelTheme.ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(-4))
        case .sleepy:
            Capsule()
                .fill(PixelTheme.ink.opacity(0.72))
                .frame(width: 16, height: 3)
        case .curious:
            Circle()
                .stroke(PixelTheme.ink, lineWidth: 3)
                .frame(width: 10, height: 10)
        }
    }
}

struct BellyBadge: View {
    let color: Color
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .black, design: .monospaced))
            .foregroundStyle(PixelTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(color.opacity(0.36))
                    .overlay(Capsule().stroke(PixelTheme.rim, lineWidth: 1.5))
            )
            .frame(width: 84)
    }
}

struct MascotMotionDots: View {
    let color: Color
    let phase: TimeInterval
    let isActive: Bool

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                let angle = phase * 0.9 + Double(index) * 1.256
                let radius = isActive ? 72.0 : 62.0
                Circle()
                    .fill(color.opacity(isActive ? 0.52 : 0.24))
                    .frame(width: index.isMultiple(of: 2) ? 6 : 4, height: index.isMultiple(of: 2) ? 6 : 4)
                    .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius * 0.62)
                    .scaleEffect(isActive ? 1.12 : 0.88)
            }
        }
        .allowsHitTesting(false)
    }
}

struct SparkleRing: View {
    let color: Color
    var phase: TimeInterval = 0

    var body: some View {
        ZStack {
            ForEach(0..<8) { index in
                Rectangle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .offset(y: -92 - CGFloat(sin(phase * 3.0 + Double(index))) * 8)
                    .rotationEffect(.degrees(Double(index) * 45 + phase * 80))
            }
        }
        .opacity(0.72)
    }
}

struct ShadowBlob: View {
    let color: Color
    var isCompressed = false

    var body: some View {
        Capsule()
            .fill(PixelTheme.ink.opacity(isCompressed ? 0.11 : 0.08))
            .frame(width: isCompressed ? 124 : 116, height: isCompressed ? 12 : 14)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: isCompressed)
    }
}

struct ArcSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width / 2,
            startAngle: .degrees(22),
            endAngle: .degrees(158),
            clockwise: false
        )
        return path
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .foregroundStyle(PixelTheme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PixelTheme.ink.opacity(0.10))
                        .offset(x: 3, y: 4)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PixelTheme.paper.opacity(PixelTheme.panelOpacity))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PixelTheme.rim, lineWidth: 1.5))
                }
            )
    }
}

struct ChatPanel: View {
    @Bindable var pet: PetModel

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(pet.chatMessages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 112)
                .onChange(of: pet.chatMessages.count) {
                    if let lastID = pet.chatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                TextField("输入指令", text: $pet.chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelTheme.ink)
                    .tint(PixelTheme.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(PixelTheme.screen.opacity(0.82))
                            .overlay(Capsule().stroke(PixelTheme.ink.opacity(PixelTheme.inkOpacity), lineWidth: 2))
                    )
                    .onSubmit {
                        pet.sendChat()
                    }

                Button {
                    pet.sendChat()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(PetButtonStyle())
                .help("发送")
            }
        }
        .padding(8)
        .frame(width: 224)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PixelTheme.ink.opacity(0.10))
                    .offset(x: 4, y: 5)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PixelTheme.panel.opacity(PixelTheme.panelOpacity))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PixelTheme.rim, lineWidth: 1.5))
            }
        )
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            Text(message.text)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(message.role == .user ? Color.white : PixelTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(message.role == .assistant ? 12 : 4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(message.role == .user ? PixelTheme.blue.opacity(0.90) : PixelTheme.paper.opacity(0.88))
                        .overlay(Capsule().stroke(PixelTheme.ink.opacity(PixelTheme.inkOpacity), lineWidth: 1.5))
                )

            if message.role == .assistant {
                Spacer(minLength: 28)
            }
        }
    }
}

struct ControlStrip: View {
    @Bindable var pet: PetModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                pet.react(to: .chooseFolder)
            } label: {
                Label("选择", systemImage: "folder.badge.plus")
            }
            .help("选择要让桌宠打开的文件夹")

            Button {
                pet.react(to: .toggleChat)
            } label: {
                Label("聊天", systemImage: pet.isChatOpen ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            }
            .help("和桌宠聊天，让它帮你操作电脑")

            Button {
                pet.react(to: .philosophyQuote)
            } label: {
                Label("名言", systemImage: "book.closed")
            }
            .help("更新一条哲学名人名言")

            Button {
                pet.react(to: .dailyFolkSong)
            } label: {
                Label("民谣", systemImage: "music.note")
            }
            .help("推荐今日民谣")

            Button {
                pet.react(to: .tap)
            } label: {
                Label("变脸", systemImage: "face.smiling")
            }
            .help("切换桌宠表情")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(PetButtonStyle())
        .padding(8)
        .background(
            ZStack {
                Capsule()
                    .fill(PixelTheme.ink.opacity(0.10))
                    .offset(x: 3, y: 4)
                Capsule()
                    .fill(PixelTheme.panel.opacity(PixelTheme.panelOpacity))
                    .overlay(Capsule().stroke(PixelTheme.rim, lineWidth: 1.5))
            }
        )
    }
}

struct PetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .monospaced))
            .foregroundStyle(PixelTheme.ink)
            .frame(width: 34, height: 30)
            .background(
                ZStack {
                    Capsule()
                        .fill(PixelTheme.ink.opacity(0.14))
                        .offset(x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
                    Capsule()
                        .fill((configuration.isPressed ? PixelTheme.screen : PixelTheme.paper).opacity(0.88))
                        .overlay(Capsule().stroke(PixelTheme.ink.opacity(PixelTheme.inkOpacity), lineWidth: 1.5))
                }
            )
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.superview?.wantsLayer = true
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
    }
}
