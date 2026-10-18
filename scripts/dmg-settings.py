# dmgbuild settings for the HBS EasyIP MAC install window.
# Used by scripts/build-app.sh:  dmgbuild -s scripts/dmg-settings.py -D app=... -D background=... -D icon=... "HBS EasyIP MAC" out.dmg
# Window size and icon centres must match scripts/make-dmg-background.swift.
import os

app = defines["app"]  # noqa: F821  (injected by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821  volume icon

background = defines["background"]  # noqa: F821  multi-resolution TIFF (@1x + @2x)
# Background is 460 pt; with the 28 pt title bar of macOS ≤ 15 it fits exactly, while the
# macOS 26 tab bar hides only the spare bottom 40 pt of the footer.
window_rect = ((200, 140), (660, 488))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    app_name: (170, 200),
    "Applications": (490, 200),
}
