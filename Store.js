.pragma library

// Pure state helpers: take a state object, return a new one. No QML, no I/O.

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// The bar draws an icon through its own Text, where AutoText would parse markup in one.
function icon(value) {
  var glyph = String(value || "")
  return glyph.length <= 8 && glyph.indexOf("<") === -1 ? glyph : ""
}

// Same trap, but a name is free text, so strip the `<` rather than drop the whole thing.
// The shell's own bar tooltip renders it with no textFormat of its own.
function label(value) {
  return String(value || "").replace(/</g, "").trim()
}

// The five below mirror BarModel.js in the shell: a bar entry naming no installed plugin
// is a custom module, and this is how the bar itself decides what it is and where it loads
// from. They have to keep tracking that file.
function entrySettings(entry) {
  var out = {}
  if (!isObject(entry)) return out
  for (var key in entry) {
    if (key !== "id") out[key] = entry[key]
  }
  return out
}

function moduleType(entry) {
  var source = entrySettings(entry)
  var type = String(source.type || "")
  if (type) return type
  if (source.exec) return "command"
  if (source.source) return "qml"
  return ""
}

function expandHome(value, home) {
  var path = String(value || "")
  if (path === "") return ""
  if (path.indexOf("~/") === 0) return String(home) + path.substring(1)
  if (path.indexOf("$HOME/") === 0) return String(home) + path.substring(5)
  return path
}

// A name is turned into a path under the config directory, so it must not climb out of it.
function moduleSafeName(name) {
  var value = String(name || "")
  return value !== "" && value.indexOf("..") === -1 && value[0] !== "/"
}

function modulePath(entry, id, home, configDir) {
  var source = entrySettings(entry)
  var path = source.source ? expandHome(source.source, home) : ""
  if (!path && moduleSafeName(id)) {
    path = String(configDir || "") + "/bar/modules/" + String(id) + ".qml"
  }
  return path
}

// Our own container slots are `source:` entries too, so they look exactly like a custom
// qml module. Hosting one would recurse; nothing may ever take one for a member.
function isOwnSlot(id, selfId) {
  return String(id) === String(selfId) || String(id).indexOf(String(selfId) + ".") === 0
}

var DEFAULTS = {
  iconsPerRow: 10,
  hideTitle: false,
  hideBarIcon: false,
  openOnHover: false,
  hideEmpty: false,
  defaultMode: "strip"
}

var MODES = ["strip", "inline"]

function mode(value) {
  return MODES.indexOf(String(value || "")) === -1 ? "" : String(value)
}

function perRow(value) {
  var n = Math.floor(Number(value))
  return n >= 1 && n <= 10 ? n : 0
}

// Global options, repaired the same way as everything else: shell.json is hand-editable.
function settings(raw) {
  var source = isObject(raw) ? raw : {}
  return {
    iconsPerRow: perRow(source.iconsPerRow) || DEFAULTS.iconsPerRow,
    hideTitle: source.hideTitle === true,
    hideBarIcon: source.hideBarIcon === true,
    openOnHover: source.openOnHover === true,
    hideEmpty: source.hideEmpty === true,
    defaultMode: mode(source.defaultMode) || DEFAULTS.defaultMode
  }
}

// A container's own overrides. Only the keys actually set are kept: an absent key
// inherits, which is not the same as a key set to the global's current value.
var OVERRIDABLE = ["iconsPerRow", "hideTitle", "mode"]

function containerSettings(raw) {
  var source = isObject(raw) ? raw : {}
  var out = {}
  if (perRow(source.iconsPerRow)) out.iconsPerRow = perRow(source.iconsPerRow)
  if (source.hideTitle === true || source.hideTitle === false) out.hideTitle = source.hideTitle
  if (mode(source.mode)) out.mode = mode(source.mode)
  return out
}

function hasOverrides(container) {
  return !!container && isObject(container.settings) && Object.keys(container.settings).length > 0
}

// What an open container actually draws with. `mode` is the one key with no global of its
// own name: a container either names one or takes the default.
function effectiveSettings(state, containerId) {
  var out = clone(state.settings)
  var container = containerById(state, containerId)
  var own = container && isObject(container.settings) ? container.settings : {}
  for (var i = 0; i < OVERRIDABLE.length; i++) {
    var key = OVERRIDABLE[i]
    if (own[key] !== undefined) out[key] = own[key]
  }
  out.mode = mode(own.mode) || out.defaultMode
  return out
}

