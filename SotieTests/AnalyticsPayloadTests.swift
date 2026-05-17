import Foundation
import Testing

@testable import Sotie

struct AnalyticsPayloadTests {

  @Test func paywallContextProducesExpectedParameters() throws {
    let context = PaywallAnalyticsContext(
      source: .responseLimitReached,
      variantId: PaywallVariant.reviewSafeBaseline.rawValue,
      eligibleForTrial: true,
      selectedProductId: PremiumProduct.annual.rawValue
    )

    #expect(
      context.parameters == [
        "source": "response_limit_reached",
        "variantId": "paywall_v1_review_safe",
        "eligibleForTrial": "true",
        "selectedProductId": PremiumProduct.annual.rawValue,
      ])
  }

  @Test func goDeeperRequestedProducesExpectedParameters() throws {
    let parameters = Analytics.goDeeperRequestedParameters(
      responseNumber: 3,
      trigger: .continue,
      hasSummary: true,
      conversationDepth: 6,
      isFirstAssistantMessage: false
    )

    #expect(
      parameters == [
        "responseNumber": "3",
        "trigger": "continue",
        "deliveryMode": "streaming",
        "hasSummary": "true",
        "conversationDepthBucket": "5-8",
        "isFirstAssistantMessage": "false",
      ])
  }

  @Test func goDeeperCompletedProducesLatencyAndLengthBuckets() throws {
    let parameters = Analytics.goDeeperCompletedParameters(
      responseNumber: 2,
      trigger: .start,
      latencyMs: 1840,
      responseLength: 86,
      hasSummary: false,
      isFirstAssistantMessage: true
    )

    #expect(
      parameters == [
        "responseNumber": "2",
        "trigger": "start",
        "deliveryMode": "streaming",
        "responseLengthBucket": "80-139",
        "hasSummary": "false",
        "isFirstAssistantMessage": "true",
        "latencyMs": "1840",
        "latencyBucket": "1000-1999",
      ])
  }

  @Test func goDeeperErrorProducesStructuredPayload() throws {
    let parameters = Analytics.goDeeperErrorParameters(
      reason: "ttft_timeout",
      stage: .generation,
      trigger: .retry,
      responseNumber: 4,
      isRetryable: true
    )

    #expect(
      parameters == [
        "reason": "ttft_timeout",
        "stage": "generation",
        "trigger": "retry",
        "deliveryMode": "streaming",
        "responseNumber": "4",
        "isRetryable": "true",
      ])
  }

  @Test func goDeeperCancelledProducesExpectedParameters() throws {
    let parameters = Analytics.goDeeperCancelledParameters(
      responseNumber: 5,
      trigger: .refreshLastAssistant,
      hadPlaceholderAssistant: true,
      wasInPlaceRegeneration: true
    )

    #expect(
      parameters == [
        "responseNumber": "5",
        "trigger": "refresh_last_assistant",
        "deliveryMode": "streaming",
        "phase": "in_flight",
        "hadPlaceholderAssistant": "true",
        "wasInPlaceRegeneration": "true",
      ])
  }

  @Test func goDeeperUsefulProducesExpectedParameters() throws {
    let parameters = Analytics.goDeeperUsefulParameters(
      responseNumber: 6,
      saveAction: .saved,
      latencyMs: 6200,
      isLastMessage: true
    )

    #expect(
      parameters == [
        "responseNumber": "6",
        "saveAction": "saved",
        "isLastMessage": "true",
        "latencyBucket": "5000+",
      ])
  }
}
