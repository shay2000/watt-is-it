# AGENTS.md

Guidance for agents working in this repository.

## Project overview

Watt is it? is a small native macOS menu-bar utility (Swift, no Xcode project) that shows charger wattage on Apple silicon. It builds with a plain `swiftc` invocation, ad-hoc code signing, and no test or lint targets.

## Building locally

```sh
./build_app.sh
```

Produces `build/WattIsIt.app` (arm64, deployment target macOS 14.6). `build/` and `release/` are gitignored.

## Releasing a new version

The release is triggered by pushing a `v*` tag. The GitHub Actions workflow `.github/workflows/release-dmg.yml` builds the DMG on an arm64 `macos-14` runner, verifies the tag matches the app version, packages `WattIsIt-<version>-macOS-arm64.dmg`, and creates/updates the GitHub release with notes pulled from `CHANGELOG.md`.

Every release must update these in a single release commit before tagging:

1. `Info.plist`: bump `CFBundleShortVersionString` (e.g. `1.1.9`) and `CFBundleVersion` (increment the integer).
2. `CHANGELOG.md`: add a `## <version> - YYYY-MM-DD` section with release bullets at the top.
3. `Sources/WattIsIt/AppDelegate.swift`: add a matching `(<version>, [...])` entry as the first item in `makeChangelogSubmenu()`.
4. `README.md`: update the Features and Using-the-menu bullets when user-facing behavior changed. Leave the top-of-file DMG download link untouched (the `releases/latest/download/...` URL resolves automatically once the release exists).
5. Commit, push, then tag and push to trigger the build:

```sh
git tag -a v<version> -m "Release <version>"
git push origin v<version>
```

### Release workflow rules and caveats

- The tag must equal `v` + `CFBundleShortVersionString`; otherwise the workflow fails deliberately (prevents shipping a DMG that reports the wrong version).
- If a GitHub release already exists for the tag, the workflow uploads the DMG to it; otherwise it creates the release titled `Watt is it? <version>`.
- The DMG asset must stay named `WattIsIt-<version>-macOS-arm64.dmg`: the app's in-app updater (`Sources/WattIsIt/UpdateService.swift`) only downloads assets matching that prefix/suffix.
- Release notes come from the `CHANGELOG.md` section for that version; if the section is missing the workflow fails.
- Track a release run with `gh run list --workflow "Release DMG"` and `gh run watch <run-id>`.
