pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: details
    required property var providerData
    readonly property var extras: providerData.details
    readonly property var history: providerData.history
    readonly property bool hasTokens: typeof history.tokens === "number"
    spacing: Kirigami.Units.largeSpacing

    function tokenText(value) {
        if (value >= 1000000000)
            return (value / 1000000000).toFixed(2) + "B tokens";
        if (value >= 1000000)
            return (value / 1000000).toFixed(2) + "M tokens";
        if (value >= 1000)
            return (value / 1000).toFixed(2) + "K tokens";
        return Math.round(value) + " tokens";
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        opacity: 0.65
    }
    DetailRows {
        title: "Fuel forecast"
        rows: details.extras.fuelRows
        Layout.fillWidth: true
    }
    DetailRows {
        objectName: "extraCreditsSection"
        title: "Extra credits"
        visible: rows.length > 0
        rows: details.extras.creditRows
        Layout.fillWidth: true
    }
    DetailRows {
        objectName: "availableResetsSection"
        title: "Available resets"
        visible: rows.length > 0
        rows: details.extras.resetRows
        Layout.fillWidth: true
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label {
            text: "Tokens · last 7 days"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.bold: true
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            objectName: "weeklyTokenTotal"
            text: details.hasTokens ? (details.history.partial ? "≥ " : "") + details.tokenText(details.history.tokens) : details.history.state === "loading" ? "Loading…" : "Not reported"
            Layout.fillWidth: true
            font.bold: details.hasTokens
            opacity: details.hasTokens ? 1 : 0.55
            HoverHandler {
                id: tokensHover
            }
            PlasmaComponents.ToolTip.text: details.hasTokens ? Number(details.history.tokens).toLocaleString(Qt.locale(), "f", 0) + " tokens" : ""
            PlasmaComponents.ToolTip.visible: tokensHover.hovered && details.hasTokens
        }
        PlasmaComponents.Label {
            text: details.history.state === "loading" && details.hasTokens ? "Refreshing token history…" : details.history.note || ""
            visible: !!text
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
            opacity: 0.55
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
}
