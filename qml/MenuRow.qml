import QtQuick
import LocalTube

// One row of the settings/context menus (ytp-menuitem).
Item {
    id: row

    property var icon: null
    property string label
    property string value
    property bool submenu: false
    property bool checkable: false
    property bool checked: false
    property bool hasToggle: false
    property bool toggled: false
    property bool big: false
    property bool iconColumn: true
    property real rowHeight: big ? 56 : 48
    readonly property bool hovered: mouse.containsMouse

    signal clicked()
    activeFocusOnTab: enabled && visible
    Accessible.role: hasToggle ? Accessible.CheckBox : Accessible.MenuItem
    Accessible.name: label + (value ? ", " + value : "")
    Accessible.checkable: checkable || hasToggle
    Accessible.checked: hasToggle ? toggled : checked
    Accessible.onPressAction: if (enabled) row.clicked()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            row.clicked()
            event.accepted = true
        }
    }

    implicitHeight: rowHeight
    implicitWidth: labelText.x + labelText.implicitWidth + 24 + valueText.implicitWidth
                   + (submenu ? 22 : 0) + (hasToggle ? 44 : 0) + (submenu ? 8 : 12)

    Rectangle {
        anchors.fill: parent
        radius: 8
        border.width: row.activeFocus ? 2 : 0
        border.color: Theme.white
        color: mouse.pressed ? Theme.pressed : mouse.containsMouse ? Theme.hover : "transparent"
    }

    Icon {
        id: leading
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        visible: icon !== null
        icon: row.checkable ? (row.checked ? Icons.check : null) : row.icon
        color: Theme.textMenu
    }

    Text {
        id: labelText
        x: row.iconColumn ? 56 : 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, row.width - x - 24)
        text: row.label
        color: Theme.textMenu
        font.family: Theme.font
        font.pixelSize: row.big ? 17 : 14
        elide: Text.ElideRight
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: row.submenu ? 8 : 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            width: Math.min(implicitWidth, row.width - labelText.x - labelText.implicitWidth - 24 - (row.submenu ? 30 : 12) - (row.hasToggle ? 44 : 0))
            text: row.value
            color: Theme.textSecondary
            font.family: Theme.font
            font.pixelSize: row.big ? 17 : 14
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.submenu
            width: 18
            height: 18
            icon: Icons.chevronRight
            color: Theme.textSecondary
        }
        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.hasToggle
            checked: row.toggled
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.clicked()
    }
}
