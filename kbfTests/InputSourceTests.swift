import Carbon.HIToolbox
import XCTest
@testable import kbf

final class InputSourceTests: XCTestCase {
    // kVK_ANSI_A produces "a" on QWERTY, Dvorak, and Colemak alike, so this is
    // stable regardless of which ASCII layout the machine prefers.
    func testTranslatesLetterKey() {
        XCTAssertEqual(InputSource.translateToASCII(keyCode: CGKeyCode(kVK_ANSI_A), shift: false), "a")
    }

    func testShiftUppercases() {
        XCTAssertEqual(InputSource.translateToASCII(keyCode: CGKeyCode(kVK_ANSI_A), shift: true), "A")
    }

    func testDigitsAndSpace() {
        XCTAssertEqual(InputSource.translateToASCII(keyCode: CGKeyCode(kVK_ANSI_1), shift: false), "1")
        XCTAssertEqual(InputSource.translateToASCII(keyCode: CGKeyCode(kVK_Space), shift: false), " ")
    }
}
