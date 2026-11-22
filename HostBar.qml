import QtQuick
import qs.Commons

// The `bar` one hosted plugin sees. One per cell, because `bar.shell` is how a widget
// reaches its own shell facade and that facade is scoped to a single plugin id.
//
// A whitelist, not the bar itself: the popout coordinator and the click-target registry
// are the container's, so a popup opened inside a container cannot close it.
QtObject {
  id: hostBar

  property var coordinator: null
  property var shell: null
  property string pluginId: ""
  readonly property string moduleName: pluginId

  readonly property var bar: coordinator ? coordinator.bar : null
  readonly property bool inline: coordinator ? coordinator.inline === true : false

  // The strip is horizontal whatever edge the real bar is docked to; inline it is the bar.
  readonly property bool vertical: inline && bar ? bar.vertical === true : false
  readonly property int barSize: inline && bar ? bar.barSize : Style.bar.sizeHorizontal
  // Forwarded: a hosted popup should still open away from the bar's edge.
  readonly property string position: bar ? bar.position : "top"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color background: bar ? bar.background : Color.bar.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool transparent: bar ? bar.transparent : false
  readonly property bool foregroundAnimationEnabled: bar ? bar.foregroundAnimationEnabled : true
  readonly property bool barHidden: bar ? bar.barHidden : false

  // A copy, as the host hands every other widget: a write here must not reach the bar.
  // Read through the bar's own property, or the copy would never be taken again.
  readonly property var layoutConfig: bar && bar.layoutConfig
    ? JSON.parse(JSON.stringify(bar.layoutConfig)) : ({})

  // KeyboardPanel and PopupCard place themselves this far from the screen edge.
  function barSizeFor(screenName) {
    if (inline && bar && typeof bar.barSizeFor === "function") return bar.barSizeFor(screenName)
    if (!inline && coordinator && coordinator.stripReach > 0) return coordinator.stripReach
    return barSize
  }

  readonly property bool centerSectionRevealHeld: false
  readonly property bool centerHoverRevealSuppressed: false
  function setCenterHoverRevealSuppressed(value) {}

  // No card morph between panels: the container's popouts are not the bar's.
  function notePopoutCard(card) {}
  function popoutCardFor(owner) { return null }

  function run(command) { if (bar) bar.run(command) }
  function targetBelongsToWindow(target, window) {
    return bar ? bar.targetBelongsToWindow(target, window) : false
  }

  readonly property var clickTargets: coordinator ? coordinator.clickTargets : []
  readonly property var activePopout: coordinator ? coordinator.activePopout : null

  function moduleWidgets(id) { return coordinator ? coordinator.moduleWidgets(id) : [] }
  function registerClickTarget(target) { if (coordinator) coordinator.registerClickTarget(target) }
  function unregisterClickTarget(target) { if (coordinator) coordinator.unregisterClickTarget(target) }
  function requestPopout(owner) { if (coordinator) coordinator.requestPopout(owner) }
  function releasePopout(owner) { if (coordinator) coordinator.releasePopout(owner) }
  function showTooltip(target, text) { if (coordinator) coordinator.showTooltip(target, text) }
  function hideTooltip(target) { if (coordinator) coordinator.hideTooltip(target) }

  // No neighbouring slot inside a container; forwarding would jump focus out to the bar.
  function switchPanelFrom(owner, direction) { return false }
}
