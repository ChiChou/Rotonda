// Run: swiftc Rotonda/Data/Models.swift Scripts/test_word_meanings.swift -o /tmp/test-word-meanings && /tmp/test-word-meanings
import Foundation

@main
struct WordMeaningRegressionTests {
    static func main() {
        let integrato = word("integrato", english: "integrated", chinese: "")
        precondition(integrato.meaning(.chinese) == nil,
                     "Missing Chinese must not display the English meaning from the screenshot")
        precondition(integrato.meaning(.chinese, cached: "综合的") == "综合的",
                     "List and detail must resolve the same cached Chinese meaning")
        precondition(integrato.meaning(.english) == "integrated",
                     "Changing back to English must still resolve the bundled English meaning")
        let motore = word("motore", english: "engine", chinese: "发动机")
        precondition(motore.meaning(.chinese) == "发动机",
                     "Bundled Chinese must work without requesting on-device translation")
        let chineseOnly = word("prova", english: "", chinese: "测试")
        precondition(chineseOnly.meaning(.english) == nil,
                     "Language fallback must not silently switch in either direction")
        print("PASS: missing, cached and bundled meanings stay in the selected language.")
    }

    private static func word(_ lemma: String, english: String, chinese: String) -> Word {
        Word(id: 1, lemma: lemma, kind: .road, partOfSpeech: "", level: nil,
             glossEN: english, glossZH: chinese, noteEN: "", noteZH: "",
             exampleIT: "", exampleEN: "", exampleZH: "", questionCount: 0, trueCount: 0,
             chapterSpread: 0, rank: 1)
    }
}
