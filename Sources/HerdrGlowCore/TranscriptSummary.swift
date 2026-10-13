import Foundation

/// What a Claude Code session did, built locally from its transcript file.
public struct TranscriptSummary: Equatable, Sendable {
    public var title: String?
    public var lastRequest: String?
    public var filesChanged: [String] = []
    public var commandCount = 0
    public var lastMessage: String?

    public init(title: String? = nil, lastRequest: String? = nil, filesChanged: [String] = [],
                commandCount: Int = 0, lastMessage: String? = nil) {
        self.title = title
        self.lastRequest = lastRequest
        self.filesChanged = filesChanged
        self.commandCount = commandCount
        self.lastMessage = lastMessage
    }

    public static var defaultProjectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Finds `<session id>.jsonl` in any project folder.
    public static func locate(sessionID: String, projectsDir: URL = defaultProjectsDir) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        return folders
            .map { $0.appendingPathComponent(sessionID + ".jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(sessionID: String, projectsDir: URL = defaultProjectsDir) -> TranscriptSummary? {
        guard let url = locate(sessionID: sessionID, projectsDir: projectsDir),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(lines: text.split(separator: "\n").map(String.init))
    }

    public static func parse(lines: [String]) -> TranscriptSummary {
        var summary = TranscriptSummary()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let message = object["message"] as? [String: Any]
            switch object["type"] as? String {
            case "ai-title":
                summary.title = object["aiTitle"] as? String ?? summary.title
            case "user":
                if let request = requestText(message?["content"]) { summary.lastRequest = request }
            case "assistant":
                for block in message?["content"] as? [[String: Any]] ?? [] {
                    summary.add(block)
                }
            default:
                break
            }
        }
        return summary
    }

    private mutating func add(_ block: [String: Any]) {
        switch block["type"] as? String {
        case "text":
            let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lastMessage = text }
        case "tool_use":
            let input = block["input"] as? [String: Any] ?? [:]
            switch block["name"] as? String {
            case "Bash":
                commandCount += 1
            case "Edit", "Write", "MultiEdit", "NotebookEdit":
                if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
                    filesChanged.removeAll { $0 == path }
                    filesChanged.append(path)
                }
            default:
                break
            }
        default:
            break
        }
    }

    /// A prompt typed by the user; tool results and system text (starting with `<`) are not.
    private static func requestText(_ content: Any?) -> String? {
        var texts: [String] = []
        if let text = content as? String {
            texts = [text]
        } else if let blocks = content as? [[String: Any]] {
            texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.hasPrefix("<") ? nil : text
    }
}
