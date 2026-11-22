.pragma library

// Pure bar-layout helpers: read and rewrite the `bar` subtree of shell.json, and project
// it into the layout the hosted upstream bar actually renders. No QML, no I/O.

// Omarchy 4.5's Util.barSections. Older bars ignore the extra sections, which stay empty.
var SECTIONS = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function entryId(entry) {
  return String(isObject(entry) ? (entry.id || "") : (entry || ""))
}

function layoutOf(barConfig) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var out = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    var entries = layout[SECTIONS[i]]
    out[SECTIONS[i]] = Array.isArray(entries) ? clone(entries) : []
  }
  // A section this list predates still has to reach the bar, or its widgets vanish.
  for (var key in layout) {
    if (!out.hasOwnProperty(key) && Array.isArray(layout[key])) out[key] = clone(layout[key])
  }
  return out
}

function sectionNames(layout) {
  var out = SECTIONS.slice()
  for (var key in layout) {
    if (out.indexOf(key) === -1 && Array.isArray(layout[key])) out.push(key)
  }
  return out
}

// Mutates: the caller is inside mutateShellConfig and wants the section it can splice.
function sectionIn(barConfig, section) {
  if (!isObject(barConfig.layout)) barConfig.layout = {}
  var name = SECTIONS.indexOf(String(section)) === -1 ? "right" : String(section)
  if (!Array.isArray(barConfig.layout[name])) barConfig.layout[name] = []
  return barConfig.layout[name]
}

function locate(barConfig, id) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var key = String(id)
  var names = sectionNames(layout)
  for (var s = 0; s < names.length; s++) {
    var entries = layout[names[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === key)
        return { found: true, section: names[s], index: i, entry: entries[i] }
    }
  }
  return { found: false }
}

function entryFor(barConfig, id) {
  var at = locate(barConfig, id)
  return at.found && isObject(at.entry) ? clone(at.entry) : { id: String(id) }
}

function inLayout(barConfig, id) {
  return locate(barConfig, id).found
}

// State lives beside the layout rather than in our widget's entry: an entry rewrite is a
// structural change to the bar, and rebuilding it destroys whichever surface is open.
function readBlock(barConfig, key) {
  var raw = isObject(barConfig) ? barConfig[String(key)] : null
  return isObject(raw) ? clone(raw) : {}
}

function writeBlock(barConfig, key, block) {
  barConfig[String(key)] = clone(block)
}

function slotPrefix(moduleName) {
  return String(moduleName) + "."
}

function isSlotId(id, moduleName) {
  return String(id).indexOf(slotPrefix(moduleName)) === 0
}

// Bar order is the truth for container order; this is how the model reads it back.
function slotOrder(barConfig, moduleName) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var out = []
  var names = sectionNames(layout)
  for (var s = 0; s < names.length; s++) {
    var entries = layout[names[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (isSlotId(id, moduleName)) out.push(id.substring(slotPrefix(moduleName).length))
    }
  }
  return out
}

// Adds a marker entry for every container that has none and drops the ones left behind.
// It never moves an existing one: dragging a container along the bar is how it is ordered.
function syncSlots(barConfig, moduleName, containerIds, section) {
  var wanted = {}
  for (var i = 0; i < containerIds.length; i++)
    wanted[slotPrefix(moduleName) + containerIds[i]] = true

  var changed = false
  if (!isObject(barConfig.layout)) barConfig.layout = {}
  var names = sectionNames(barConfig.layout)
  for (var s = 0; s < names.length; s++) {
    var entries = barConfig.layout[names[s]]
    if (!Array.isArray(entries)) continue
    for (var e = entries.length - 1; e >= 0; e--) {
      var id = entryId(entries[e])
      if (!isSlotId(id, moduleName) || wanted[id]) continue
      entries.splice(e, 1)
      changed = true
    }
  }

  for (var w in wanted) {
    if (locate(barConfig, w).found) continue
    var target = sectionIn(barConfig, section)
    var self = locate(barConfig, moduleName)
    // Beside the manager's own icon where it has one, so a new container lands in view.
    if (self.found && self.section === String(section)) target.splice(self.index, 0, { id: w })
    else target.push({ id: w })
    changed = true
  }
  return changed
}

function dropSlots(barConfig, moduleName) {
  return syncSlots(barConfig, moduleName, [], "right")
}

// A member has to keep its layout entry: that entry is what keeps the plugin enabled and
// holds its inline settings. Containment only decides whether the bar draws it.
function ensureEntry(barConfig, pluginId, section) {
  if (locate(barConfig, pluginId).found) return false
  sectionIn(barConfig, section).push({ id: String(pluginId) })
  return true
}

function removeEntry(barConfig, pluginId) {
  var at = locate(barConfig, pluginId)
  if (!at.found) return false
  barConfig.layout[at.section].splice(at.index, 1)
  return true
}

function hiddenSet(containers) {
  var out = {}
  for (var i = 0; i < containers.length; i++) {
    var members = containers[i].members || []
    for (var m = 0; m < members.length; m++) out[members[m]] = true
  }
  return out
}

