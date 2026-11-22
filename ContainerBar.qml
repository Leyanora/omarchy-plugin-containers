import QtQuick
import Quickshell
import "Store.js" as Model
import "Layout.js" as Layout
import "Bridge.js" as Bridge

// The bar this plugin installs. It draws nothing itself: it loads the bar Omarchy ships,
// hands it a layout with the contained widgets taken out and a module in place of each
// container, and forwards everything the host reads back off `shell.bar`.
//
// A bar plugin rather than a bar widget because only a full bar is given the widget
// catalogue and a writable bar config; a widget is handed capability facades that can
// reach neither. Loading the installed bar rather than a fork of it means an Omarchy
// update to the bar lands here too.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null

  readonly property string moduleName: manifest && manifest.id
    ? String(manifest.id) : "leyanora.plugincontainers"

  // The hosted bar loads a container's slot from this path, the way it loads any custom
  // qml module. It is never written to shell.json: the projection supplies it per render.
  // A path, not a url: the bar runs it back through Util.fileUrl when it loads the module.
  readonly property string slotSource:
    decodeURIComponent(String(Qt.resolvedUrl("ContainerButton.qml")).replace(/^file:\/\//, ""))

  readonly property var inner: hostLoader.item

  // The bar's single popout token is held by whichever of our surfaces is open, on any
  // monitor. A layout change while one is open would rebuild the bar out from under it.
  readonly property bool surfaceOpen: {
    if (!inner || !inner.activePopout) return false
    var name = String(inner.activePopout.moduleName || "")
    return name === root.moduleName || name.indexOf(root.moduleName + ".") === 0
  }

  Store {
    id: store
    moduleName: root.moduleName
    shell: root.shell
    barWidgetRegistry: root.barWidgetRegistry
    barConfig: root.barConfig
    slotSource: root.slotSource
    home: Quickshell.env("HOME")
    deferLayout: root.surfaceOpen
  }

  readonly property var containerStore: store

  // Read out of the config being projected rather than off the store: a binding that
  // crossed to the store saw last read's containers and built the bar without them, then
  // rebuilt it a frame later once they arrived.
  readonly property var liveContainers:
    Model.normalize(Layout.readBlock(root.barConfig, root.moduleName), root.moduleName).containers

  readonly property var liveConfig:
    Layout.project(root.barConfig, root.liveContainers, root.moduleName, root.slotSource)

  // Held while a surface is open, for the same reason the writes are: reassigning the
  // hosted bar's layout rebuilds every widget on every monitor and takes the surface
  // with it. A whole projection rather than the container list, so what the bar renders
  // is always one consistent read of the config.
  property var renderedConfig: ({})

  Binding {
    target: root
    property: "renderedConfig"
    value: root.liveConfig
    when: !root.surfaceOpen
    restoreMode: Binding.RestoreNone
  }

  // The bar's drag indexes count only what it draws, so its writes are mapped back through these.
  property var renderedContainers: []

  Binding {
    target: root
    property: "renderedContainers"
    value: root.liveContainers
    when: !root.surfaceOpen
    restoreMode: Binding.RestoreNone
  }

  ShellProxy {
    id: shellProxy
    target: root.shell
    moduleName: root.moduleName
    containers: root.renderedContainers
  }

  Component.onCompleted: Bridge.publish(root)
  Component.onDestruction: Bridge.withdraw(root)

  onShellChanged: if (shell) Qt.callLater(store.migrate)

  // Read off `shell.bar` by the host and by first-party panels that anchor to the bar.
  readonly property int barSize: inner ? inner.barSize : 0
  readonly property bool barHidden: inner ? inner.barHidden === true : false
  readonly property string fontFamily: inner ? String(inner.fontFamily || "") : ""
  readonly property string position: inner ? String(inner.position || "top") : "top"
  readonly property var screenBarSizes: inner && inner.screenBarSizes ? inner.screenBarSizes : ({})

  function barSizeFor(screenName) {
    if (inner && typeof inner.barSizeFor === "function") return inner.barSizeFor(screenName)
    return barSize
  }

  // A summon naming a contained plugin has no slot to land on; the container opens instead.
  function containerHolding(id) {
    var containers = store.containers
    for (var i = 0; i < containers.length; i++) {
      if (containers[i].members.indexOf(String(id)) !== -1) return containers[i]
    }
    return null
  }

  function summonBarWidget(id) {
    var container = containerHolding(id)
    if (container && inner) return inner.summonBarWidget(store.slotIdFor(container.id))
    return inner ? inner.summonBarWidget(id) : false
  }

  function hideBarWidget(id) { return inner ? inner.hideBarWidget(id) : false }
  function isBarWidgetOpen(id) { return inner ? inner.isBarWidgetOpen(id) : false }
  // Omarchy 4.5 renamed the two-state toggleTransparency to the three-state cycleBackground.
  function cycleBackground() {
    if (inner && typeof inner.cycleBackground === "function") inner.cycleBackground()
    else if (inner && typeof inner.toggleTransparency === "function") inner.toggleTransparency()
  }
  function toggleTransparency() { cycleBackground() }
  function debugBarGeometry() { return inner ? inner.debugBarGeometry() : [] }
  function panelWidgetIdAt(section, index) {
    return inner ? inner.panelWidgetIdAt(section, index) : ""
  }

  Loader {
    id: hostLoader
    source: "file://" + root.omarchyPath + "/shell/plugins/bar/Bar.qml"

    onLoaded: {
      item.omarchyPath = Qt.binding(function () { return root.omarchyPath })
      item.barWidgetRegistry = Qt.binding(function () { return root.barWidgetRegistry })
      item.pluginRegistry = Qt.binding(function () { return root.pluginRegistry })
      item.shell = Qt.binding(function () { return root.shell ? shellProxy : null })
      item.manifest = Qt.binding(function () { return root.manifest })
      item.barConfig = Qt.binding(function () { return root.renderedConfig })
    }

    onStatusChanged: if (status === Loader.Error)
      console.warn("leyanora.plugincontainers: could not load the Omarchy bar from "
        + hostLoader.source)
  }
}
