import Testing
@testable import TaskAlarm

struct PhraseTaskTests {
    @Test func generatesEightWords() {
        let phrase = PhraseTask.generate()
        #expect(phrase.split(separator: " ").count == 8)
    }

    @Test func generatedPhrasesDiffer() {
        // 50-word pool, 8 picks: collision over 5 runs is effectively impossible.
        let phrases = (0..<5).map { _ in PhraseTask.generate() }
        #expect(Set(phrases).count > 1)
    }

    @Test func validateAcceptsExactMatch() {
        #expect(PhraseTask.validate(input: "red fox jumps", against: "red fox jumps"))
    }

    @Test func validateTrimsOuterWhitespaceOnly() {
        #expect(PhraseTask.validate(input: "  red fox jumps \n", against: "red fox jumps"))
    }

    @Test func validateRejectsCaseMismatch() {
        #expect(!PhraseTask.validate(input: "Red fox jumps", against: "red fox jumps"))
    }

    @Test func validateRejectsMissingWord() {
        #expect(!PhraseTask.validate(input: "red fox", against: "red fox jumps"))
    }
}
