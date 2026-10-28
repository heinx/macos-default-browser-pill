# Browser Pill

A small macOS menu bar app for routing web links to Chrome (left) or Firefox (right). Click anywhere on the pill to switch browsers; right-click for settings and quit. The selection persists across launches.

## Build and install

Requires macOS 13 or later, Xcode command line tools, Chrome and Firefox. Run `scripts/build.sh`, then copy `build/Browser Pill.app` to Applications and open it. Right-click the pill and choose **Install Browser Switcher**, then approve any macOS confirmation. The app requests the default handler for HTTPS and HTTP in turn. Use **Start at Login** in the right-click menu to enable or disable automatic startup.

Once configured, HTTP and HTTPS links sent to the default browser open in the selected browser without changing the system default each time. Links opened directly by a browser or another app are unaffected. If the selected browser is missing, an alert appears and the link is not opened.
