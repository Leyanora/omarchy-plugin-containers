import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// An open container: its plugins in a row, on a layer surface shaped like the bar.
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  required property var store
  required property var container
  required property var coordinator
  property var owner: null
  property bool open: false

  property int margin: Style.gapsOut
  property int gap: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property color foreground: Color.popups.text
  readonly property var members: container ? container.members : []
  // Merged, not the globals: a container can override the two that shape this card.
  readonly property var options: store.effectiveSettings(root.container ? root.container.id : "")

  // Whether the pointer is anywhere over the card, for the hover-to-open close grace.
  // A HoverHandler, not the swallow MouseArea: the hosted widgets' own areas take hover off it.
  readonly property bool cardHovered: cardHover.hovered
  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  // Hosted instances, so a plugin's broadcast() reaches its peers here, not an empty bar.
  function collectPeers() {
    var out = []
    for (var i = 0; i < repeater.count; i++) {
      var cell = repeater.itemAt(i)
      if (cell && cell.widget) out.push(cell.widget)
    }
    root.coordinator.peers = out
  }

  // A hosted popup can only be measured once this window exists, so not before open.
  function tuneHostedPanels() {
    for (var i = 0; i < repeater.count; i++) {
      var cell = repeater.itemAt(i)
      if (cell && cell.cellWidget) cell.cellWidget.tunePanels()
    }
  }

  readonly property bool horizontalBar: barPos === "top" || barPos === "bottom"
  readonly property var hostBar: coordinator ? coordinator.bar : null
  // Omarchy 4.5's bar window spans the screen; only barSizeFor() still says how thick it is.
  readonly property real barThickness: {
    if (hostBar && typeof hostBar.barSizeFor === "function" && screen)
      return hostBar.barSizeFor(screen.name)
    return horizontalBar ? barH : barW
  }
  readonly property real barOffset: barThickness + gap
  readonly property real cardReach: barOffset + (horizontalBar ? contentHeight : contentWidth)

  Binding {
    target: root.coordinator
    property: "stripReach"
    value: root.cardReach
    when: !!root.coordinator
  }

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "leyanora-plugincontainers-strip"
  WlrLayershell.layer: WlrLayer.Overlay
  // No keyboard focus: hosted popups that want keys still take their own.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Starts at the screen edge, so a hosted panel told the card's reach opens just past it.
  anchors {
    top: root.horizontalBar ? root.barPos === "top" : true
    bottom: root.horizontalBar ? root.barPos === "bottom" : true
    left: root.horizontalBar ? true : root.barPos === "left"
    right: root.horizontalBar ? true : root.barPos === "right"
  }

  implicitWidth: root.horizontalBar ? root.contentWidth : root.barOffset + root.contentWidth
  implicitHeight: root.horizontalBar ? root.barOffset + root.contentHeight : root.contentHeight

  // Only the card takes input; the bar stays clickable underneath.
  mask: Region {
    x: root.horizontalBar ? root.cardAlong : root.cardPerp
    y: root.horizontalBar ? root.cardPerp : root.cardAlong
    width: root.contentWidth
    height: root.contentHeight
  }

  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0

  // mapToItem is a one-shot; the watcher keeps the position binding live.
  TransformWatcher {
    id: anchorWatcher
    a: root.anchorWindow ? root.anchorWindow.contentItem : null
    b: root.anchorItem
  }

  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }

  readonly property real availableWidth: screenW > 0
    ? Math.max(120, screenW - (horizontalBar ? margin * 2 : barOffset + margin))
    : 0
  readonly property real availableHeight: screenH > 0
    ? Math.max(120, screenH - (horizontalBar ? barOffset + margin : margin * 2))
    : 0

  readonly property real contentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)
  readonly property real contentInsetX: padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)

  // From the widget row, never the column: the column's width comes from the card.
  readonly property int contentWidth: Math.round(Math.min(
    Math.max(strip.implicitWidth,
      // The pill's intrinsic width, not the pill: that one is capped by this card.
      // Text measures itself even when hidden, so the flag has to gate the term too.
      root.options.hideTitle ? 0 : titleMetrics.width + Style.spacing.controlPaddingX * 2,
      root.members.length === 0 ? Style.space(260) : 0) + contentInsetX, availableWidth))
  readonly property int contentHeight: Math.round(Math.min(
    layout.implicitHeight + contentInset, availableHeight))

  // What is left for the widgets once the name pill has taken its share.
  readonly property real stripBudget: Math.max(Style.bar.sizeHorizontal,
    availableHeight - contentInset - (title.visible ? title.height + layout.spacing : 0))

  // The card has to clear the bar the surface covers.
  readonly property int cardPerp: barPos === "top" || barPos === "left" ? barOffset : 0

  // The card edge a hosted popup has to clear, in this window's coordinates.
  readonly property real panelBaseline: {
    if (barPos === "bottom" || barPos === "right") return cardPerp
    return horizontalBar ? cardPerp + contentHeight : cardPerp + contentWidth
  }

  // Centred under its button, kept on screen.
  readonly property int cardAlong: {
    if (!anchorItem || !bar) return margin
    var along = horizontalBar
      ? anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      : anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    var limit = horizontalBar ? screenW - contentWidth : screenH - contentHeight
    return Math.round(Math.max(margin, Math.min(along, limit - margin)))
  }

  onOpenChanged: {
    if (open) {
      Qt.callLater(collectPeers)
      Qt.callLater(tuneHostedPanels)
    }
    // Or a hosted popup is left floating with a destroyed anchor.
    else root.coordinator.closeHostedPopouts()

    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // One dismissal surface per monitor, on Top so the card on Overlay stays above them.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dismissWindow
        required property var modelData

        readonly property real strip: root.bar
          ? Math.max(root.bar.barSize, root.barThickness) + root.gap : 0

        screen: modelData
        visible: root.open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "leyanora-plugincontainers-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          x: root.barPos === "left" ? dismissWindow.strip : 0
          y: root.barPos === "top" ? dismissWindow.strip : 0
          width: dismissWindow.width - (root.barPos === "left" || root.barPos === "right"
            ? dismissWindow.strip : 0)
          height: dismissWindow.height - (root.barPos === "top" || root.barPos === "bottom"
            ? dismissWindow.strip : 0)
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  BorderSurface {
    id: card
    x: root.horizontalBar ? root.cardAlong : root.cardPerp
    y: root.horizontalBar ? root.cardPerp : root.cardAlong
    width: root.contentWidth
    height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Math.max(Style.cornerRadius, Style.space(6))
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card so they do not reach the dismissal area.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    HoverHandler {
      id: cardHover
    }

    Column {
      id: layout
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      spacing: Style.spacing.md

      Rectangle {
        id: title
        visible: !root.options.hideTitle
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: Math.min(titleMetrics.width + Style.spacing.controlPaddingX * 2,
          parent.width)
        implicitHeight: titleText.implicitHeight + Style.spacing.xxs * 2
        // A pill, not the card's radius: this one must stay round when rounding is 0.
        radius: height / 2
        color: Style.normalFillFor(root.foreground, Color.accent)

        // Text.implicitWidth reports the *elided* width once elide and width are both set,
        // so measuring the pill off it collapses the card to the narrowest name that fits.
        TextMetrics {
          id: titleMetrics
          font: titleText.font
          text: titleText.text
        }

        Text {
          id: titleText
          anchors.centerIn: parent
          width: Math.min(titleMetrics.width, title.width - Style.spacing.controlPaddingX * 2)
          text: root.container ? root.container.name : ""
          // Container names are user input; AutoText would parse a `<` in one.
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.members.length === 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Glyphs.empty
          color: Qt.darker(root.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }

        Text {
          width: parent.width
          text: "No plugins in this container yet. Open the container manager and drag plugins in."
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      // Capped, not clipped: a container with more rows than the screen has room for used
      // to lose the ones past the edge, with nothing to say they were there.
      Flickable {
        id: stripView
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.members.length > 0
        width: strip.implicitWidth
        height: Math.min(strip.implicitHeight, root.stripBudget)
        contentWidth: width
        contentHeight: strip.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        // Last row of the card, so a popup opened from a widget clears the strip.
        // Intrinsically sized, never `width: parent.width`: contentWidth is measured off it.
        Grid {
          id: strip
          columns: Math.max(1, Math.min(root.options.iconsPerRow, root.members.length))
          horizontalItemAlignment: Grid.AlignHCenter
          verticalItemAlignment: Grid.AlignVCenter
          spacing: Style.spacing.lg

          Repeater {
            id: repeater
            model: root.members

            delegate: Item {
              id: cell
              required property var modelData

              readonly property var widget: hosted.widget
              readonly property var cellWidget: hosted
              readonly property int padding: Style.spacing.sm

              implicitWidth: hosted.implicitWidth + padding * 2
              implicitHeight: hosted.implicitHeight + padding * 2

              // A HoverHandler, not the MouseArea: the widget's own areas take hover off it.
              HoverHandler {
                id: cellHover
              }

              // The cell draws no chrome of its own, so hover is what marks the click target.
              Rectangle {
                anchors.fill: parent
                radius: Math.max(Style.cornerRadius, Style.space(4))
                color: Style.normalFillFor(root.foreground, Color.accent)
                opacity: cellHover.hovered ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
              }

              // Before the widget, so the widget's own mouse areas win where they overlap.
              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                enabled: hosted.routable
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) { hosted.press(mouse.button) }
              }

              HostedWidget {
                id: hosted
                anchors.centerIn: parent
                pluginId: cell.modelData
                label: root.store.pluginInfo(cell.modelData).name
                widgetComponent: root.store.componentFor(cell.modelData)
                source: root.store.entryUrlFor(cell.modelData)
                coordinator: root.coordinator
                store: root.store
                hostSettings: root.store.settingsFor(cell.modelData)
                foreground: root.foreground
                panelBaseline: root.panelBaseline
                barPosition: root.barPos
                tooltipHovered: cellHover.hovered
                onWidgetChanged: Qt.callLater(root.collectPeers)

                // Deferred: the plugin's own tooltip claims the target first where it has one.
                onTooltipHoveredChanged: {
                  if (!hosted.tooltipHovered) {
                    tooltip.hide(hosted)
                    return
                  }
                  Qt.callLater(function () {
                    if (hosted.tooltipHovered && !tooltip.target)
                      tooltip.show(hosted, hosted.fallbackTooltip)
                  })
                }
              }
            }
          }
        }
      }
    }
  }

  // Anchored inside the strip: mapFromItem only works within one window.
  HostTooltip {
    id: tooltip
    anchorItem: layout
    foreground: Color.tooltip.text
  }

  Connections {
    target: root.coordinator
    function onTooltipRequested(target, text) { tooltip.show(target, text) }
    function onTooltipDismissed(target) { tooltip.hide(target) }
  }
}
