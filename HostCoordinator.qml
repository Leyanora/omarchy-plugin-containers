import QtQuick

// Container-scoped state every cell in one container shares: which hosted popup is open,
// which buttons registered a click target, and the instances a broadcast has to reach.
// Kept off the real bar so a popup opened inside a container cannot evict the container.
QtObject {
  id: coordinator

  // The bar this plugin installed, not a facade: the cells sit in its windows.
  property var bar: null

  // Set when the container draws its widgets in its own bar slot rather than in a strip.
  property bool inline: false

  // Screen edge to the strip card's far edge: the bar thickness a hosted panel has to clear.
  property real stripReach: 0

  signal tooltipRequested(var target, string text)
  signal tooltipDismissed(var target)

  // broadcast() should reach the container's instances; the bar has none.
  property var peers: []

  function moduleWidgets(id) {
    var out = []
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].moduleName === id) out.push(peers[i])
    }
    return out
  }

  // Hosted buttons register here so a click on a cell's padding can be routed to one.
  property var clickTargets: []

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(function (item) { return item !== target })
  }

  property var activePopout: null

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  // Or a hosted popup outlives the strip that anchored it.
  function closeHostedPopouts() {
    if (!activePopout) return
    var owner = activePopout
    activePopout = null
    if ("close" in owner) owner.close()
  }

  // The bar only paints tooltips for its own windows, so the strip hosts its own. An inline
  // cell is in that window, so there the real one works and looks like every other widget's.
  function showTooltip(target, text) {
    if (coordinator.inline && coordinator.bar) {
      coordinator.bar.showTooltip(target, text)
      return
    }
    coordinator.tooltipRequested(target, String(text || ""))
  }

  function hideTooltip(target) {
    if (coordinator.inline && coordinator.bar) {
      coordinator.bar.hideTooltip(target)
      return
    }
    coordinator.tooltipDismissed(target)
  }
}
