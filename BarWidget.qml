import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "billy.ytdl"

  readonly property bool isDownloading: panelLoader.item ? panelLoader.item.isDownloading : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "billy.ytdl"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf16a"
    slotSize: Style.bar.statusSlot
    tooltipText: root.isDownloading ? "YouTube Downloader (Downloading...)" : "YouTube Downloader"

    Rectangle {
      visible: root.isDownloading
      width: Style.space(4)
      height: Style.space(4)
      radius: Style.space(2)
      color: Color.accent
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)

      SequentialAnimation on opacity {
        running: root.isDownloading
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 600 }
        NumberAnimation { to: 1.0; duration: 600 }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton && panelLoader.item) {
        panelLoader.item.pasteFromClipboard()
      } else {
        root.togglePanel()
      }
    }
  }
}
