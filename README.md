# plasma-icontasks-tint

A KDE Plasma widget that tints all task bar icons to a single hue and spins them while the
mouse hovers over them. Pinned launchers and open windows can be tinted separately; a hovered
icon always shows its real colours.

Tested on Plasma 6.7, Wayland, Qt 6.11.

## Install

```
./install.sh            # builds the widget and restarts the Plasma shell
./migrate.py            # replaces the stock Icons-Only Task Manager in every panel
```

`migrate.py` edits `~/.config/plasma-org.kde.plasma.desktop-appletsrc` and backs it up first.
Pinned launchers survive the swap: an applet's settings are keyed by its *number*, not by its
plugin name, so rewriting the `plugin=` line is enough.

If you would rather drag the widget into a panel yourself, just skip `migrate.py`.

## Settings

Right-click the panel → Configure → **Appearance**, section *Einfärbung der Symbole*. One colour
picker and one strength slider each for pinned launchers and for open windows. At strength 0 the
tint is off. Every panel is configured separately.

Spin duration, settle time and the shrink factor applied while spinning are constants at the top of
`patch/HoverSpin.qml`; run `./install.sh` again after changing them.

Note: the widget's own UI strings are currently German only.

## How it works

The stock task manager's QML does not exist as files — it is compiled into
`org.kde.plasma.taskmanager.so` as a Qt resource. `extract.py` `dlopen`s that library, which makes
its static initialiser register the resource, and then reads it back out through `QFile`. Two small
patches are applied to the result, which is then installed as a standalone widget.

**This repository contains no KDE source code.** It is extracted from your locally installed Plasma
library on every install. That keeps the project update-proof: after a Plasma upgrade, another
`./install.sh` rebases onto the new sources. If a patch no longer applies, the script aborts
instead of writing a broken package.

### Why a separate widget instead of a fork

Forking the stock `org.kde.plasma.icontasks` under its own ID does not work:

- **Without `X-Plasma-RootPath`** your own files are used, but the applet library is never loaded,
  so the C++ type `Backend` is missing. Loading it as a QML module afterwards is impossible — it is
  a Plasma applet plugin, not a `QQmlEngineExtensionPlugin`.
- **With `X-Plasma-RootPath`** the module loads, but Plasma redirects the whole package to the
  compiled resource and ignores your files entirely.

Hence a separate widget ID, with the compile-only types `Backend` and `SmartLauncherItem` *replaced*
by QML stubs under `tmlocal/` rather than obtained.

### What that costs

- No jump lists, "recent documents" or "places" entries in the context menu.
- No unread-count badges and no progress bars on the icons.
- No pinning by dragging a `.desktop` file onto the panel.
- Audio streams are matched to windows less reliably.

Still working: activate, close, pin from the menu, grouping, tooltips, attention highlighting and
drag-to-reorder.

### Two traps, if you are building something similar

The stock code checks **its own identity** in nine places
(`Plasmoid.pluginName === "org.kde.plasma.icontasks"`), among them the icons-only mode in `main.qml`
and the icon spacing in `LayoutMetrics.js`. Your replacement must cover **all** files, not just
`*.qml` — miss the `.js` ones and open windows render wide with labels, or the configured icon
spacing is silently ignored.

`MultiEffect` applies `saturation` **after** colorization. Setting `saturation: -1` together with a
tint yields grey, not the tint colour. Colorization alone is enough and already forces a single hue,
because it maps every pixel onto `tintColor` times luminance.

## Tests

```
./tests/run.sh          # everything
```

The QML components are checked headless via `qml -platform offscreen`. Careful on systems with Qt 5
and Qt 6 side by side: the Qt 6 interpreter is required, because under Qt 5 an unversioned
`import QtQuick` silently loads nothing and the test would assert against an empty scene.
`tests/run.sh` picks the right one by itself.

Note that `layer.effect` cannot be verified headless at all — the software scene graph Qt loads with
`-platform offscreen` ignores layer composition entirely. That path is only covered by looking at a
real panel.

## Uninstall

```
./migrate.py --zurueck  # puts the stock widgets back into the panels
./uninstall.sh          # removes the widget
```

## Licence

GPL-2.0-or-later, see `LICENSE`.

The patches under `patch/` modify QML from KDE Plasma's task manager widget (`plasma-desktop`,
copyright Eike Hein and contributors, GPL-2.0-or-later), so this project carries the same licence.