// Repairs anything: fresh install, hand-edited shell.json, an older version's state.
function normalize(entry, selfId) {
  var source = isObject(entry) ? entry : {}
  var containers = []
  var seenIds = {}
  var rawContainers = Array.isArray(source.containers) ? source.containers : []

  for (var i = 0; i < rawContainers.length; i++) {
    var raw = rawContainers[i]
    if (!isObject(raw)) continue
    var id = String(raw.id || "")
    // The slot id is `<module>.<id>`, split on the last dot, so a dot in one aims it elsewhere.
    if (!/^[A-Za-z0-9_-]+$/.test(id) || seenIds[id]) continue
    seenIds[id] = true

    var members = []
    var seenMembers = {}
    var rawMembers = Array.isArray(raw.members) ? raw.members : []
    for (var m = 0; m < rawMembers.length; m++) {
      var pluginId = String(rawMembers[m] || "")
      // Self-membership would recurse; a duplicate gives one plugin two live IpcHandlers.
      if (!pluginId || isOwnSlot(pluginId, selfId) || seenMembers[pluginId]) continue
      seenMembers[pluginId] = true
      members.push(pluginId)
    }

    containers.push({
      id: id,
      name: label(raw.name) || "Container",
      icon: icon(raw.icon),
      members: members,
      settings: containerSettings(raw.settings)
    })
  }

  return { containers: containers, settings: settings(source.settings) }
}

var BLOCK_VERSION = 2

function toBlock(state) {
  return {
    version: BLOCK_VERSION,
    settings: clone(state.settings),
    containers: clone(state.containers)
  }
}

function containerById(state, id) {
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].id === id) return state.containers[i]
  }
  return null
}

function containerIndex(state, id) {
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].id === id) return i
  }
  return -1
}

// Refcount: a plugin leaves the bar at 0 -> 1 and comes back at 1 -> 0.
function holderCount(state, pluginId) {
  var count = 0
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].members.indexOf(pluginId) !== -1) count++
  }
  return count
}

function allMembers(state) {
  var seen = {}
  var out = []
  for (var i = 0; i < state.containers.length; i++) {
    var members = state.containers[i].members
    for (var m = 0; m < members.length; m++) {
      if (seen[members[m]]) continue
      seen[members[m]] = true
      out.push(members[m])
    }
  }
  return out
}

// A counter, not a random id, so shell.json stays readable.
function nextContainerId(state) {
  var n = 1
  while (containerById(state, "c" + n) !== null) n++
  return "c" + n
}

function uniqueName(state, base, exceptId) {
  var wanted = label(base) || "Container"
  var candidate = wanted
  var n = 2
  while (true) {
    var clash = false
    for (var i = 0; i < state.containers.length; i++) {
      var c = state.containers[i]
      if (c.id !== exceptId && c.name.toLowerCase() === candidate.toLowerCase()) clash = true
    }
    if (!clash) return candidate
    candidate = wanted + " " + n
    n++
  }
}

function addContainer(state, name, glyph) {
  var next = clone(state)
  var id = nextContainerId(next)
  next.containers.push({
    id: id,
    name: uniqueName(next, name),
    icon: icon(glyph),
    members: [],
    settings: {}
  })
  return { state: next, id: id }
}

function updateContainer(state, id, name, glyph) {
  var next = clone(state)
  var container = containerById(next, id)
  if (!container) return next
  if (name !== undefined && name !== null) container.name = uniqueName(next, name, id)
  if (glyph !== undefined && glyph !== null) container.icon = icon(glyph)
  return next
}

// Routed through settings() so an out-of-range value from anywhere is still repaired.
function setSetting(state, key, value) {
  var next = clone(state)
  var raw = clone(next.settings)
  raw[key] = value
  next.settings = settings(raw)
  return next
}

// An override is removed by passing undefined, which is what "inherit" means here.
function setContainerSetting(state, id, key, value) {
  var next = clone(state)
  var container = containerById(next, id)
  if (!container || OVERRIDABLE.indexOf(key) === -1) return next
  var raw = clone(container.settings || {})
  if (value === undefined || value === null) delete raw[key]
  else raw[key] = value
  container.settings = containerSettings(raw)
  return next
}

// The whole override block at once, so switching a container off the globals is one write.
function setContainerSettings(state, id, raw) {
  var next = clone(state)
  var container = containerById(next, id)
  if (container) container.settings = containerSettings(raw)
  return next
}

