import QtQuick
import "Layout.js" as Layout

// The hosted bar's `shell`: the host's, but layout writes are made against the projection.
QtObject {
  id: proxy

  property var target: null
  property string moduleName: ""
  // The containers behind the projection the bar is drawing, held with it while a surface is open.
  property var containers: []

  readonly property string pluginId: target ? String(target.pluginId || "") : ""
  readonly property var appLibrary: target ? target.appLibrary : null
  readonly property var bar: target ? target.bar : null
  readonly property var barConfig: target ? target.barConfig : ({})
  readonly property var idleConfig: target ? target.idleConfig : ({})

  function serviceFor(id) { return target ? target.serviceFor(id) : null }
  function firstPartyServiceFor(id) { return target ? target.firstPartyServiceFor(id) : null }
  function pluginShellForBarEntry(ownerId, moduleName) {
    return target ? target.pluginShellForBarEntry(ownerId, moduleName) : null
  }
  function summon(id, payloadJson) { return target ? target.summon(id, payloadJson) : false }
  function hide(id) { return target ? target.hide(id) : false }
  function toggle(id, payloadJson) { return target ? target.toggle(id, payloadJson) : false }
  function isPluginOpen(id) { return target ? target.isPluginOpen(id) : false }
  function updateEntryInline(id, settings) {
    return target ? target.updateEntryInline(id, settings) : false
  }

  function mutateShellConfig(mutator) {
    if (!target || typeof mutator !== "function") return false
    var held = proxy.containers
    var name = proxy.moduleName
    return target.mutateShellConfig(function (config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      Layout.editProjected(config.bar, held, name, function (view) {
        var scoped = { bar: view }
        mutator(scoped)
        return scoped.bar
      })
    })
  }
}
