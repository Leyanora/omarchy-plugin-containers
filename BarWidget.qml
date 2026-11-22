import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs
import "Bridge.js" as Bridge

// The manager's bar button. It owns no state: the bar root does, and every container slot
// reads the same store through the same library handle.
BarWidget {
  id: root
  moduleName: "leyanora.plugincontainers"

  property bool manageOpen: false

  // Bar.findPanelWidget requires opened/open/close on the bar-widget root.
  readonly property bool opened: manageOpen

  property var host: Bridge.host()
  Component.onCompleted: if (!host) host = Bridge.host()

  readonly property var store: host ? host.containerStore : null

  // The instance a summon should land on. Opening on every screen makes the
  // second one evict the first through the bar's shared popout coordinator.
  function firstInstance() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.length > 0 ? items[0] : root
  }

  function openManager() { manageOpen = true }

  function toggleManager() {
    if (manageOpen) close()
    else openManager()
  }

  function openContainerNamed(name) {
    if (!store || !host) return false
    var wanted = String(name || "").trim().toLowerCase()
    for (var i = 0; i < store.containers.length; i++) {
      if (store.containers[i].name.toLowerCase() !== wanted) continue
      return host.summonBarWidget(store.slotIdFor(store.containers[i].id)) === true
    }
    return false
  }

  // Every strip is a slot of its own, so closing them all means visiting each one. The
  // bar facade only answers for this widget's id; the plugin's own bar knows the rest.
  function closeAll() {
    root.close()
    if (!store || !host || !host.inner) return
    for (var i = 0; i < store.containers.length; i++) {
      var items = host.inner.moduleWidgets(store.slotIdFor(store.containers[i].id))
      for (var j = 0; j < items.length; j++) {
        if (items[j] && typeof items[j].close === "function") items[j].close()
      }
    }
  }

  // close() is also how the bar's popout coordinator evicts this widget.
  function open() { openManager() }
  function close() { manageOpen = false }
  function togglePanel() {
    if (opened) close()
    else openManager()
  }
  function restoreAll() { if (store) store.restoreAll() }
  function prepareUninstall() { return !!store && store.prepareUninstall() }
  function refresh() { if (store) store.reconcile() }
  function setIconHidden(hidden) { if (store) store.setSetting("hideBarIcon", hidden === true) }

  // The bar gives an invisible module no width. Removing the entry instead would take the
  // manager's only way back with it, so hiding the icon always leaves the entry in place.
  readonly property bool iconHidden: !store || store.settings.hideBarIcon

  visible: !iconHidden
  implicitWidth: iconHidden ? 0 : boxButton.implicitWidth
  implicitHeight: iconHidden ? 0 : boxButton.implicitHeight

  // No tint when open: the bar already draws an open-panel indicator for the slot.
  BarIconButton {
    id: boxButton
    bar: root.bar
    text: Glyphs.app
    tooltipText: !root.store || root.store.containerCount === 0
      ? "Plugin containers — group bar widgets"
      : "Plugin containers — manage"
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) root.closeAll()
      else root.toggleManager()
    }
  }

  // Built only once there is a store: the stock bar draws this button before ours publishes.
  LazyLoader {
    active: !!root.store

    ManagePanel {
      anchorItem: boxButton
      bar: root.bar
      owner: root
      open: root.manageOpen
      store: root.store
    }
  }

  IpcHandler {
    target: "leyanora.plugincontainers"

    function open(): void { root.firstInstance().openManager() }
    function close(): void { root.firstInstance().closeAll() }
    function show(): void { root.firstInstance().openManager() }
    function hide(): void { root.firstInstance().closeAll() }
    function toggle(): void { root.firstInstance().togglePanel() }
    function manage(): void { root.firstInstance().openManager() }
    function refresh(): void { root.firstInstance().refresh() }

    // The way back when the box is hidden and there is no container left to right-click.
    function showIcon(): void { root.firstInstance().setIconHidden(false) }
    function hideIcon(): void { root.firstInstance().setIconHidden(true) }

    // Empty containers while retaining their definitions and bar slots.
    function restoreAll(): void { root.firstInstance().restoreAll() }

    // Required deterministic cleanup before the standard Omarchy remove command.
    function prepareUninstall(): string {
      return root.firstInstance().prepareUninstall() ? "ok" : "failed"
    }

    function openContainer(name: string): void { root.firstInstance().openContainerNamed(name) }
  }
}
