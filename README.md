# Archive Player — macOS app

A small Cocoa wrapper around the single-page player: a real app with a Dock
icon, a menu bar icon, and the page running at a proper web address instead of
a file path.

## Build

    ./build.sh
    open ArchivePlayer.app

Needs Apple's command line tools (`xcode-select --install`) and nothing else —
no Xcode project, no packages. The build takes a few seconds and leaves
`ArchivePlayer.app` beside the script. Drag it to /Applications if you want it
there.

The first launch may warn that the app is from an unidentified developer, since
it is signed with an ad-hoc signature rather than a paid certificate. Right
click the app, choose Open, and confirm once; after that it opens normally.

## What the app does differently from opening the file

The page is served to the window by a tiny web server inside the app, bound to
the loopback interface only, at `http://127.0.0.1:8787/`. That gives the page a
real origin, which is the thing YouTube's player insists on — so clips play in
the floating window instead of showing "video player configuration error (153)",
and archive.org's own embeds behave too.

Because the address is fixed, everything the page saves in that browser storage
— pins, history, the Supadata key, filter settings — stays put from one launch
to the next. If port 8787 is already taken the app steps up through 8788 and
beyond; the page then has a different address, so it would start with empty
storage. Quitting whatever holds 8787 puts it back.

## The icons

Both the Dock tile and the menu bar icon use the same twenty pixel marks the
page cycles through, on the same ten-minute clock, so all three change together
and agree on which mark is current. The menu bar version is a template image,
so it follows light and dark menu bars on its own. The Finder icon is fixed —
the original three play heads on a dark plate.

## The menu bar item

    Show Player
    Reload
    Open in Browser
    Copy Address
    Quit Archive Player

Closing the window leaves the app running in the menu bar; Show Player brings it
back, as does clicking the Dock icon.

## Notes

- **Links out** (watch on youtube, source links, anything leaving the player)
  open in your default browser rather than inside the app window.
- **SEND TXT** saves the transcript into your Downloads folder and reveals it in
  the Finder.
- **Updating the page**: drop a newer `archive-video-player.html` into
  `Resources/` and run `./build.sh` again. Your saved pins and history are kept,
  since they belong to the address, not the file.
- The server answers only `/`, only on loopback, and serves only that one page.
  Nothing on your network can reach it.

## Files

    build.sh                           compiles and assembles the app
    Info.plist                         bundle settings
    Sources/main.swift                 the whole app: window, server, icons, menus
    Resources/archive-video-player.html the page itself
    Resources/AppIcon.icns             the Finder/Dock icon
