# Development Tasks

Product behavior and acceptance criteria are maintained in `requirements/`. Completed interface changes are recorded here.

- [x] Keep the Output, Mix, and Input headings fixed above their scrollable content; sort cards by type, then by name.
- [x] Add a fixed footer below the independently scrolling work areas and show the installed app version; verify the footer stays visible while panels scroll.
- [x] Clear actionable formatter, linter, and compiler diagnostics; verify Swift tests, web checks, and a clean macOS build.
- [ ] Split the app bridge and audio routing coordinators into smaller units while preserving atomic command validation and route transitions; remove their scoped SwiftLint size and complexity exceptions after integration verification.