function clearContainerSettings(state, id) {
  var next = clone(state)
  var container = containerById(next, id)
  if (container) container.settings = {}
  return next
}

// Returns the plugins nothing holds any more; deleting a container deletes no plugin.
function removeContainer(state, id) {
  var next = clone(state)
  var index = containerIndex(next, id)
  if (index === -1) return { state: next, released: [] }
  var members = next.containers[index].members.slice()
  next.containers.splice(index, 1)
  var released = []
  for (var i = 0; i < members.length; i++) {
    if (holderCount(next, members[i]) === 0) released.push(members[i])
  }
  return { state: next, released: released }
}

// Every container owns a bar entry of its own, named after the container it draws.
function slotId(moduleName, containerId) {
  return String(moduleName) + "." + String(containerId)
}

function slotContainerId(moduleName, id) {
  var prefix = String(moduleName) + "."
  var value = String(id || "")
  return value.indexOf(prefix) === 0 ? value.substring(prefix.length) : ""
}

function slotIds(state, moduleName) {
  var out = []
  for (var i = 0; i < state.containers.length; i++) {
    out.push(slotId(moduleName, state.containers[i].id))
  }
  return out
}

// The bar is where containers are reordered now, so the model follows the slots.
function orderContainers(state, containerIds) {
  var next = clone(state)
  var rank = {}
  for (var i = 0; i < containerIds.length; i++) {
    if (rank[containerIds[i]] === undefined) rank[containerIds[i]] = i
  }
  var indexed = []
  for (var c = 0; c < next.containers.length; c++) {
    var at = rank[next.containers[c].id]
    // A container with no slot yet keeps its place behind the ones that have one.
    indexed.push({ at: at === undefined ? containerIds.length + c : at, container: next.containers[c] })
  }
  indexed.sort(function (left, right) { return left.at - right.at })
  var out = []
  for (var k = 0; k < indexed.length; k++) out.push(indexed[k].container)
  next.containers = out
  return next
}

// `claimed` means the caller must take the plugin off the bar.
function addMember(state, containerId, pluginId) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container || !pluginId) return { state: next, claimed: false }
  if (container.members.indexOf(pluginId) !== -1) return { state: next, claimed: false }
  var claimed = holderCount(next, pluginId) === 0
  container.members.push(pluginId)
  return { state: next, claimed: claimed }
}

// `released` means the caller must put the plugin back on the bar.
function removeMember(state, containerId, pluginId) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container) return { state: next, released: false }
  var at = container.members.indexOf(pluginId)
  if (at === -1) return { state: next, released: false }
  container.members.splice(at, 1)
  return { state: next, released: holderCount(next, pluginId) === 0 }
}

function moveMember(state, containerId, pluginId, toIndex) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container) return next
  var from = container.members.indexOf(pluginId)
  if (from === -1) return next
  var to = Math.max(0, Math.min(container.members.length - 1, Math.floor(toIndex)))
  if (to === from) return next
  container.members.splice(from, 1)
  container.members.splice(to, 0, pluginId)
  return next
}

// One commit, not a remove plus an add: the refcount never reaches 0, so the plugin
// must not go back to the bar and lose the position its stash record holds.
function moveMemberBetween(state, fromId, toId, pluginId) {
  var next = clone(state)
  if (fromId === toId) return { state: next, moved: false }
  var from = containerById(next, fromId)
  var to = containerById(next, toId)
  if (!from || !to) return { state: next, moved: false }
  var at = from.members.indexOf(pluginId)
  if (at === -1) return { state: next, moved: false }
  from.members.splice(at, 1)
  if (to.members.indexOf(pluginId) === -1) to.members.push(pluginId)
  return { state: next, moved: true }
}

// Bar-bound: the tray draws the `tray` section, the indicators need the bar's services.
var UNHOSTABLE = ["omarchy.tray", "omarchy.indicators"]

function hostable(pluginId) {
  return UNHOSTABLE.indexOf(String(pluginId)) === -1
}

// Drops members naming a widget the bar no longer has.
function prune(state, hostable) {
  var next = clone(state)
  var dropped = []
  for (var i = 0; i < next.containers.length; i++) {
    var container = next.containers[i]
    var kept = []
    for (var m = 0; m < container.members.length; m++) {
      var pluginId = container.members[m]
      if (hostable[pluginId]) kept.push(pluginId)
      else if (dropped.indexOf(pluginId) === -1) dropped.push(pluginId)
    }
    container.members = kept
  }
  return { state: next, dropped: dropped }
}

function equal(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}
