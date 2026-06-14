package clean_cmd

import "core:testing"

// These tests pin the SAFETY boundary of the uninstaller: which ~/Library
// entries get swept when removing an app. The failure mode that matters is a
// false positive (deleting an unrelated app's data), so the negative cases are
// at least as important as the positive ones.

@(test)
test_leftover_matches_bundle_id :: proc(t: ^testing.T) {
	bid := "com.microsoft.VSCode"
	app := "Visual Studio Code"

	// Exact bundle id, child namespace, and embedded (Group Containers) all match.
	testing.expect(t, leftover_matches("com.microsoft.VSCode", app, bid), "exact bundle id")
	testing.expect(t, leftover_matches("com.microsoft.VSCode.ShipIt", app, bid), "child namespace")
	testing.expect(t, leftover_matches("com.microsoft.VSCode.plist", app, bid), "prefs plist")
	testing.expect(t, leftover_matches("ABCDE12345.com.microsoft.VSCode", app, bid), "group container prefix")
	// Case-insensitive.
	testing.expect(t, leftover_matches("COM.MICROSOFT.VSCODE", app, bid), "case-insensitive bundle id")
}

@(test)
test_leftover_matches_rejects_unrelated :: proc(t: ^testing.T) {
	bid := "com.microsoft.VSCode"
	app := "Visual Studio Code"

	// A different vendor's bundle id must never match.
	testing.expect(t, !leftover_matches("com.google.Chrome", app, bid), "unrelated bundle id")
	// A name that merely *contains* the app name is NOT an exact match.
	testing.expect(t, !leftover_matches("Visual Studio Code Helper", app, bid), "name superstring")
}

@(test)
test_leftover_matches_name_only :: proc(t: ^testing.T) {
	// No bundle id available → fall back to EXACT, case-insensitive name only.
	testing.expect(t, leftover_matches("Code", "Code", ""), "exact name")
	testing.expect(t, leftover_matches("Code.plist", "Code", ""), "name plist")
	testing.expect(t, leftover_matches("code.savedState", "Code", ""), "name saved state")
	// The classic prefix footgun: uninstalling "Code" must not touch "CodeRunner".
	testing.expect(t, !leftover_matches("CodeRunner", "Code", ""), "prefix must not match")
	testing.expect(t, !leftover_matches("Codez", "Code", ""), "near-name must not match")
}
