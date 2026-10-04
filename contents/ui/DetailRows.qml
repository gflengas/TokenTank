pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: section
    required property string title
    required property var rows
    spacing: Kirigami.Units.smallSpacing

    component SmallLabel: PlasmaComponents.Label {
        Layout.fillWidth: true
        font: Kirigami.Theme.smallFont
        textFormat: Text.PlainText
    }

    PlasmaComponents.Label {
        text: section.title
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.bold: true
        Layout.fillWidth: true
    }
    Repeater {
        model: section.rows
        delegate: ColumnLayout {
            id: detail
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                SmallLabel {
                    text: detail.modelData.label
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                    opacity: 0.7
                    wrapMode: Text.Wrap
                }
                SmallLabel {
                    text: detail.modelData.value
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 13
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.Wrap
                }
            }
            SmallLabel {
                visible: !!detail.modelData.note
                text: detail.modelData.note || ""
                opacity: 0.55
                wrapMode: Text.Wrap
            }
        }
    }
    SmallLabel {
        visible: section.rows.length === 0
        text: "Not reported"
        opacity: 0.55
    }
}
