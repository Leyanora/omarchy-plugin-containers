import QtQuick
import qs.Commons
import "Store.js" as Model
import "Layout.js" as Layout
import "Migrate.js" as Migrate

// The only reader and writer of container state. One instance, on the bar root: the bar
// is a single object for every monitor, so N of these would race each other.
QtObject {
  id: store

  property string moduleName: ""

  // The capability facade the host hands a full bar. mutateShellConfig is scoped to the
  // `bar` subtree, which is where everything this plugin owns lives.
  property var shell: null

  // The detached widget catalogue. Its entries carry the real Components, so a hosted
  // plugin is instantiated from the same component the bar would have used.
  property var barWidgetRegistry: null

  // The live `bar` subtree, replaced by the host on every shell.json load.
  property var barConfig: ({})

  property string slotSource: ""

  readonly property bool ready: !!shell && typeof shell.mutateShellConfig === "function"

  property string error: ""

  function slotIdFor(containerId) { return Model.slotId(moduleName, containerId) }

  readonly property var block: Layout.readBlock(barConfig, moduleName)

  // Bar order is the truth for container order: a marker entry is dragged like any other
  // widget, and nothing in the block records where the user put it.
  readonly property var state: {
    var raw = Model.normalize(block, moduleName)
    return Model.orderContainers(raw, Layout.slotOrder(barConfig, moduleName))
  }

  readonly property var containers: state.containers
  readonly property var settings: state.settings
  readonly property int containerCount: state.containers.length
  readonly property bool inLayout: Layout.inLayout(barConfig, moduleName)

  function containerById(id) { return Model.containerById(state, id) }
  function holderCount(pluginId) { return Model.holderCount(state, pluginId) }
  function effectiveSettings(containerId) { return Model.effectiveSettings(state, containerId) }
  function hasOverrides(containerId) {
    return Model.hasOverrides(Model.containerById(state, containerId))
  }

  // widgets is a plain object, so reassigning it does not notify on its own.
  readonly property int catalogueRevision: barWidgetRegistry ? barWidgetRegistry.revision : 0

  readonly property var registered: {
    var unused = catalogueRevision
    return barWidgetRegistry && barWidgetRegistry.widgets ? barWidgetRegistry.widgets : ({})
  }

  // A bar entry naming no registered widget is a custom module of the user's own. Its
  // definition lives only in that entry, so it is listed straight from the layout.
  readonly property var customModules: {
    var found = Layout.customModules(barConfig, moduleName, registered, Model.moduleType)
    var out = []
    for (var i = 0; i < found.length; i++) {
      var path = Model.modulePath(found[i].entry, found[i].id, home, configDir)
      if (path === "") continue
      out.push({
        id: found[i].id,
        name: found[i].id,
        description: "Custom bar module — " + path,
        category: "Custom module",
        firstParty: false,
        kind: "qml",
        url: "file://" + path
      })
    }
    return out
  }

  property string home: ""
  readonly property string configDir: home === "" ? "" : home + "/.config/omarchy"

  readonly property var catalogue: {
    var out = []
    var widgets = registered
    for (var id in widgets) {
      if (id === moduleName || !Model.hostable(id)) continue
      var meta = widgets[id] && widgets[id].metadata ? widgets[id].metadata : {}
      out.push({
        id: id,
        name: String(meta.displayName || id),
        description: String(meta.description || ""),
        category: String(meta.category || "Plugin"),
        firstParty: meta.firstParty === true,
        kind: "plugin",
        url: ""
      })
    }
    for (var c = 0; c < customModules.length; c++) out.push(customModules[c])
    out.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
    return out
  }

  readonly property var hostableIds: {
    var map = {}
    for (var i = 0; i < catalogue.length; i++) map[catalogue[i].id] = true
    return map
  }

  function pluginInfo(pluginId) {
    for (var i = 0; i < catalogue.length; i++) {
      if (catalogue[i].id === pluginId) return catalogue[i]
    }
    return { id: pluginId, name: pluginId, description: "", category: "", firstParty: false }
  }

  function componentFor(pluginId) {
    var entry = registered[pluginId]
    return entry ? entry.component : null
  }

  function entryUrlFor(pluginId) {
    for (var i = 0; i < customModules.length; i++) {
      if (customModules[i].id === pluginId) return customModules[i].url
    }
    return ""
  }

  // A member keeps its own bar entry; its inline settings are read straight off it.
  function settingsFor(pluginId) { return Layout.entryFor(barConfig, pluginId) }

  // The host's own per-widget shell facade, the same one the bar would hand this plugin
  // if it were drawing it: writes and lifecycle calls stay scoped to the member's id.
  function shellFor(pluginId) {
    if (!shell || typeof shell.pluginShellForBarEntry !== "function") return null
    return shell.pluginShellForBarEntry(moduleName, String(pluginId))
  }

  // While a container or the manager is open, only the block is written: every mutator
  // here changes bar.layout, and a structural layout change rebuilds the bar and destroys
  // the surface that asked for the change. reconcile() applies the session on close.
  function commit(nextState, mutator, always) {
    if (!ready) {
      store.error = "the shell did not expose mutateShellConfig; state was not saved"
      return false
    }
    var apply = mutator && (always === true || !deferLayout)
    shell.mutateShellConfig(function (config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      if (apply) mutator(config.bar)
      Layout.writeBlock(config.bar, moduleName, Model.toBlock(nextState))
    })
    store.error = ""
    return true
  }

  function createContainer(name, icon) {
    var result = Model.addContainer(state, name, icon)
    commit(result.state, function (bar) {
      Layout.syncSlots(bar, moduleName, containerIdsOf(result.state), "right")
    })
    return result.id
  }

  function updateContainer(id, name, icon) {
    commit(Model.updateContainer(state, id, name, icon), null)
  }

  function deleteContainer(id) {
    var next = Model.removeContainer(state, id).state
    commit(next, function (bar) {
      Layout.syncSlots(bar, moduleName, containerIdsOf(next), "right")
    })
  }

  function containerIdsOf(source) {
    var out = []
    for (var i = 0; i < source.containers.length; i++) out.push(source.containers[i].id)
    return out
  }

  function setSetting(key, value) { commit(Model.setSetting(state, key, value), null) }

  function setContainerSetting(id, key, value) {
    commit(Model.setContainerSetting(state, id, key, value), null)
  }

  function setContainerSettings(id, raw) {
    commit(Model.setContainerSettings(state, id, raw), null)
  }

  function clearContainerSettings(id) {
    commit(Model.clearContainerSettings(state, id), null)
  }

  // Containment moves where a widget is drawn, never whether it is enabled: the entry
  // that keeps the plugin loaded and holds its settings stays exactly where it was.
  function addPlugin(containerId, pluginId) {
    if (!hostableIds[pluginId]) return
    var result = Model.addMember(state, containerId, pluginId)
    commit(result.state, function (bar) {
      Layout.ensureEntry(bar, pluginId, "right")
    })
  }

  function removePlugin(containerId, pluginId) {
    commit(Model.removeMember(state, containerId, pluginId).state, null)
  }

  function movePlugin(containerId, pluginId, toIndex) {
    commit(Model.moveMember(state, containerId, pluginId, toIndex), null)
  }

  function movePluginToContainer(fromId, toId, pluginId) {
    var result = Model.moveMemberBetween(state, fromId, toId, pluginId)
    if (!result.moved) return
    commit(result.state, null)
  }

  // The bar is where containers are ordered, so this rewrites the marker entries and lets
  // the model follow them back. A structural layout change, hence deferred while open.
  function reorderContainer(id, delta) {
    var index = Model.containerIndex(state, id)
    if (index === -1) return
    var to = index + (delta < 0 ? -1 : 1)
    if (to < 0 || to >= state.containers.length) return
    var ids = containerIdsOf(state)
    ids.splice(index, 1)
    ids.splice(to, 0, id)
    commit(Model.orderContainers(state, ids), function (bar) {
      Layout.dropSlots(bar, moduleName)
      Layout.syncSlots(bar, moduleName, ids, "right")
    })
  }

  function restoreAll() {
    var next = Model.clone(state)
    for (var i = 0; i < next.containers.length; i++) next.containers[i].members = []
    commit(next, null)
  }

  // Leaves the bar exactly as it would be without this plugin: every member is already in
  // the layout, so only the markers and the block have to go.
  function prepareUninstall() {
    var next = Model.clone(state)
    next.containers = []
    return commit(next, function (bar) {
      Layout.dropSlots(bar, moduleName)
      delete bar[moduleName]
    }, true)
  }

  // Never before the first registry scan, or every member would be pruned as missing.
  readonly property bool scanned: catalogue.length > 0

  property Timer reconcileTimer: Timer {
    interval: 250
    onTriggered: store.reconcile()
  }

  property bool deferLayout: false
  onDeferLayoutChanged: if (!deferLayout) scheduleReconcile()

  function scheduleReconcile() {
    if (!ready || !scanned || deferLayout) return
    reconcileTimer.restart()
  }

  onScannedChanged: if (scanned) scheduleReconcile()
  onBlockChanged: scheduleReconcile()

  // Self-healing, and idempotent: prunes members whose widget is gone, gives a container
  // back a marker entry that was deleted by hand, and keeps every member's entry present.
  function reconcile() {
    if (!ready || !scanned || deferLayout) return

    var next = Model.prune(state, hostableIds).state
    var ids = containerIdsOf(next)
    var members = Model.allMembers(next)

    var probe = Model.clone(barConfig)
    var slotsChanged = Layout.syncSlots(probe, moduleName, ids, "right")
    // Without an entry the manager has no icon and no way back; hideBarIcon collapses it.
    var entriesChanged = Layout.ensureEntry(probe, moduleName, "right")
    for (var i = 0; i < members.length; i++) {
      if (Layout.ensureEntry(probe, members[i], "right")) entriesChanged = true
    }
    if (!slotsChanged && !entriesChanged && Model.equal(next, state)
      && Model.equal(block, Model.toBlock(state))) return

    commit(next, function (bar) {
      Layout.ensureEntry(bar, moduleName, "right")
      Layout.syncSlots(bar, moduleName, ids, "right")
      for (var m = 0; m < members.length; m++) Layout.ensureEntry(bar, members[m], "right")
    })
  }

  // Reads the 1.x state out of the manager's bar entry and writes it beside the layout,
  // handing every contained plugin its own entry back in the same write.
  function migrate() {
    if (!ready) return false
    var probe = Model.clone(barConfig)
    var sections = Util.barSections
    var centreBox = Array.isArray(sections) && sections.indexOf("centerEnd") !== -1
    if (!Migrate.migrate(probe, moduleName, centreBox)) return false
    shell.mutateShellConfig(function (config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      Migrate.migrate(config.bar, moduleName, centreBox)
    })
    return true
  }
}
