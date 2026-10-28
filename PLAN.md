# Browser Profiles in the Pill — Plan

Add support for browser profiles in the pill and make the pill a multi-slot selector (not just left/right), where clicking cycles selection in the direction clicked from the active item.

## Goals

- Browser-level and profile-level selection in one pill.
- Profiles are optional: pill renders profiles only for browsers that have them.
- Click behavior: clicking a slot selects it; repeated clicks on the last slot wrap around (cycle) in the direction implied by where the user clicked relative to the active item.
- Persisted selection survives launches.

## Pill layout

The pill stops being a two-slot toggle and becomes a strip of slots:

- One slot per profile that is shown. For browsers with no profiles, the browser itself is one slot.
- Selected slot is highlighted (accent fill behind it), like today but per-slot rather than binary left/right.
- Unselected slots show their icon dimmed, possibly with the profile name in very small text under or over the icon (to be decided during implementation — keep it legible at menu bar size; icon-only with hover tooltip is an option).
- Pill width is computed from the number of slots (e.g. `2 + slots * 30 + (slots - 1) * 4`), not fixed at 70pt.

## Click and cycle behavior

- Clicking a slot: selects that slot immediately (no cycling needed when clicking the target directly).
- Clicking the currently active slot: advances to the next slot to the right of the active slot, wrapping around to the leftmost slot after the rightmost (a cycle).
- Direction: cycling follows the side of the active slot the user clicked — clicking the active slot advances forward (right); a click on the pill outside slots (or a modifier-based backward cycle, e.g. Option-click) steps backward (left). This keeps "cycle in the direction we clicked in from the active item" simple and predictable.
- The selection animation slides the accent fill from the old slot to the new one using the existing Timer-based easing, extended to support arbitrary start/target offsets (per-slot index positions instead of only 0 and 1).

## Profiles

### Discovery

- Chrome: profiles live under `~/Library/Application Support/Google/Chrome/Local State` (JSON key `profile.info_cache`, a dictionary keyed by profile directory name, e.g. `Default`, `Profile 1`). Each entry has `name` (may be empty — fall back to directory name). Display order is derived from the `profile.orders` info. Read once at launch and on menu/profile changes.
- Firefox: profiles from `~/Library/Application Support/Firefox/profiles.ini`. Each `[Profile N]` section has `Name=`, `IsRelative=`, `Path=`. Also read `Default` entry which records the default profile. Firefox profiles do not require launching the app to enumerate; no need to parse containers, keep it simple.
- Both are read with `FileManager` + `JSONSerialization`/`PropertyListSerialization`. No third-party dependencies.
- If a browser is not installed (no bundle ID in `/Applications` etc.) its profiles are not shown.

### Launching with a profile

- Chrome: `open -na "Google Chrome" --args --profile-directory="<dir>"`. Verified: launching via `open` works even when Chrome is already running; if the chosen profile is already the active window's profile, Chrome just focuses.
- Firefox: `open -na "Firefox" --args -P "<name>"` — launches with the named profile. If Firefox is already running with a different profile, this opens a new window in that profile (Firefox supports multiple profiles concurrently).
- Use `Process` with `open` so the app doesn't need to find the binary path of the browsers.

## Persistence

- Store the selection as a compound value, e.g. `chrome|Default` (browser raw value + profile directory or `none`). Use `UserDefaults` key `selection` (new key; keep the old `browser` key as a fallback for migration, delete after migrating).
- On load, validate the stored selection still exists (profile may have been deleted). If invalid, fall back to the browser's default or first available slot.

## Settings (right-click menu)

- Right-click menu gains a **Profiles…** submenu:
  - One item per browser with profiles found (Chrome, Firefox).
  - Each profile item is a checkable row: checkmark = shown in the pill. Toggling shows/hides the profile slot.
  - A "Show browser icon" toggle per browser: when off, only the browser's profiles are shown; when on, the bare browser is shown alongside profiles.
  - "All profiles" / "No profiles" quick toggles per browser.
- Keep existing items (Install Browser Switcher…, Start at Login, Quit) unchanged.
- Toggles persist in `UserDefaults` (e.g. `shownProfiles` as a `[String: [String]]` keyed by browser raw value holding profile directory names, or a single list of `browser:profile` compound keys).

## Implementation steps

1. Model: replace the `Browser` enum cases with a struct/array-based `Slot` model (`browser`, `profile?`, `title`, `icon`). Keep a static list of browsers with bundle IDs and display order.
2. Profile discovery for Chrome and Firefox as described above, with caching and error fallback (missing files → no profiles).
3. Rework `Pill` to lay out N slots, compute width, per-slot drawing (icon + optional profile name), per-slot highlight.
4. Rework click handling: hit-test slot under the click; implement forward/backward cycling from active slot; wire Option-click as backward cycle.
5. Selection persistence: new compound `selection` key with migration from `browser`.
6. Launch-with-profile via `open` + `--profile-directory=` / `-P`.
7. Right-click menu: Profiles… submenu with show/hide toggles, persisted.
8. Rebuild the slot list whenever profiles or visibility settings change; keep the pill centered at stable width when possible.
9. Update `README.md` to document profiles, cycling click behavior, and the new menu items.

## Testing

- Manual: build with `scripts/build.sh`, run, click each slot, cycle across boundaries (rightmost → leftmost), Option-click cycle backward, toggle profiles on/off from menu, quit and relaunch to verify persistence, remove a profile in Chrome/Firefox and relaunch to verify fallback.
- Profile parsing: add a small swift test for `Local State` JSON and `profiles.ini` parsing against fixture files.
