//
//  AnalyticsService.swift
//  Easydict
//
//  Created by tisfeng on 2025/12/22.
//  Copyright © 2025 izual. All rights reserved.
//

import Foundation

/// Provides analytics and crash logging utilities (disabled in QuickTranslate).
@objc(EZAnalyticsService)
@objcMembers
final class AnalyticsService: NSObject {
    // MARK: Internal

    /// No-op: crash reporting is permanently disabled in QuickTranslate.
    @objc(setupCrashLogService)
    static func setupCrashService() {}

    /// No-op: crash reporting is permanently disabled in QuickTranslate.
    static func setCrashEnabled(_ enabled: Bool) {
        _ = enabled
    }

    /// No-op: analytics is permanently disabled in QuickTranslate.
    @objc(logEventWithName:parameters:)
    static func logEvent(withName name: String, parameters: [String: Any]?) {
        _ = name
        _ = parameters
    }

    /// No-op: analytics is permanently disabled in QuickTranslate.
    @objc(logWindowAppear:)
    static func logWindowAppear(_ windowType: EZWindowType) {
        _ = windowType
    }

    /// No-op: analytics is permanently disabled in QuickTranslate.
    @objc(logQueryService:)
    static func logQueryService(_ service: QueryService) {
        _ = service
    }

    /// Returns a human-readable text length range.
    static func textLengthRange(_ text: String) -> String {
        let length = text.utf16.count
        if length <= 10 {
            return "1-10"
        } else if length <= 50 {
            return "10-50"
        } else if length <= 200 {
            return "50-200"
        } else if length <= 1000 {
            return "200-1000"
        } else if length <= 5000 {
            return "1000-5000"
        } else {
            return "5000-∞"
        }
    }

    /// No-op: analytics is permanently disabled in QuickTranslate.
    static func logAppInfo() {}
}
