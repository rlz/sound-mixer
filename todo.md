# Development Tasks

Product behavior and acceptance criteria are maintained in `requirements/`. Keep only outstanding work in this list.

- [ ] Split the app bridge and audio routing coordinators into smaller units while preserving atomic command validation and route transitions; remove their scoped SwiftLint size and complexity exceptions after integration verification.
- [ ] Verify version-tagged DMG creation and Finder layout on macOS; document install, first-launch, and permission checks for releases.
- [ ] Verify the first GitHub Pages deployment from `main`, confirm the public URL, and check the published page on mobile and desktop.
- [ ] Add and verify upgrade coverage for configurations from the published app before changing the schema; confirm failed or unsupported migrations preserve the user's file.
- [ ] Before the next public app release, increment `MARKETING_VERSION` and the shipped `CURRENT_PROJECT_VERSION`, then verify the bundle, tag, and artifact versions agree.