// What the hosted bar is handed: members drop out of the sections and every container
// marker becomes the custom qml module that draws it. Nothing here is written to disk.
function project(barConfig, containers, moduleName, slotSource) {
  var next = isObject(barConfig) ? clone(barConfig) : {}
  var hidden = hiddenSet(containers)
  var known = {}
  for (var c = 0; c < containers.length; c++)
    known[slotPrefix(moduleName) + containers[c].id] = true

  var layout = layoutOf(barConfig)
  var names = sectionNames(layout)
  for (var s = 0; s < names.length; s++) {
    var entries = layout[names[s]]
    var kept = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var id = entryId(entry)
      if (known[id]) {
        kept.push({ id: id, type: "qml", source: String(slotSource) })
        continue
      }
      // A marker whose container is gone would load nothing and collapse to a 0x0 slot.
      if (isSlotId(id, moduleName)) continue
      if (hidden[id]) continue
      kept.push(entry)
    }
    layout[names[s]] = kept
  }
  next.layout = layout
  return next
}

function sameEntry(a, b) {
  return a === b || JSON.stringify(a) === JSON.stringify(b)
}

// Which of `after` kept its place relative to `before`: their longest common subsequence.
function stationary(before, after) {
  var rows = before.length + 1
  var cols = after.length + 1
  var table = []
  for (var r = 0; r < rows; r++) {
    table.push([])
    for (var c = 0; c < cols; c++) table[r].push(0)
  }
  for (var i = before.length - 1; i >= 0; i--) {
    for (var j = after.length - 1; j >= 0; j--) {
      table[i][j] = sameEntry(before[i], after[j])
        ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1])
    }
  }
  var kept = []
  var pairs = []
  i = 0
  j = 0
  while (i < before.length && j < after.length) {
    if (sameEntry(before[i], after[j])) {
      pairs.push([i, j])
      i++
      j++
    } else if (table[i + 1][j] >= table[i][j + 1]) i++
    else j++
  }
  for (var a = 0; a < after.length; a++) kept.push(-1)
  for (var p = 0; p < pairs.length; p++) kept[pairs[p][1]] = pairs[p][0]
  return kept
}

// The bar's indexes count only what it was shown; hidden entries return beside unmoved neighbours.
function editProjected(barConfig, containers, moduleName, edit) {
  var hidden = hiddenSet(containers)
  var known = {}
  for (var c = 0; c < containers.length; c++)
    known[slotPrefix(moduleName) + containers[c].id] = true
  function concealed(entry) {
    var id = entryId(entry)
    return !!hidden[id] || (isSlotId(id, moduleName) && !known[id])
  }

  var layout = isObject(barConfig.layout) ? barConfig.layout : {}
  var view = {}
  for (var key in barConfig) {
    if (key !== "layout") view[key] = clone(barConfig[key])
  }
  view.layout = {}
  var before = {}
  for (var k in layout) {
    if (!Array.isArray(layout[k])) {
      view.layout[k] = clone(layout[k])
      continue
    }
    before[k] = layout[k]
    view.layout[k] = layout[k].filter(function (entry) { return !concealed(entry) })
  }

  var replaced = edit(view)
  if (isObject(replaced)) view = replaced

  for (key in barConfig) {
    if (key !== "layout" && !view.hasOwnProperty(key)) delete barConfig[key]
  }
  for (key in view) {
    if (key !== "layout") barConfig[key] = view[key]
  }

  var edited = isObject(view.layout) ? view.layout : {}
  var out = {}
  for (k in edited) {
    if (!Array.isArray(edited[k])) out[k] = edited[k]
  }
  var names = sectionNames(edited)
  for (k in before) {
    if (names.indexOf(k) === -1) names.push(k)
  }
  for (var n = 0; n < names.length; n++) {
    var name = names[n]
    var old = before[name] || []
    var now = Array.isArray(edited[name]) ? edited[name] : []
    var visible = old.filter(function (entry) { return !concealed(entry) })
    var kept = stationary(visible, now)

    // Hidden entries in old order, keyed by the visible index they followed (-1: the start).
    var after = {}
    var seen = -1
    var anchor = -1
    var stays = {}
    for (var q = 0; q < kept.length; q++) {
      if (kept[q] !== -1) stays[kept[q]] = true
    }
    for (var o = 0; o < old.length; o++) {
      if (!concealed(old[o])) {
        seen++
        if (stays[seen]) anchor = seen
        continue
      }
      if (!after[anchor]) after[anchor] = []
      after[anchor].push(old[o])
    }

    var section = (after[-1] || []).slice()
    for (var e = 0; e < now.length; e++) {
      section.push(now[e])
      if (kept[e] !== -1 && after[kept[e]]) section = section.concat(after[kept[e]])
    }
    if (section.length > 0 || Array.isArray(edited[name]) || Array.isArray(before[name]))
      out[name] = section
  }
  barConfig.layout = out
}

// A bar entry naming no registered widget is a custom module the user wrote. It can be
// contained like anything else, so the picker has to list it beside the plugins.
function customModules(barConfig, moduleName, registered, moduleTypeOf) {
  var out = []
  var layout = layoutOf(barConfig)
  var names = sectionNames(layout)
  for (var s = 0; s < names.length; s++) {
    var entries = layout[names[s]]
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (!id || registered[id] || isSlotId(id, moduleName) || id === String(moduleName)) continue
      if (moduleTypeOf(entries[i]) !== "qml") continue
      out.push({ id: id, entry: clone(entries[i]) })
    }
  }
  return out
}
