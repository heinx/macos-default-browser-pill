# Browser Pill

A small macOS menu bar app for routing web links to a browser of your choice. The pill shows browser and profile slots: Chrome and Firefox, plus their profiles. Click a slot to select it; click the active slot to cycle in the clicked direction (left half cycles backward, right half cycles forward). Right-click for settings and quit. The selection persists across launches.

## Browser profiles

Right-click the pill and open **Profiles**. Each browser lists the profiles found on disk — Chrome profiles from `~/Library/Application Support/Google/Chrome/Local State`, Firefox profiles from `~/Library/Application Support/Firefox/profiles.ini`. Check the profiles you want to see in the pill, and toggle **Show Browser Icon** to keep or hide the plain browser slot. Selecting a profile slot routes links to that browser with that profile (Chrome via `--profile-directory`, Firefox via `-P`).

## Build and install

Requires macOS 13 or later, Xcode command line tools, Chrome and Firefox. Run `scripts/build.sh`, then copy `build/Browser Pill.app` to Applications and open it. Right-click the pill and choose **Install Browser Switcher**, then approve any macOS confirmation. The app requests the default handler for HTTPS and HTTP in turn. Use **Start at Login** in the right-click menu to enable or disable automatic startup.

Once configured, HTTP and HTTPS links sent to the default browser open in the selected browser without changing the system default each time. Links opened directly by a browser or another app are unaffected. If the selected browser is missing, an alert appears and the link is not opened.
