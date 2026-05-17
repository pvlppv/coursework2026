import Foundation
import Security
import Testing

@testable import Sotie

struct SecurityHardeningTests {

  @Test func usageRecordResetsDailyCountersAcrossDayBoundary() throws {
    var record = AIUsageRecord(
      dayAnchor: makeDate(dayOffset: 0, seconds: 0),
      responsesToday: 7,
      reservedRequestDates: [makeDate(dayOffset: 0, seconds: 15)],
      deviceFingerprint: "vendor:test-device"
    )

    record.normalize(now: makeDate(dayOffset: 1, seconds: 0), calendar: Self.utcCalendar)

    #expect(record.responsesToday == 0)
    #expect(record.reservedRequestDates.isEmpty)
  }

  @Test func rateLimitReservationAllowsRapidRequestsWithoutDelay() throws {
    var record = AIUsageRecord(deviceFingerprint: "vendor:test-device")
    let start = makeDate(dayOffset: 0, seconds: 0)
    let policy = AIRateLimitPolicy.default

    // Two requests 0.1s apart should both succeed immediately (no delay)
    try record.reserveRequestSlot(
      at: start,
      policy: policy,
      isSuspiciousEnvironment: false
    )
    try record.reserveRequestSlot(
      at: start.addingTimeInterval(0.1),
      policy: policy,
      isSuspiciousEnvironment: false
    )

    #expect(record.reservedRequestDates.count == 2)
  }

  @Test func rateLimitReservationRejectsBurstOverPerMinuteCap() throws {
    var record = AIUsageRecord(deviceFingerprint: "vendor:test-device")
    let start = makeDate(dayOffset: 0, seconds: 0)
    let policy = AIRateLimitPolicy.default

    for index in 0..<policy.maxRequestsPerMinute {
      try record.reserveRequestSlot(
        at: start.addingTimeInterval(Double(index) * 0.1),
        policy: policy,
        isSuspiciousEnvironment: false
      )
    }

    do {
      try record.reserveRequestSlot(
        at: start.addingTimeInterval(1),
        policy: policy,
        isSuspiciousEnvironment: false
      )
      Issue.record("Expected the per-minute limiter to reject the request exceeding the cap.")
    } catch let error as AIRequestThrottleError {
      switch error {
      case .perMinuteLimitExceeded(let retryAfter):
        #expect(retryAfter > 0)
      case .dailyLimitExceeded:
        Issue.record("Expected perMinuteLimitExceeded, got dailyLimitExceeded.")
      }
    }
  }

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private func makeDate(dayOffset: Int, seconds: TimeInterval) -> Date {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    return base.addingTimeInterval(TimeInterval(dayOffset) * 86_400 + seconds)
  }
}

private final class TestSecureStore: @unchecked Sendable, SecureValueStore {
  private var values: [String: Data] = [:]

  func data(for account: String) throws -> Data? {
    values[account]
  }

  func set(_ data: Data, for account: String, accessible: CFString?) throws {
    values[account] = data
  }

  func removeValue(for account: String) throws {
    values.removeValue(forKey: account)
  }
}
