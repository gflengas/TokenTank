pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property var results: [root.initialResult("codex", "Codex"), root.initialResult("claude", "Claude"), root.initialResult("zai", "z.ai"), root.initialResult("antigravity", "DeepMind")]
    readonly property bool busy: results.some(result => result.loading)
    readonly property int historyCacheDurationMs: 60000
    readonly property url robotIcon: Qt.resolvedUrl("../images/robot.svg")

    Plasmoid.icon: root.robotIcon
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: "TokenTank"
    toolTipSubText: "Click to refresh · Expand a card for details"
    preferredRepresentation: compactRepresentation

    UsageData {
        id: usageData
    }

    function initialResult(provider, name) {
        return {
            provider: provider,
            name: name,
            connected: false,
            rows: [],
            loading: false,
            error: "",
            historyFetchedAt: 0,
            details: {
                fuelRows: [],
                creditRows: [],
                resetRows: []
            },
            history: usageData.historyResult(null, false, "", "idle")
        };
    }

    function quotaCommand(provider) {
        var source = provider === "codex" || provider === "claude" ? " --source oauth" : "";
        return "/usr/bin/timeout --kill-after=3s 45s /usr/bin/codexbar usage --provider " + provider + source + " --format json --json-only";
    }

    function historySupported(provider) {
        return provider === "codex" || provider === "claude" || provider === "antigravity";
    }

    function historyCommand(provider) {
        return "/usr/bin/timeout --kill-after=3s 55s /usr/bin/codexbar cost --provider " + provider + " --days 7 --format json --json-only --provider-native-only";
    }

    function setResult(index, result) {
        var next = results.slice();
        next[index] = result;
        results = next;
    }

    function historyIsFresh(result, now) {
        const history = result.history;
        if ((history.state !== "ready" && history.state !== "empty") || history.stale)
            return false;
        const fetchedAt = result.historyFetchedAt;
        if (!(fetchedAt > 0 && now - fetchedAt < historyCacheDurationMs))
            return false;
        return new Date(fetchedAt).toDateString() === new Date(now).toDateString();
    }

    function fetchHistory(provider) {
        var index = results.findIndex(result => result.provider === provider);
        if (index < 0 || !historySupported(provider) || results[index].history.state === "loading")
            return;
        var prior = results[index];
        var now = Date.now();
        if (historyIsFresh(prior, now))
            return;
        setResult(index, Object.assign({}, prior, {
            history: Object.assign({}, prior.history, {
                state: "loading"
            })
        }));
        runner.connectSource(historyCommand(provider));
    }

    function fetchError(provider, message, exitCode) {
        if (exitCode === 124 || exitCode === 137)
            return "Refresh timed out. Try again.";
        if (message === "Provider data exceeds TokenTank limits.")
            return "Provider returned too much data to display.";
        if (message === "Invalid provider data.")
            return "Provider returned invalid data.";
        if (/network|resolve host|connection|offline/i.test(message))
            return "Unable to connect. Try again.";
        if (/credentials|authenticat|available fetch|not detected|sign.?in|unauthorized|(?:missing|invalid|expired|revoked).*(?:token|api.?key)|(?:token|api.?key).*(?:missing|invalid|expired|revoked)|\b401\b/i.test(message)) {
            const signIn = {
                claude: "Sign in to Claude Code to see usage.",
                zai: "Connect your z.ai account in CodexBar.",
                antigravity: "Connect Google in CodexBar or open Antigravity."
            }[provider];
            return typeof signIn === "string" ? signIn : "Sign in to Codex to see usage.";
        }
        return "Unable to refresh usage. Try again.";
    }

    function refresh() {
        const idle = results.filter(result => !result.loading);
        if (!idle.length)
            return;
        results = results.map(result => result.loading ? result : Object.assign({}, result, {
                loading: true,
                error: ""
            }));
        var popup = root.fullRepresentationItem as Popup;
        idle.forEach(function (result) {
            runner.connectSource(root.quotaCommand(result.provider));
            if (popup && popup.isExpanded(result.provider))
                root.fetchHistory(result.provider);
        });
    }

    onExpandedChanged: {
        if (root.expanded)
            root.refresh();
        else {
            var popup = root.fullRepresentationItem as Popup;
            if (popup)
                popup.collapseAll();
        }
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        onNewData: function (command, output) {
            disconnectSource(command);
            var isHistory = /\bcodexbar cost\b/.test(command);
            var index = root.results.findIndex(result => (!isHistory || root.historySupported(result.provider)) && (isHistory ? root.historyCommand(result.provider) : root.quotaCommand(result.provider)) === command);
            if (index < 0)
                return;
            var result = Object.assign({}, root.results[index]);
            if (!isHistory)
                result.loading = false;
            try {
                if (output["exit code"] !== 0 || (output["exit status"] !== undefined && output["exit status"] !== 0)) {
                    // Read a bounded CLI error record, without accepting failed usage/history.
                    if (!output.stderr)
                        usageData.recordFor(output.stdout || "", result.provider);
                    throw new Error(output.stderr || "Command failed");
                }
                if (isHistory) {
                    result.history = usageData.decodeHistory(output.stdout || "", result.provider);
                    result.historyFetchedAt = Date.now();
                } else {
                    var decoded = usageData.decodeUsage(output.stdout || "", result.provider);
                    result.connected = true;
                    result.rows = decoded.rows;
                    result.details = decoded.details;
                    result.error = decoded.rows.length ? "" : "No quota data reported.";
                    if (!root.historySupported(result.provider))
                        result.history = decoded.providerHistory || usageData.historyResult(null, false, "Token history not reported by this provider", "unsupported");
                }
            } catch (error) {
                if (isHistory) {
                    const failure = root.fetchError(result.provider, error.message, output["exit code"]);
                    result.history = typeof result.history.tokens === "number" ? Object.assign({}, result.history, {
                        state: "ready",
                        note: "Saved total · " + failure,
                        stale: true
                    }) : usageData.historyResult(null, false, failure, "error");
                } else {
                    result.error = root.fetchError(result.provider, error.message, output["exit code"]);
                    if (/^(Sign in|Connect)/.test(result.error))
                        result.connected = false;
                }
            }
            root.setResult(index, result);
        }
    }

    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth
        Layout.minimumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        Kirigami.Icon {
            anchors.fill: parent
            source: root.robotIcon
            isMask: true
            active: mouse.containsMouse
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            property bool wasExpanded: false
            onPressed: wasExpanded = root.expanded
            onClicked: root.expanded = !wasExpanded
        }
    }

    fullRepresentation: Popup {
        results: root.results
        busy: root.busy
        onRefreshRequested: root.refresh()
        onDetailsRequested: provider => root.fetchHistory(provider)
        Component.onCompleted: {
            if (root.expanded)
                root.refresh();
        }
    }
}
