import Testing
@testable import SidebarCore

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
