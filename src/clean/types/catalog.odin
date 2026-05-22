package clean_types

// CATEGORIES is the master list — index it by CategoryId via category_of().
// Order here is the display order users will see in the interactive UI:
// grouped loosely by safety, then by domain.
CATEGORIES := [?]Category{
	{
		id          = .Trash,
		slug        = "trash",
		name        = "Trash",
		group       = .Storage,
		description = "Files in the Trash bin",
		safety      = .Safe,
	},
	{
		id          = .Temp_Files,
		slug        = "temp-files",
		name        = "Temporary Files",
		group       = .System_Junk,
		description = "Temporary files in /tmp and /var/folders",
		safety      = .Safe,
	},
	{
		id          = .Browser_Cache,
		slug        = "browser-cache",
		name        = "Browser Cache",
		group       = .Browsers,
		description = "Cache from Chrome, Safari, Firefox, and Arc",
		safety      = .Safe,
	},
	{
		id          = .Homebrew,
		slug        = "homebrew",
		name        = "Homebrew Cache",
		group       = .Development,
		description = "Homebrew download cache and old versions",
		safety      = .Safe,
	},
	{
		id          = .Homebrew_Cleanup,
		slug        = "homebrew-cleanup",
		name        = "Homebrew Old Versions",
		group       = .Development,
		description = "Outdated versions of installed brew formulae (brew cleanup)",
		safety      = .Safe,
	},
	{
		id          = .Homebrew_Autoremove,
		slug        = "homebrew-autoremove",
		name        = "Homebrew Orphan Dependencies",
		group       = .Development,
		description = "Brew packages installed only as dependencies and no longer needed",
		safety      = .Moderate,
		safety_note = "May remove packages you'd want to keep — review preview list",
	},
	{
		id          = .App_Cache,
		slug        = "app-cache",
		name        = "App Caches (non-standard)",
		group       = .System_Junk,
		description = "Electron/sandboxed app caches outside ~/Library/Caches",
		safety      = .Safe,
	},
	{
		id          = .System_Cache_Root,
		slug        = "system-cache-root",
		name        = "System-wide Caches",
		group       = .System_Junk,
		description = "/Library/Caches contents (needs sudo to delete)",
		safety      = .Moderate,
		safety_note = "Sudo password required at delete time",
	},
	{
		id          = .Orphan_Symlinks,
		slug        = "orphan-symlinks",
		name        = "Orphaned Symlinks",
		group       = .Development,
		description = "Dangling symlinks in /opt/homebrew/bin, ~/.local/bin, ~/bin",
		safety      = .Safe,
	},
	{
		id          = .Docker,
		slug        = "docker",
		name        = "Docker",
		group       = .Development,
		description = "Unused Docker images, containers, and volumes",
		safety      = .Safe,
	},
	{
		id          = .System_Cache,
		slug        = "system-cache",
		name        = "User Cache Files",
		group       = .System_Junk,
		description = "Application caches stored in ~/Library/Caches",
		safety      = .Moderate,
		safety_note = "Some apps may need to rebuild cache on next launch",
	},
	{
		id          = .System_Logs,
		slug        = "system-logs",
		name        = "System Log Files",
		group       = .System_Junk,
		description = "System and application logs",
		safety      = .Moderate,
		safety_note = "Logs may be useful for debugging issues",
	},
	{
		id          = .Dev_Cache,
		slug        = "dev-cache",
		name        = "Development Cache",
		group       = .Development,
		description = "npm, yarn, pip, Xcode DerivedData, CocoaPods cache",
		safety      = .Moderate,
		safety_note = "Projects will need to rebuild/reinstall dependencies",
	},
	{
		id          = .Node_Modules,
		slug        = "node-modules",
		name        = "Node Modules",
		group       = .Development,
		description = "Orphaned node_modules in old projects",
		safety      = .Moderate,
		safety_note = "Projects will need npm install to restore",
	},
	{
		id          = .Launch_Agents,
		slug        = "launch-agents",
		name        = "Orphaned Launch Agents",
		group       = .System_Junk,
		description = "Launch agents pointing to non-existent applications",
		safety      = .Moderate,
		safety_note = "Only orphaned items (pointing to non-existent apps) are detected.",
	},
	{
		id          = .Downloads,
		slug        = "downloads",
		name        = "Old Downloads",
		group       = .Storage,
		description = "Downloads older than 30 days",
		safety      = .Risky,
		safety_note = "May contain important files you forgot about",
		supports_file_selection = true,
	},
	{
		id          = .Ios_Backups,
		slug        = "ios-backups",
		name        = "iOS Backups",
		group       = .Storage,
		description = "iPhone and iPad backup files",
		safety      = .Risky,
		safety_note = "DANGER: you may lose important device backups permanently",
	},
	{
		id          = .Mail_Attachments,
		slug        = "mail-attachments",
		name        = "Mail Attachments",
		group       = .Storage,
		description = "Downloaded email attachments from Mail.app",
		safety      = .Risky,
		safety_note = "May contain important documents and files",
	},
	{
		id          = .Language_Files,
		slug        = "language-files",
		name        = "Language Files",
		group       = .System_Junk,
		description = "Unused language localizations in applications",
		safety      = .Risky,
		safety_note = "May break apps if you switch system language",
	},
	{
		id          = .Large_Files,
		slug        = "large-files",
		name        = "Large Files",
		group       = .Large_Files,
		description = "Files larger than 500MB for review",
		safety      = .Risky,
		safety_note = "Review each file carefully before deleting",
		supports_file_selection = true,
	},
	{
		id          = .Duplicates,
		slug        = "duplicates",
		name        = "Duplicate Files",
		group       = .Storage,
		description = "Files with identical content",
		safety      = .Risky,
		safety_note = "Review carefully — keeps newest copy by default",
	},
}

// category_of returns the Category metadata for the given id.
// Panics if the id isn't registered — keep CATEGORIES exhaustive.
category_of :: proc(id: CategoryId) -> Category {
	for c in CATEGORIES {
		if c.id == id {
			return c
		}
	}
	panic("category_of: missing CategoryId entry — CATEGORIES is not exhaustive")
}

// safety_label returns a human-readable label for a Safety level.
safety_label :: proc(s: Safety) -> string {
	switch s {
	case .Safe:     return "safe"
	case .Moderate: return "moderate"
	case .Risky:    return "risky"
	}
	return "?"
}

// group_label returns a human-readable label for a Group.
group_label :: proc(g: Group) -> string {
	switch g {
	case .System_Junk: return "System Junk"
	case .Development: return "Development"
	case .Storage:     return "Storage"
	case .Browsers:    return "Browsers"
	case .Large_Files: return "Large Files"
	}
	return "?"
}
