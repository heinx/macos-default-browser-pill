# AGENTS.md

## Project

Browser Pill — macOS menu bar app (Swift, AppKit, SPM). Routes http/https links to the selected browser/profile.

## Build

- `./scripts/build.sh` builds `build/Browser Pill.app` (ad-hoc signed).
- App must be relaunched (`pkill -x BrowserPill; open "build/Browser Pill.app"`) to see changes.

## UI changes

- When changing the pill's rendering (`Pill.draw`, slot layout, colors, icon treatment), regenerate the README image with `swift scripts/render-readme-image.swift docs/pill.png` and commit it together with the code change. The script mirrors the app's drawing logic — keep it in sync.

## Git

- Commit after each meaningful change (builds green). Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`.
- Do not push unless asked.

## Notes

- Release flow: push an annotated tag `vX.Y.Z`; the `release` GitHub Actions workflow builds, zips, and publishes the GitHub release.
