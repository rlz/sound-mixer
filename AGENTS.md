# Sound Mixer Development Rules

These rules apply to the entire repository. User requirements and files in `requirements/` take precedence.

## Purpose and scope

- Build a desktop app for macOS 15+ with Swift, AppKit, and WKWebView. React, TypeScript, and Tailwind provide the interface. Audio processing stays native.
- Do not describe an internal virtual bus as a system device. Physical Core Audio devices and internal virtual buses are separate destination types.
- Do not promise capture of all audio from an application or control of system volume where macOS or the device does not support it. Show errors and limitations clearly.
- When behavior changes, update the relevant requirements and `todo.md`.

## Structure and architecture

- Keep the route domain model, Core Audio adapters, audio engine, configuration storage, WKWebView bridge, and React interface separate.
- Identify physical devices by stable Core Audio UID and internal buses and routes by their own UUID. Do not use names as identifiers.
- Validate source existence, channel compatibility, and absence of cycles before applying a mixing graph configuration.
- Do not allocate memory, access files, log, block, or call WebKit inside an audio callback. Pass prepared snapshots of settings to the engine.
- The WebKit bridge accepts only known messages after validating types and value ranges. The interface does not access Core Audio directly.
- Store configuration locally with a schema version. Because Rlz Sound Mixer is published, preserve configurations from every supported released version: keep backward compatibility or migrate older schemas atomically before restoring the audio graph. Never discard an older released configuration just because its schema version changed. If a newer unsupported schema is encountered (for example, after downgrading), leave the file intact, keep mixing off, and show an actionable error. Do not store secrets or audio data in configuration.
- The master switch and app termination stop Sound Mixer capture and output and release app-created taps and other audio resources. Do not leave changes to system output or volume after exit.
- Save every accepted change automatically and atomically. At launch, read and validate the configuration before restoring the audio graph according to the saved master switch state.

## Style

- Prefer a dense interface that avoids large spacing and unnecessary labels. Use icon buttons where they remain clear and accessible, to conserve space.
- Present inputs, outputs, and mixes as consistent compact panels rather than text-list rows. Show live signal-level meters for inputs and outputs, and show levels in mix settings. Panels also show the item's name, state, and icon-based controls, with accessible names and clear status text.
- Use four spaces for indentation in Swift, TypeScript, TSX, JavaScript, JSON, configuration files, and Markdown code blocks. Do not use tabs.
- Format Swift with SwiftFormat and lint it with SwiftLint; format TypeScript and TSX with Prettier and lint them with ESLint. Sort Tailwind classes with the Prettier plugin.
- Pin tool versions and configuration in the repository. CI checks formatting, linting, tests, and builds.
- Use clear names, short functions, and comments that explain the reasons behind complex decisions. Do not add comments that merely repeat the code.
- Write the interface, app system messages, and all repository documentation in English. Use English names for types, files, methods, and APIs.

## Verification

- For the audio engine, test signal level, mono to stereo mapping, routes, cycle prevention, and device changes.
- For integration, test device connection and disconnection, permission denial, the master switch, app exit, and restoration of saved configuration.
- For the interface, test name editing, keyboard accessibility, visible error states, and synchronization of sliders with native state.
- If a required device or permission is unavailable in the development environment, state what was checked automatically and what still needs manual verification on a Mac.

## Working on tasks

- Take tasks from `todo.md` in dependency order, update their status after completion, and do not mark a task complete without meeting its acceptance criterion.
- Never create a Git commit unless the user explicitly asks for a commit. Leave changes in the working tree for the user to review; approval of the implementation or request to publish does not authorize committing.
- Document decisions for unspecified scenarios in the requirements before implementing them.
- When the sandbox blocks a necessary command or file access, immediately request the required sandbox escalation with a concise justification and continue after it is approved. Do not spend time trying alternate cache paths or other workarounds first.
- If Git cannot write its index in the sandbox, request the required escalation and continue the requested Git operation without narrating the routine index-lock failure.

## Releases

- Increase `MARKETING_VERSION` for every public app release and never reuse a version that has been published. Increase `CURRENT_PROJECT_VERSION` for every shipped build. Keep the app bundle version, release tag, and distributed artifact name in sync, and verify the version bump before preparing a release.
- Before changing the configuration schema in a release, implement and verify migration from every released schema version that remains supported. A failed migration must leave the original configuration intact and keep mixing off with a clear error.
