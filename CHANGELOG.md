# Changelog

## 2.1.0

Omarchy 4.5 compatibility ([#2](https://github.com/Leyanora/omarchy-plugin-containers/issues/2)).

### Fixed

- **Widgets in `centerBegin`, `centerEnd` and `tray` vanished from the bar.** The layout
  handed to the hosted bar now carries all six 4.5 sections, and any section it does not
  know is passed through. A member or container sitting in one of them is found where it
  is, rather than duplicated into `right`.
- **An open container drew nothing in strip mode.** The 4.5 bar window spans the whole
  screen, so the strip measured the bar as screen-tall and put its card off-screen. It
  now asks the bar for its thickness (`barSizeFor`), notch floor included, and clicking
  outside the strip closes it again.
- A hosted plugin's keyboard panel opens just past the strip card instead of on top of
  it.
- The manager panel is built only once the store exists, which silences the burst of
  `Cannot read property … of null` errors at start-up.
- A hosted widget is unloaded before its bar facade goes, so tearing a container down no
  longer logs `hideTooltip is not a function`.
- `omarchy-shell shell toggleBarTransparency` works with this bar again (`cycleBackground`),
  and notifications and panels see the per-screen bar size.

- **Dragging a widget along the bar did nothing** whenever a contained widget sat before
  it. The bar counted positions over what it draws and wrote them into the full layout,
  where the hidden widgets shifted them, so the move was rejected. The bar's layout writes
  now go through the projection, and contained widgets keep their place beside the
  neighbours that did not move.

### Changed

- The tray (`omarchy.tray`) can no longer be put in a container: it draws the bar's
  `tray` section in its drawer, so containing it would hide every widget in that section.
  Widgets *in* the tray section can still be contained.
- The built-in indicators (`omarchy.indicators`: do not disturb, night light, stay awake
  and the rest) can no longer be put in a container either. They rely on bar services a
  hosted widget is not given. A container that already holds them lets them go back to
  the bar.
- A config last written while this plugin was the bar still has the pre-4.5 centre
  (`centerAnchor`), because Omarchy's own migration skips third-party bars. It is split
  into `centerBegin` / `center` / `centerEnd` the same way on first start.

## 2.0.0

Omarchy 4.0.0.alpha put third-party bar widgets behind capability facades that
expose neither the widget catalogue nor a writable bar config. A container needs
both to draw another plugin's widget, and only a full bar plugin is given them,
so this is now a bar rather than a widget in one.

### Changed

- **The plugin is the bar.** It loads the bar Omarchy ships, from its installed
  path and unmodified, and hands it a layout with contained widgets left out and
  a container button in their place. Bar updates from Omarchy land here too.
  Enable it with `omarchy plugin enable leyanora.plugincontainers`; go back with
  `omarchy plugin enable omarchy.bar`.
- **Containing a plugin no longer moves it.** Its bar entry stays where it is,
  with its settings, so it stays enabled by the ordinary rule. Only what the bar
  is asked to draw changes. The invisible placeholder entries, the stash, the
  enablement bookkeeping and the teardown restore are all gone with the problem
  they solved.
- **State moved beside the layout**, to `bar["leyanora.plugincontainers"]`, so
  editing a container no longer rewrites `bar.layout` and no longer rebuilds the
  bar. Container order still comes from the bar.
- A container's bar entry holds nothing but its id. No path to the installation
  is written to `shell.json` any more.
- A hosted plugin now receives the host's own per-widget shell facade rather than
  a proxy of this plugin's, so its settings writes and lifecycle calls are scoped
  by the shell itself.

### Migration

Automatic, on first run: the 1.x state is read out of the manager's bar entry,
written to the new block, and every contained plugin gets its own entry back at
the position and with the settings its stash record recorded.

### Known limitation

Any third-party bar rendering a widget is given a service-less shell facade by
the host, so a plugin that pairs a bar widget with a service sees
`shell.serviceFor()` return null while this bar is active. First-party widgets
are unaffected.

### Removed

- `Stash.js`, `KeepAliveWidget.qml` and `HostShell.qml`, along with the
  `stashed` config key and the `disabledPlugins` bookkeeping.

## 1.1.1

### Fixed

- Contained manifest plugins keep an invisible layout placeholder, so Omarchy
  still treats them as enabled and their service, panel and overlay entry points
  keep running.
- The placeholder mirrors safe widget settings for services such as Bambu
  Companion that read configuration specifically from `bar.layout`.
- Removing a plugin, deleting a container, restoring everything or running the
  manual pre-uninstall cleanup now removes only enablement state created by the
  container and restores an explicit disabled state that existed beforehand.
- Settings written by a service, panel or hosted widget while contained stay in
  sync and return to the restored bar entry without allowing executable
  bar-entry keys to be introduced.
- Existing 1.1.0 stashes are upgraded automatically during reconciliation.
- Added `prepareUninstall`, a deterministic manual cleanup command to run before
  `omarchy plugin remove`. Direct removal remains best-effort because current
  Omarchy has no synchronous pre-remove hook for plugins.

## 1.1.0

The release for having more than one container: moving plugins between them,
ordering them from the manager, and letting each one look and open its own way.

### Added

- **Move a plugin between containers** with **>** on its row. One write, so it
  never touches the bar in between and keeps the position it would go back to.
- **Reorder containers from the manager** with the up and down buttons, writing
  the bar order that has always been the source of truth. Dragging the icons in
  the bar still works and still wins.
- **Any glyph as a container icon**, from the field under the icon grid.
- **Per-container settings.** A container can be taken off the globals and then
  wraps, labels and opens itself its own way.
- **Expand in the bar.** A container opens in place instead of dropping a strip,
  with the open mark drawn across the whole group. Global default, or per
  container.
- **Open a container on hover.** It closes shortly after the pointer leaves,
  unless something opened from inside it is still up.
- **Hide a container while it is empty.** Refused, like hiding the box, when it
  would leave nothing of this plugin in the bar to get back through.
- **Custom qml bar modules can be contained.** Their definition lives only in
  their `bar.layout` entry, so a container holds on to it and writes it back
  untouched.
- A write that does not land now says so in the manager instead of failing
  silently.
- An open container that outgrows the screen scrolls instead of losing its last
  row off the edge.

### Changed

- **A contained plugin can no longer put a command in its own bar entry.** A
  settings write from a hosted widget was already refused `source`, which the bar
  loads as QML; it is now refused `type`, `exec` and the `onClick` /
  `onRightClick` / `onMiddleClick` commands as well, all of which the bar acts on
  once the entry goes back. Entries that already carry them keep them.

## 1.0.0

The first release with settings of its own, and the first that cleans up after
itself.

### Added

- **Settings view in the manager**, behind the cog beside `CONTAINERS`.
- **Icons per row** (1–10), where an open container wraps onto another row.
- **Hide the container name.** The bar tooltip still shows it.
- **Hide the plugin containers icon.** Frees the box's bar slot without disabling
  anything — the plugin keeps running, so containers still work. Get back in by
  right-clicking a container icon or with the new `showIcon`. Refused while there
  are no containers, which would leave no way back but IPC.
- `hideIcon` / `showIcon` IPC verbs.

### Changed

- **Contained plugins go back to the bar automatically** when the plugin is
  removed or disabled: each container's own bar entry outlives the disable and
  empties itself onto the bar. Best-effort — `restoreAll` first is still the
  certain path.
- Removing the plugin no longer leaves its containers' `bar.layout` entries
  behind pointing at deleted files.
- The plugin's `shell.json` entry gained a `settings` key alongside `containers`
  and `stashed`.
