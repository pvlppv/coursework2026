import Foundation
import Testing

@testable import Sotie

@MainActor
struct PromptCatalogClusterTests {

  @Test func openerForHeavyClusterReturnsHeavySubState() async throws {
    let pick = PromptCatalog.opener(
      for: PromptCluster.heavy,
      languageCode: "en",
      seed: 42
    )
    let valid: Set<PromptCategory> = [.heavy, .numb, .anxious, .frustrated]
    #expect(valid.contains(pick.subState))
    #expect(!pick.text.isEmpty)
  }

  @Test func openerForBrainDumpAlwaysReturnsBrainDump() async throws {
    for seed: UInt64 in [1, 2, 3, 4, 5, 99, 12345] {
      let pick = PromptCatalog.opener(
        for: PromptCluster.brainDump,
        languageCode: "en",
        seed: seed
      )
      #expect(pick.subState == .brainDump)
    }
  }

  @Test func deterministicSeedReproducesSamePick() async throws {
    let a = PromptCatalog.opener(
      for: PromptCluster.looping,
      languageCode: "en",
      seed: 12345
    )
    let b = PromptCatalog.opener(
      for: PromptCluster.looping,
      languageCode: "en",
      seed: 12345
    )
    #expect(a.subState == b.subState)
    #expect(a.openerIndex == b.openerIndex)
    #expect(a.text == b.text)
  }

  @Test func recentlyShownExclusionAffectsNextPick() async throws {
    // Pin three globalIndices and confirm the picker doesn't return them.
    let firstThree: [Int] = (0..<5).map { seed -> Int in
      let pick = PromptCatalog.opener(
        for: PromptCluster.heavy,
        languageCode: "en",
        seed: UInt64(seed)
      )
      return PromptCatalog.globalIndex(forSubState: pick.subState, openerIndex: pick.openerIndex)
    }
    let recent = Array(firstThree.prefix(3))
    let next = PromptCatalog.opener(
      for: PromptCluster.heavy,
      languageCode: "en",
      seed: 999,
      recentlyShownGlobalIndices: recent
    )
    let nextGlobal = PromptCatalog.globalIndex(
      forSubState: next.subState,
      openerIndex: next.openerIndex
    )
    #expect(!Set(recent).contains(nextGlobal))
  }

  @Test func timeOpenerNilAtMidday() async throws {
    let result = PromptCatalog.opener(forTime: 14, languageCode: "en", seed: 1)
    #expect(result == nil)
  }

  @Test func timeOpenerMatchesHourSubState() async throws {
    let morning = PromptCatalog.opener(forTime: 8, languageCode: "en", seed: 1)
    let evening = PromptCatalog.opener(forTime: 20, languageCode: "en", seed: 1)
    let lateNight = PromptCatalog.opener(forTime: 2, languageCode: "en", seed: 1)
    #expect(morning?.subState == .morning)
    #expect(evening?.subState == .evening)
    #expect(lateNight?.subState == .lateNight)
  }

  @Test func globalIndexRoundTrip() async throws {
    for subState in PromptCategory.allCases {
      for openerIndex in 1...10 {
        let g = PromptCatalog.globalIndex(forSubState: subState, openerIndex: openerIndex)
        let decoded = PromptCatalog.decodeGlobalIndex(g)
        #expect(decoded?.subState == subState)
        #expect(decoded?.openerIndex == openerIndex)
      }
    }
  }
}
