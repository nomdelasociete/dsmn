import XCTest
import TOMLKit
@testable import DSMNCore

final class CodexFeatureConfigurationTests: XCTestCase {
    func testNativeParserAcceptsCommentedTableAndRejectsDuplicateTable() throws {
        let table = try TOMLTable(string: "[features] # valid comment\nhooks = false\n")
        XCTAssertEqual(table["features"]?.table?["hooks"]?.bool, false)
        XCTAssertThrowsError(try TOMLTable(string: "[features] # comment\nhooks = false\n[features]\nhooks = true\n"))
    }

    func testSupportedEditsPreserveEveryUnrelatedByte() throws {
        let fixtures: [(String, String)] = [
            ("", "[features]\nhooks = true\n"),
            ("# user settings", "# user settings\n[features]\nhooks = true\n"),
            ("model = 'example'\n", "model = 'example'\n[features]\nhooks = true\n"),
            ("[features]", "[features]\nhooks = true\n"),
            ("[features] # keep\nother = true\n[next] # keep too\nhooks = false\n",
             "[features] # keep\nhooks = true\nother = true\n[next] # keep too\nhooks = false\n"),
            ("[features] # keep\n\t hooks  =  false # reason\n[next] # keep too\nhooks = false\n",
             "[features] # keep\n\t hooks  =  true # reason\n[next] # keep too\nhooks = false\n"),
            ("[ 'features' ] # quoted\n'hooks' = false\n", "[ 'features' ] # quoted\n'hooks' = true\n"),
            ("[\"feat\\u0075res\"] # escaped key\n\"hoo\\u006Bs\" = false # preserved\n",
             "[\"feat\\u0075res\"] # escaped key\n\"hoo\\u006Bs\" = true # preserved\n"),
            ("[features]\r\nhooks = false # keep\r\n[desktop]\r\nx = 1\r\n",
             "[features]\r\nhooks = true # keep\r\n[desktop]\r\nx = 1\r\n"),
            ("[desktop]\r\nx = 1", "[desktop]\r\nx = 1\r\n[features]\r\nhooks = true\r\n"),
            ("[features] # end", "[features] # end\nhooks = true\n")
        ]
        for (original, expected) in fixtures {
            let result = try CodexFeatureConfiguration.enablingHooks(in: original)
            XCTAssertEqual(Data(result.utf8), Data(expected.utf8))
            XCTAssertTrue(try CodexFeatureConfiguration.hooksEnabled(in: result))
            XCTAssertEqual(try TOMLTable(string: result), try TOMLTable(string: expected))
            XCTAssertEqual(try CodexFeatureConfiguration.enablingHooks(in: result), result)
        }
    }

    func testScannerDoesNotTreatStringsOrArrayContentsAsHeaders() throws {
        let original = #"""
        message = """
        [features] # this is a string
        hooks = false
        Escaped \" and a backslash \\
        """
        literal = '''
        [features]
        hooks = false
        '''
        array = [
            "[features]", # ] " ignored comment
            "hooks = false",
            { text = "# = [features]" }
        ]
        [features] # actual table
        text = "quoted \" # [next]"
        more = """
        [next]
        """
        hooks = false # actual flag
        [next] # actual boundary
        hooks = false
        """#
        let expected = original.replacingOccurrences(of: "hooks = false # actual flag", with: "hooks = true # actual flag")
        XCTAssertEqual(try CodexFeatureConfiguration.enablingHooks(in: original), expected)
        XCTAssertTrue(try CodexFeatureConfiguration.hooksEnabled(in: expected))
    }

    func testAlreadyEnabledSemanticFormsAreByteIdentical() throws {
        for original in [
            "features.hooks = true # dotted\n",
            "features = { hooks = true, other = false }\r\n",
            "[\"features\"] # quoted\n'hooks' = true",
            "[features]\nhooks = true\n[features.other]\nenabled = false\n"
        ] {
            XCTAssertTrue(try CodexFeatureConfiguration.hooksEnabled(in: original))
            XCTAssertEqual(try CodexFeatureConfiguration.enablingHooks(in: original), original)
        }
    }

    func testValidUnsupportedRepresentationsAreRefused() throws {
        for original in [
            "features.hooks = false\n",
            "features = { hooks = false, other = true }\n",
            "features = { other = true }\n",
            "[features.other]\nenabled = true\n",
            "features = 'custom'\n",
            "[features]\nhooks = 'false'\n",
            "[features.hooks]\nenabled = false\n"
        ] {
            XCTAssertNoThrow(try TOMLTable(string: original))
            XCTAssertFalse(try CodexFeatureConfiguration.hooksEnabled(in: original))
            XCTAssertThrowsError(try CodexFeatureConfiguration.enablingHooks(in: original)) { error in
                XCTAssertTrue(error.localizedDescription.contains("cannot safely edit"))
            }
        }
    }

    func testInvalidTOMLIsRefusedWithoutLeakingValues() {
        for original in [
            "[features]\nhooks = false\n[features]\nhooks = true\n",
            "secret_token = 'private-value\n",
            "[features]\nhooks = not_a_boolean\n",
            "key = 'valid'\u{0000}private-value"
        ] {
            XCTAssertThrowsError(try CodexFeatureConfiguration.enablingHooks(in: original)) { error in
                XCTAssertFalse(error.localizedDescription.contains("private-value"))
                XCTAssertTrue(error.localizedDescription.contains("invalid TOML"))
            }
            XCTAssertThrowsError(try CodexFeatureConfiguration.hooksEnabled(in: original))
        }
    }
}
