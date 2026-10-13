import Testing
@testable import HerdrGlowCore

@Test func boxedPermissionPrompt() {
    let screen = """
    ╭───────────────────────────────────────────╮
    │ Bash command                              │
    │                                           │
    │   rm -rf build                            │
    │                                           │
    │ Do you want to proceed?                   │
    │ ❯ 1. Yes                                  │
    │   2. Yes, and don't ask again for rm      │
    │   3. No, and tell Claude what to do (esc) │
    ╰───────────────────────────────────────────╯
    """
    #expect(PromptParser.options(in: screen) == [
        PromptOption(number: 1, label: "Yes"),
        PromptOption(number: 2, label: "Yes, and don't ask again for rm"),
        PromptOption(number: 3, label: "No, and tell Claude what to do (esc)"),
    ])
}

@Test func unboxedEditPrompt() {
    let screen = """
     Do you want to make this edit to Package.swift?
     ❯ 1. Yes
       2. Yes, allow all edits during this session (shift+tab)
       3. No, and tell Claude what to do differently (esc)
    """
    #expect(PromptParser.options(in: screen).map(\.number) == [1, 2, 3])
    #expect(PromptParser.options(in: screen)[1].label == "Yes, allow all edits during this session (shift+tab)")
}

@Test func earlierNumberedListIsIgnored() {
    let screen = """
    Plan:
    1. Install deps
    2. Run tests
    3. Ship
    Do you want to proceed?
    ❯ 1. Yes
      2. No
    """
    #expect(PromptParser.options(in: screen) == [
        PromptOption(number: 1, label: "Yes"),
        PromptOption(number: 2, label: "No"),
    ])
}

@Test func freeTextQuestionHasNoOptions() {
    #expect(PromptParser.options(in: "What name should the new branch have?\n> ").isEmpty)
}

@Test func plainOutputHasNoOptions() {
    #expect(PromptParser.options(in: "Running tests…\nAll 12 tests passed.").isEmpty)
}

@Test func singleNumberedLineIsNotAPrompt() {
    #expect(PromptParser.options(in: "1. Only one").isEmpty)
}

@Test func nonSequentialNumbersAreNotAPrompt() {
    #expect(PromptParser.options(in: "1. a\n3. c").isEmpty)
}

@Test func questionIsTheBlockAboveTheOptions() {
    let screen = """
    ⏺ Done: I created hello.txt.
    ❯ Use the AskUserQuestion tool to ask me which color I like.
    ────────────────
     ☐ Color
    Which color do you like?
    ❯ 1. Red
         The color red.
      2. Green
         The color green.
    ────────────────
      3. Chat about this

    Enter to select · ↑/↓ to navigate · Esc to cancel
    """
    #expect(PromptParser.question(in: screen) == "☐ Color\nWhich color do you like?")
}

@Test func questionDropsBoxBorders() {
    let screen = """
    ╭───────────────────────────────────────────╮
    │ Bash command                              │
    │                                           │
    │   rm -rf build                            │
    │                                           │
    │ Do you want to proceed?                   │
    │ ❯ 1. Yes                                  │
    │   2. No                                   │
    ╰───────────────────────────────────────────╯
    """
    #expect(PromptParser.question(in: screen) == "Bash command\nrm -rf build\nDo you want to proceed?")
}

@Test func questionKeepsOnlyTheLastLines() {
    let diff = (1...20).map { "  \($0) line" }.joined(separator: "\n")
    let screen = "Edit file\n\(diff)\nDo you want to make this edit?\n❯ 1. Yes\n  2. No"
    let question = PromptParser.question(in: screen)
    #expect(question?.split(separator: "\n").count == PromptParser.questionLineLimit)
    #expect(question?.hasSuffix("Do you want to make this edit?") == true)
}

@Test func questionNeedsOptions() {
    #expect(PromptParser.question(in: "Running tests…\nAll 12 tests passed.") == nil)
}

@Test func questionDropsDashedLinesAndTips() {
    let screen = """
    ⏺ Write(notes.txt)
    ────────────────
     Create file
     notes.txt
     Tip: auto mode handles prompts for you
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
      1 test
    ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to create notes.txt?
     ❯ 1. Yes
       2. No
     Esc to cancel · Tab to amend
    """
    #expect(PromptParser.question(in: screen) == "Create file\nnotes.txt\n1 test\nDo you want to create notes.txt?")
}
