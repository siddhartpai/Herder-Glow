import Foundation

public struct PromptOption: Equatable, Sendable {
    public let number: Int
    public let label: String

    public init(number: Int, label: String) {
        self.number = number
        self.label = label
    }
}

public enum PromptParser {
    /// Returns the last run of options numbered 1, 2, 3… on the screen.
    /// Lines that are not options (wrapped text, box borders) do not end a run.
    public static func options(in screen: String) -> [PromptOption] {
        lastRun(in: screen.split(separator: "\n", omittingEmptySubsequences: false)).options
    }

    static let questionLineLimit = 6

    /// The short question above the options: the lines after the last separator or box top,
    /// without borders, dashed lines, tips and blank lines. Nil when the screen shows no options.
    public static func question(in screen: String) -> String? {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lastRun(in: lines).lines?.lowerBound else { return nil }
        let above = lines[..<start]
        let blockStart = above.lastIndex { isLine($0, of: "─━═╭╮╰╯") }.map { $0 + 1 } ?? above.startIndex
        let text = above[blockStart...]
            .filter { !isLine($0, of: "╌┄┈") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "│|").union(.whitespaces)) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Tip:") }
        return text.isEmpty ? nil : text.suffix(questionLineLimit).joined(separator: "\n")
    }

    /// True for a line drawn only with the given characters, such as a separator.
    private static func isLine(_ line: Substring, of characters: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && text.allSatisfy { characters.contains($0) }
    }

    private static func lastRun(in lines: [Substring]) -> (options: [PromptOption], lines: ClosedRange<Int>?) {
        var run: [PromptOption] = []
        var start = 0
        var end = 0
        for (index, line) in lines.enumerated() {
            guard let option = parseLine(line) else { continue }
            if option.number == 1 {
                run = [option]
                start = index
            } else if let last = run.last, option.number == last.number + 1 {
                run.append(option)
            } else {
                run = []
            }
            end = index
        }
        return run.count >= 2 ? (run, start...end) : ([], nil)
    }

    /// True when the screen shows a selection menu, where Enter picks the highlighted item.
    public static func isMenu(_ screen: String) -> Bool {
        ["Enter to confirm", "Enter to select", "↑/↓ to navigate"].contains { screen.contains($0) }
    }

    static func parseLine(_ raw: Substring) -> PromptOption? {
        var text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "│|").union(.whitespaces))
        if let marker = ["❯", "›", ">"].first(where: { text.hasPrefix($0) }) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 2, let number = Int(digits) else { return nil }
        let rest = text.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let label = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        return PromptOption(number: number, label: label)
    }
}
