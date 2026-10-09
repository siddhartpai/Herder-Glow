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
        var run: [PromptOption] = []
        for line in screen.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let option = parseLine(line) else { continue }
            if option.number == 1 {
                run = [option]
            } else if let last = run.last, option.number == last.number + 1 {
                run.append(option)
            } else {
                run = []
            }
        }
        return run.count >= 2 ? run : []
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
