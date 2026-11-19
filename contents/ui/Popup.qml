pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: popup
    required property var results
    required property bool busy
    readonly property var connectedResults: results.filter(result => result.connected === true)
    readonly property string inputError: results.filter(result => !result.connected && /^Provider returned (too much|invalid) data/.test(result.error)).map(result => result.name + ": " + result.error).join("\n")
    property var expandedProviders: ({})
    property real maximumPopupHeight: Screen.height > 0 ? Screen.height * 0.8 : Kirigami.Units.gridUnit * 36
    readonly property real naturalHeight: headerRow.implicitHeight + providerList.implicitHeight + scroll.topPadding + scroll.bottomPadding + layout.spacing
    signal refreshRequested
    signal detailsRequested(string provider)

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Layout.preferredHeight
    Layout.minimumWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: Math.ceil(Math.min(naturalHeight, maximumPopupHeight))
    Layout.minimumHeight: Layout.preferredHeight
    Layout.maximumHeight: Layout.preferredHeight

    function isExpanded(provider) {
        return expandedProviders[provider] === true;
    }

    function toggleExpanded(provider) {
        var next = Object.assign({}, expandedProviders);
        next[provider] = !isExpanded(provider);
        expandedProviders = next;
        if (next[provider])
            detailsRequested(provider);
    }

    function collapseAll() {
        expandedProviders = ({});
    }

    function quotaLabel(label) {
        return String(label).replace(/^(\d+)\s*hours?$/i, "$1h");
    }

    function resetText(row) {
        var label = quotaLabel(row.label);
        var reset = new Date(row.resetsAt);
        if (!row.resetsAt || !isFinite(reset.getTime())) {
            return label + (row.resetDescription ? " reset: " + row.resetDescription : " reset unavailable");
        }
        var hourly = /^\d+h$/.test(label);
        return label + " resets " + Qt.formatDateTime(reset, hourly ? "HH:mm" : "ddd d MMM, HH:mm");
    }

    function resetSummary(rows) {
        const weekly = rows.find(row => row.label === "Weekly");
        const weeklyReset = weekly ? Date.parse(weekly.resetsAt) : NaN;
        return rows.filter(row => row.shortLabel !== "Argon" || Date.parse(row.resetsAt) !== weeklyReset)
                   .map(row => popup.resetText(row)).join("  ·  ");
    }

    function statusText(result) {
        if (result.loading)
            return "Refreshing…";
        if (result.rows.length > 0)
            return "Saved usage · refresh failed";
        if (/^(Sign in|Connect)/.test(result.error))
            return "Connect account to see usage.";
        return result.error || "Open to refresh usage.";
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 3
                text: "TokenTank"
                Layout.fillWidth: true
            }
            PlasmaComponents.BusyIndicator {
                running: popup.busy
                visible: running
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Layout.preferredWidth
            }
            PlasmaComponents.ToolButton {
                objectName: "refreshButton"
                icon.name: "view-refresh"
                icon.color: Kirigami.Theme.textColor
                text: "Refresh"
                display: PlasmaComponents.ToolButton.IconOnly
                enabled: popup.results.some(result => !result.loading)
                onClicked: popup.refreshRequested()
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
            }
        }

        PlasmaComponents.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            contentHeight: providerList.implicitHeight
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

            ColumnLayout {
                id: providerList
                width: scroll.availableWidth
                spacing: Kirigami.Units.smallSpacing * 2

                Repeater {
                    model: popup.connectedResults.map(result => result.provider)
                    delegate: Rectangle {
                        id: provider
                        required property string modelData
                        readonly property var providerData: popup.results.find(result => result.provider === provider.modelData)
                        objectName: "providerCard-" + modelData
                        readonly property bool expanded: popup.isExpanded(modelData)
                        readonly property real padding: Kirigami.Units.largeSpacing
                        Layout.fillWidth: true
                        implicitHeight: providerBody.implicitHeight + padding * 2
                        radius: Kirigami.Units.smallSpacing * 1.5
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.025)
                        border.width: 1
                        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                        Accessible.name: providerData.name

                        ColumnLayout {
                            id: providerBody
                            anchors.fill: parent
                            anchors.margins: provider.padding
                            spacing: Kirigami.Units.largeSpacing

                            Item {
                                id: summary
                                objectName: "providerSummary-" + provider.modelData
                                Layout.fillWidth: true
                                implicitHeight: providerContent.implicitHeight
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: provider.providerData.name + " details"
                                Accessible.description: provider.expanded ? "Collapse details" : "Expand details"
                                Accessible.onPressAction: popup.toggleExpanded(provider.modelData)
                                Keys.onSpacePressed: popup.toggleExpanded(provider.modelData)
                                Keys.onReturnPressed: popup.toggleExpanded(provider.modelData)
                                TapHandler {
                                    onTapped: popup.toggleExpanded(provider.modelData)
                                }
                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }

                                RowLayout {
                                    id: providerContent
                                    anchors.fill: parent
                                    spacing: Kirigami.Units.largeSpacing

                                    Kirigami.Icon {
                                        source: Qt.resolvedUrl("../images/" + (provider.modelData === "antigravity" ? "deepmind" : provider.modelData) + ".svg")
                                        isMask: true
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                        Layout.alignment: Qt.AlignVCenter
                                        HoverHandler {
                                            id: iconHover
                                        }
                                        PlasmaComponents.ToolTip.text: provider.providerData.name
                                        PlasmaComponents.ToolTip.visible: iconHover.hovered
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        opacity: provider.providerData.loading && provider.providerData.rows.length > 0 ? 0.6 : 1

                                        PlasmaComponents.Label {
                                            visible: provider.providerData.rows.length > 0
                                            text: popup.resetSummary(provider.providerData.rows)
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.7
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }

                                        Repeater {
                                            model: provider.providerData.rows
                                            delegate: RowLayout {
                                                id: quota
                                                required property var modelData
                                                readonly property string displayLabel: modelData.shortLabel || popup.quotaLabel(modelData.label)
                                                readonly property string remainingText: modelData.known ? Math.round(modelData.remaining) + "% left" : "Unavailable"
                                                Layout.fillWidth: true
                                                spacing: Kirigami.Units.smallSpacing * 2

                                                PlasmaComponents.Label {
                                                    id: quotaLabel
                                                    objectName: "quotaLabel"
                                                    text: quota.displayLabel
                                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                                    elide: Text.ElideRight
                                                    textFormat: Text.PlainText
                                                    HoverHandler {
                                                        id: labelHover
                                                    }
                                                    PlasmaComponents.ToolTip {
                                                        objectName: "quotaLabelToolTip"
                                                        text: quota.modelData.label
                                                        textFormat: Text.PlainText
                                                        visible: labelHover.hovered && (quotaLabel.truncated || !!quota.modelData.shortLabel)
                                                    }
                                                }

                                                Rectangle {
                                                    id: track
                                                    objectName: "quotaTrack"
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                                                    implicitHeight: Kirigami.Units.smallSpacing * 2
                                                    radius: 3
                                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                                                    Accessible.role: Accessible.ProgressBar
                                                    Accessible.name: quota.modelData.shortLabel ? quota.modelData.label : quota.displayLabel
                                                    Accessible.description: quota.remainingText

                                                    Rectangle {
                                                        objectName: "quotaFill"
                                                        anchors.left: parent.left
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        width: quota.modelData.known ? track.width * Math.max(0, Math.min(100, quota.modelData.remaining)) / 100 : 0
                                                        radius: track.radius
                                                        color: Kirigami.Theme.textColor
                                                        opacity: 0.92
                                                    }
                                                }

                                                PlasmaComponents.Label {
                                                    text: quota.remainingText
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4.5
                                                    horizontalAlignment: Text.AlignRight
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            visible: provider.providerData.rows.length === 0 || !!provider.providerData.error
                                            text: popup.statusText(provider.providerData)
                                            opacity: 0.7
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                            HoverHandler {
                                                id: statusHover
                                            }
                                            PlasmaComponents.ToolTip.text: provider.providerData.error
                                            PlasmaComponents.ToolTip.visible: statusHover.hovered && !!provider.providerData.error
                                        }
                                    }
                                    PlasmaComponents.Label {
                                        text: provider.expanded ? "⌄" : "›"
                                        font.pixelSize: Kirigami.Units.iconSizes.small
                                        opacity: 0.5
                                        Layout.alignment: Qt.AlignTop
                                    }
                                }
                            }
                            ProviderDetails {
                                objectName: "providerDetails-" + provider.modelData
                                visible: provider.expanded
                                providerData: provider.providerData
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
                PlasmaComponents.Label {
                    objectName: "emptyStatus"
                    visible: popup.connectedResults.length === 0 || !!popup.inputError
                    text: popup.inputError || (popup.busy ? "Refreshing…" : "No connected providers.")
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
