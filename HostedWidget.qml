import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One plugin in an open container, built from its manifest rather than the registry.
Item {
  id: root

  required property string pluginId
  required property string label
  required property var hostSettings

  // The catalogue hands out the same Component the bar would have drawn this plugin from.
  // A custom qml module has no registration, so that one is loaded by path instead.
  property Component widgetComponent: null
  property url source: ""

  required property var coordinator
  required property var store

  // Resolved once, never bound: the host creates and caches the facade as a side effect of
  // the lookup, and a binding that reads it re-enters itself.
  property var hostShell: null
  Component.onCompleted: hostShell = store ? store.shellFor(root.pluginId) : null
  // 4.5's WidgetButton calls bar.hideTooltip() unguarded as it hides; unload while bar lives.
  Component.onDestruction: {
    loader.sourceComponent = null
    loader.source = ""
  }
  property color foreground: Color.popups.text

  // Hosted in the bar's own slot, where a panel already measures from the right window.
  property bool inline: false

  // Window-space coordinate of the card edge a hosted popup has to clear.
  property real panelBaseline: 0
  property string barPosition: "top"

  readonly property var widget: loader.item
  readonly property bool failed: loader.status === Loader.Error
    || (!root.widgetComponent && String(root.source) === "")

  // Named for HostTooltip.stillHovered(), which polls this exact property on its target.
  property bool tooltipHovered: false
  readonly property string fallbackTooltip: root.failed ? "failed to load" : root.label

  // Activate the plugin for a click on the cell padding, where it has no handler of its own.
  function press(button) {
    // A panel built lazily inside the plugin does not exist until something opens it.
    tunePanels()

    var target = primaryTarget()
    if (target) {
      target.triggerPress(button)
      return true
    }

    // A plugin using a bare MouseArea registers no target; fall back, most specific first.
    var item = loader.item
    if (!item) return false
    if (typeof item.togglePanel === "function") { item.togglePanel(); return true }
    if (typeof item.toggle === "function") { item.toggle(); return true }
    // The shell's summon contract: `opened` says which way to go.
    if (typeof item.opened === "boolean"
        && typeof item.open === "function" && typeof item.close === "function") {
      if (item.opened) item.close()
      else item.open()
      return true
    }
    // Not a contract, but what widgets name the flag their own button toggles.
    if (typeof item.popupOpen === "boolean") { item.popupOpen = !item.popupOpen; return true }
    return false
  }

  // The cell only offers a pointer cursor for a click it can actually route.
  readonly property bool routable: {
    var item = loader.item
    if (!item) return false
    if (primaryTarget()) return true
    if (typeof item.togglePanel === "function") return true
    if (typeof item.toggle === "function") return true
    if (typeof item.opened === "boolean"
        && typeof item.open === "function" && typeof item.close === "function") return true
    return typeof item.popupOpen === "boolean"
  }

  function ownsItem(item) {
    var node = item
    while (node) {
      if (node === loader.item) return true
      node = node.parent
    }
    return false
  }

  function primaryTarget() {
    var item = loader.item
    if (!item || !root.coordinator) return null
    var targets = root.coordinator.clickTargets || []
    var centre = item.width / 2
    var best = null
    var bestDistance = Infinity
    for (var i = 0; i < targets.length; i++) {
      var target = targets[i]
      if (!target || typeof target.triggerPress !== "function") continue
      if (target.visible === false || target.opacity === 0) continue
      if (!ownsItem(target)) continue
      var mapped = target.mapToItem(item, target.width / 2, target.height / 2)
      var distance = Math.abs(mapped.x - centre)
      if (distance < bestDistance) {
        bestDistance = distance
        best = target
      }
    }
    return best
  }

  // A plugin's panel is a window object, so it hangs off `data` and never off `children`.
  function tunePanels() {
    var host = loader.item
    var window = root.QsWindow.window
    if (!host || !window) return
    var seen = []
    var queue = [host]
    while (queue.length > 0 && seen.length < 400) {
      var node = queue.shift()
      if (!node || seen.indexOf(node) !== -1) continue
      seen.push(node)
      alignPanel(node, window)
      var kids = node.data
      if (!kids) continue
      for (var i = 0; i < kids.length; i++) queue.push(kids[i])
    }
  }

  // KeyboardPanel clears HostBar.barSizeFor(), the card's reach; PopupCard needs its margin.
  function alignPanel(node, window) {
    if (!node || !("anchorItem" in node) || !("contentWidth" in node) || !("open" in node)) return
    var anchor = node.anchorItem
    if (!anchor || !ownsItem(anchor)) return
    if ("centerOnBar" in node && node.centerOnBar) node.centerOnBar = false
    // The anchor window is the bar itself, so the panel's own measurement is already right.
    if (root.inline) return
    if (!("triggerMode" in node) || !("margin" in node)) return

    var at = anchor.mapToItem(window.contentItem, 0, 0)
    var clear = Style.gapsOut
    var wanted
    if (root.barPosition === "bottom") wanted = at.y - root.panelBaseline + clear
    else if (root.barPosition === "left") wanted = root.panelBaseline - (at.x + anchor.width) + clear
    else if (root.barPosition === "right") wanted = at.x - root.panelBaseline + clear
    else wanted = root.panelBaseline - (at.y + anchor.height) + clear
    node.margin = Math.round(Math.max(clear, wanted))
  }

  implicitWidth: slot.width
  implicitHeight: slot.height

  // Reserves the bar's slot height so a widget sized off barSize is not squeezed.
  Item {
    id: slot
    anchors.centerIn: parent
    width: Math.max(loader.implicitWidth, Style.bar.iconSlot)
    height: Style.bar.sizeHorizontal

    Loader {
      id: loader
      anchors.centerIn: parent
      // Synchronous: async would resize the strip under the cursor as each widget lands.
      asynchronous: false
      sourceComponent: root.widgetComponent
      source: root.widgetComponent ? "" : root.source
      onLoaded: {
        injectProps()
        // Twice, as the bar does: a root binding against `bar` reads it before the assignment.
        Qt.callLater(injectProps)
      }

      function injectProps() {
        var target = loader.item
        if (!target) return
        if ("bar" in target) target.bar = cellBar
        if ("moduleName" in target) target.moduleName = root.pluginId
        if ("settings" in target) target.settings = root.hostSettings
        root.tunePanels()
      }
    }

    // Keep a live widget in step with settings written while it is open.
    Connections {
      target: root
      function onHostSettingsChanged() { loader.injectProps() }
      function onPanelBaselineChanged() { root.tunePanels() }
    }

    // Declared after the Loader, so it outlives the widget: children die in creation order.
    HostBar {
      id: cellBar
      coordinator: root.coordinator
      shell: root.hostShell
      pluginId: root.pluginId
    }

    Text {
      anchors.centerIn: parent
      visible: root.failed
      text: Glyphs.warn
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
    }
  }
}
