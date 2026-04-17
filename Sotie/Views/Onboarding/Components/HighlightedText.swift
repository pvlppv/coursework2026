//
//  HighlightedText.swift
//  Sotie
//
//  Reusable component that renders text with a highlighted substring.
//  Uses AttributedString to avoid deprecated Text concatenation on iOS 26.
//

import SwiftUI

struct HighlightedText: View {
    let fullText: String
    let highlight: String
    let font: Font
    let highlightFont: Font
    let textColor: Color
    let highlightColor: Color
    let alignment: TextAlignment

    init(
        _ fullText: String,
        highlight: String,
        font: Font = .system(size: 26, weight: .bold),
        highlightFont: Font? = nil,
        textColor: Color = Color.theme.textPrimary,
        highlightColor: Color = Color.theme.textSecondary,
        alignment: TextAlignment = .leading
    ) {
        self.fullText = fullText
        self.highlight = highlight
        self.font = font
        self.highlightFont = highlightFont ?? font
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.alignment = alignment
    }

    var body: some View {
        Text(attributedString)
            .multilineTextAlignment(alignment)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(fullText)
        attributed.font = font
        attributed.foregroundColor = textColor

        if let range = attributed.range(of: highlight) {
            attributed[range].font = highlightFont
            attributed[range].foregroundColor = highlightColor
        }

        return attributed
    }
}

/// Variant with two highlights in the same string.
struct DoubleHighlightedText: View {
    let fullText: String
    let highlight1: String
    let highlight2: String
    let font: Font
    let highlightFont: Font
    let textColor: Color
    let highlightColor: Color
    let alignment: TextAlignment

    init(
        _ fullText: String,
        highlight1: String,
        highlight2: String,
        font: Font = .system(size: 22, weight: .medium),
        highlightFont: Font = .system(size: 22, weight: .bold),
        textColor: Color = Color.theme.textPrimary,
        highlightColor: Color = Color.theme.textSecondary,
        alignment: TextAlignment = .leading
    ) {
        self.fullText = fullText
        self.highlight1 = highlight1
        self.highlight2 = highlight2
        self.font = font
        self.highlightFont = highlightFont
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.alignment = alignment
    }

    var body: some View {
        Text(attributedString)
            .multilineTextAlignment(alignment)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(fullText)
        attributed.font = font
        attributed.foregroundColor = textColor

        if let range = attributed.range(of: highlight1) {
            attributed[range].font = highlightFont
            attributed[range].foregroundColor = highlightColor
        }
        if let range = attributed.range(of: highlight2) {
            attributed[range].font = highlightFont
            attributed[range].foregroundColor = highlightColor
        }

        return attributed
    }
}

#Preview {
    VStack(spacing: 20) {
        HighlightedText(
            "what would help right now?",
            highlight: "help"
        )
        DoubleHighlightedText(
            "do you have just 5 minutes for your clarity each day?",
            highlight1: "5 minutes",
            highlight2: "clarity"
        )
    }
    .padding()
}
