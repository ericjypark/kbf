import AppKit
import XCTest
@testable import kbf

final class SettingsTests: XCTestCase {
    // MARK: label themes

    func testThemeRawValueRoundTrip() {
        for t in LabelTheme.allCases {
            XCTAssertEqual(LabelTheme(rawValue: t.rawValue), t)
        }
    }

    func testLightThemeUsesDarkText() {
        XCTAssertLessThan(LabelTheme.light.text.srgbBrightness,
                          LabelTheme.light.pill.srgbBrightness)
        XCTAssertGreaterThan(LabelTheme.dark.text.srgbBrightness,
                             LabelTheme.dark.pill.srgbBrightness)
    }

    func testHintScaleFontsAscend() {
        XCTAssertLessThan(HintScale.small.fontSize, HintScale.medium.fontSize)
        XCTAssertLessThan(HintScale.medium.fontSize, HintScale.large.fontSize)
    }

    // MARK: excluded apps

    func testExclusionMatchIsCaseInsensitive() {
        let list = ["com.apple.Terminal", "Org.Mozilla.Firefox"]
        XCTAssertTrue(AppSettings.matchesExclusion("com.apple.terminal", in: list))
        XCTAssertTrue(AppSettings.matchesExclusion("org.mozilla.firefox", in: list))
        XCTAssertFalse(AppSettings.matchesExclusion("com.apple.Safari", in: list))
    }

    func testNilBundleIDNeverExcluded() {
        XCTAssertFalse(AppSettings.matchesExclusion(nil, in: ["com.apple.Terminal"]))
    }

    // MARK: alphabet sanitization

    func testAlphabetSanitizationDedupesAndKeepsOrder() {
        XCTAssertEqual(AppSettings.sanitizedAlphabet("aAbb1c!d"), ["a", "b", "c", "d"])
    }

    func testAlphabetTooShortFallsBackToDefault() {
        // Fewer than 4 letters can't sustain the 2-char pool + overflow prefix.
        XCTAssertEqual(AppSettings.sanitizedAlphabet("abc"), LabelAssigner.defaultAlphabet)
        XCTAssertEqual(AppSettings.sanitizedAlphabet(""), LabelAssigner.defaultAlphabet)
    }
}

private extension NSColor {
    var srgbBrightness: CGFloat { usingColorSpace(.sRGB)?.brightnessComponent ?? 0 }
}
