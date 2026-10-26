# Contributing to TidyDock

Thanks for helping! Issues and pull requests in English or Turkish are both fine.

## Reporting a problem with a specific app

Most bugs are about one app behaving differently from the rest. Please include:

- The app's name, version and bundle ID (`osascript -e 'id of app "AppName"'`)
- Your macOS version
- What you did (for example "closed the last window with ⌘W")
- What TidyDock did, and what you expected
- Whether the app had windows on another desktop, minimized, or in full screen

Logs help a lot. Run this, reproduce the problem, then press Ctrl-C and attach the output:

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.utkumeydan.TidyDock"' --level info
```

## Development

Only the Xcode Command Line Tools are needed. You can also open `Package.swift` in Xcode.

```bash
./scripts/test.sh          # unit tests for the decision logic
./scripts/build-app.sh     # build/TidyDock.app, ad-hoc signed
```

Ad-hoc builds get a new signature every time, so macOS forgets the Accessibility permission after each rebuild. To avoid re-granting it, create a self-signed code signing certificate once (Keychain Access › Certificate Assistant › Create a Certificate…, Identity Type: Self Signed Root, Certificate Type: Code Signing) and build with:

```bash
SIGN_IDENTITY="TidyDock Development" ./scripts/build-app.sh
```

### Project layout

| Path | What's there |
|---|---|
| `Sources/TidyDockCore` | Settings, window counting and the quit policy. No AppKit, fully unit tested. |
| `Sources/TidyDock` | The menu bar app: app monitoring, Accessibility, menus, settings window, Sparkle. |
| `Tests/TidyDockCoreTests` | Tests for the core. |
| `Support` | Info.plist, app icon and translations. |
| `scripts` | Build and icon scripts. |

### Guidelines

- Put decisions in `TidyDockCore` and add a test for each new rule.
- When in doubt, don't quit. A missed quit is a small annoyance; a wrong quit can lose someone's work.
- New user-facing text goes through `L("English text")`. Add a translation to every `Support/Localization/*.lproj/Localizable.strings`, then run `./scripts/check-strings.sh`.

### Translations

TidyDock speaks English, Turkish, German, Spanish, French, Italian, Japanese and Simplified Chinese. To add a language, copy `tr.lproj` to `<code>.lproj`, translate the right-hand side of each line, add the code to `CFBundleLocalizations` in `Support/Info.plist`, and run `./scripts/check-strings.sh`. Native speakers reviewing existing translations are very welcome.

### Screenshots and the demo GIF

The README and website images are generated, so they stay up to date in every language:

```bash
./scripts/build-app.sh
./scripts/screenshots.sh "en tr" "dark light"   # docs/screenshots/<lang>/<appearance>/<scene>.png
swift scripts/make-demo-gif.swift en            # docs/demo-en.gif
./scripts/build-site.sh                         # the website, into _site/
```

Screenshot mode uses sample data in a separate defaults domain. It never watches or quits real apps.

### Manual test checklist

Before a release, check these on the latest macOS:

- [ ] Safari, Chrome, Firefox, Arc: closing the last window quits; closing a tab doesn't
- [ ] TextEdit with unsaved text: the save dialog appears; Cancel keeps the app running
- [ ] Preview, Xcode, VS Code, iTerm2, Discord, Slack
- [ ] A window on another desktop and a full-screen window keep the app running
- [ ] Minimized and ⌘H-hidden apps keep running
- [ ] Menu bar apps and login items without windows are never quit
- [ ] Excluded apps are not quit; "only listed" mode quits only listed apps
- [ ] Idle quit works and never quits the front app
- [ ] Shortcuts work; pause survives until TidyDock restarts
- [ ] Launch at login
