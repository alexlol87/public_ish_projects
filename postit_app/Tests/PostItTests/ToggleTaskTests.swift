import Testing
import PostItCore

let sample = "- [ ] a\n- [x] b\n\n```\n- [ ] code\n```\n1. [ ] c\n"

@Test func togglesFirstTask() {
    #expect(toggleTask(sample, index: 0) == sample.replacingOccurrences(of: "- [ ] a", with: "- [x] a"))
}

@Test func togglesSecondTaskOff() {
    #expect(toggleTask(sample, index: 1) == sample.replacingOccurrences(of: "- [x] b", with: "- [ ] b"))
}

@Test func ignoresFencedCode() {
    // index 2 is the numbered task, not the one inside the fence
    #expect(toggleTask(sample, index: 2) == sample.replacingOccurrences(of: "1. [ ] c", with: "1. [x] c"))
}

@Test func outOfRangeIsUnchanged() {
    #expect(toggleTask(sample, index: 3) == sample)
    #expect(toggleTask(sample, index: -1) == sample)
}
