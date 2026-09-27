# Development Tasks

Product behavior and acceptance criteria are maintained in `requirements/`. Completed interface changes are recorded here.

- [x] Keep the Output, Mix, and Input headings fixed above their scrollable content; sort cards by type, then by name.
- [x] Add a fixed footer below the independently scrolling work areas and show the installed app version; verify the footer stays visible while panels scroll.
- [x] Show disconnected physical input and output cards as dimmed, without errors; disable device controls and add deletion actions that remove input sources from all mixes or clear the disconnected output mix. Verify web format, lint, build, and Swift checks.
- [x] Keep newly added virtual bus channels unassigned in dependent mixes when the bus channel count increases.
- [ ] Make disabling a physical device stop Sound Mixer capture, output, and metering for its UID; preserve saved routes for re-enabling and stop stale capture on disconnection. Automated checks and a macOS build pass; manually verify unplugging hardware and listening for silence on a Mac with the device attached.
- [x] Clear actionable formatter, linter, and compiler diagnostics; verify Swift tests, web checks, and a clean macOS build.
- [x] Preserve the source kind when removing mix inputs and show command errors and startup notifications in dismissible popups that close after ten seconds; verify web formatting, lint, build, and macOS build.
- [x] Replace the DMG photo with a hand-painted music studio illustration, align real Finder icons with empty wall frames, add a drag arrow, and keep their captions on a light background.
- [ ] Split the app bridge and audio routing coordinators into smaller units while preserving atomic command validation and route transitions; remove their scoped SwiftLint size and complexity exceptions after integration verification.
- [ ] Verify version-tagged DMG creation and Finder layout on macOS; document manual install, first-launch, and permission checks before public distribution.
