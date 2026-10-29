import Foundation

// Only unrelated hardware/localization dependencies are stubbed for this standalone test.
enum HardwareProbe {
    static func systemProfilerHardwareJSON() -> [String: Any] { [:] }
}
func L(_ chinese: String, _ english: String) -> String { english }

@main
enum ManagementServiceTests {
    static func main() {
        let signedIn: [String: Any] = ["Accounts": [["AccountID": "test@example.invalid"]]]
        let signedOut: [String: Any] = ["Accounts": [[String: Any]]()]
        let cases: [(String, [String: Any]?, [String: Any]?, Bool?)] = [
            ("modern signed in without legacy domain", nil, ["AAIsAccountSignedIn": true], true),
            ("modern signed out", nil, ["AAIsAccountSignedIn": false], false),
            ("legacy signed in", signedIn, nil, true),
            ("legacy signed out", signedOut, nil, false),
            ("both unavailable", nil, nil, nil),
            ("missing fields", [:], [:], nil),
            ("malformed fields", ["Accounts": "invalid"], ["AAIsAccountSignedIn": "invalid"], nil),
            ("invalid account identifier", ["Accounts": [["AccountID": "  "]]], nil, nil),
            ("conflicting signed in cache", signedOut, ["AAIsAccountSignedIn": true], nil),
            ("conflicting signed out cache", signedIn, ["AAIsAccountSignedIn": false], nil),
            ("agree signed in", signedIn, ["AAIsAccountSignedIn": true], true),
            ("agree signed out", signedOut, ["AAIsAccountSignedIn": false], false),
        ]
        for (name, legacy, cache, expected) in cases {
            let actual = ManagementService.iCloudAccountSignedIn(legacy: legacy, cache: cache)
            precondition(actual == expected, "Failed: \(name)")
        }
        print("PASS: \(cases.count) iCloud account status regression cases")
        let cache: [String: Any] = ["AAIsAccountSignedIn": true, "AAAccountFullName": "Test User"]
        let modern = ManagementService.iCloudAccountInfo(legacy: nil, cache: cache, databaseUsernames: ["test@example.invalid"])
        precondition(modern.accountID == "test@example.invalid" && modern.displayName == "Test User")
        let legacy = ManagementService.iCloudAccountInfo(
            legacy: ["Accounts": [["AccountID": "test@example.invalid", "DisplayName": "Legacy User"]]],
            cache: nil, databaseUsernames: []
        )
        precondition(legacy.accountID == "test@example.invalid" && legacy.displayName == "Legacy User")
        for state in [false, true] {
            let info = ManagementService.iCloudAccountInfo(
                legacy: state ? signedOut : nil,
                cache: ["AAIsAccountSignedIn": state, "AAAccountFullName": "Stale Name"],
                databaseUsernames: ["stale@example.invalid"]
            )
            precondition(info.accountID == nil && info.displayName == nil)
        }
        let ambiguous = ManagementService.iCloudAccountInfo(
            legacy: signedIn, cache: cache, databaseUsernames: ["other@example.invalid"]
        )
        precondition(ambiguous.accountID == nil)
        let unavailable = ManagementService.iCloudAccountInfo(legacy: nil, cache: cache, databaseUsernames: ["  "])
        precondition(unavailable.signedIn == true && unavailable.accountID == nil && unavailable.displayName == "Test User")
        print("PASS: 6 account identity cases (modern, legacy, signed out, conflict, ambiguity, missing ID)")
        for error in ["authorization denied", "not authorized", "Permission denied", "Operation not permitted"] {
            let parsed = ManagementService.parseICloudAccountDatabaseOutput("Error: unable to open database: \(error)")
            precondition(parsed.usernames.isEmpty && parsed.permissionDenied)
        }
        precondition(!ManagementService.parseICloudAccountDatabaseOutput("Error: no such table: ZACCOUNT").permissionDenied)
        precondition(!ManagementService.parseICloudAccountDatabaseOutput("[{\"username\":\"not authorized@example.invalid\"}]").permissionDenied)
        print("PASS: 6 database error cases (permission denials, schema error, valid JSON)")
        testAccountDatabase()
        if CommandLine.arguments.contains("--live") {
            let info = ManagementService.iCloudAccountInfo()
            precondition(info.signedIn == true && info.accountID != nil && info.displayName != nil,
                         "Expected this Mac’s known signed-in account and identity to be detected")
            print("PASS: this Mac’s sign-in, Apple ID and name detected (no account details printed)")
        }
    }

    static func testAccountDatabase() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("Account fixture.sqlite")
        let fixture = """
            CREATE TABLE ZACCOUNTTYPE (Z_PK INTEGER, ZIDENTIFIER TEXT);
            CREATE TABLE ZACCOUNT (ZACCOUNTTYPE INTEGER, ZUSERNAME TEXT, ZACTIVE INTEGER);
            INSERT INTO ZACCOUNTTYPE VALUES (1, 'com.apple.account.AppleAccount'),
                (2, 'com.apple.account.iTunesStore'), (3, 'com.apple.account.IMAP');
            INSERT INTO ZACCOUNT VALUES (1, 'primary@example.invalid', 1),
                (1, 'primary@example.invalid', 1), (1, 'old@example.invalid', 0),
                (2, 'store@example.invalid', 1), (3, 'mail@example.invalid', 1);
            """
        _ = ShellRunner.run("/usr/bin/sqlite3", [database.path, fixture])
        precondition(ManagementService.iCloudAccountUsernames(at: database) == ["primary@example.invalid"])
        let missing = directory.appendingPathComponent("missing.sqlite")
        precondition(ManagementService.iCloudAccountUsernames(at: missing).isEmpty)
        precondition(!FileManager.default.fileExists(atPath: missing.path), "Read-only queries must not create a database")
        let malformed = directory.appendingPathComponent("malformed.sqlite")
        try! Data("invalid database".utf8).write(to: malformed)
        precondition(ManagementService.iCloudAccountUsernames(at: malformed).isEmpty)
        print("PASS: 3 database cases (primary account filtering, missing file, malformed database)")
    }
}
