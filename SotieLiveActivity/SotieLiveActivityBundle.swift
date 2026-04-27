//
//  SotieLiveActivityBundle.swift
//  SotieLiveActivity
//
//  Widget extension entry point. Registers every widget the extension
//  vends. We only ship one Live Activity for the onboarding discount
//  squeeze; nothing else lives here.
//

import SwiftUI
import WidgetKit

@main
struct SotieLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        OnboardingDiscountLiveActivity()
    }
}
