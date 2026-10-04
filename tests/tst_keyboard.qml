import QtQuick
import QtTest
import "../contents/ui" as Tank

Item {
    id: root
    width: 560
    height: 600
    property int propagatedKeys: 0
    property int detailRequests: 0
    Keys.onPressed: event => {
        ++root.propagatedKeys;
        event.accepted = true;
    }

    Tank.Popup {
        id: popup
        anchors.fill: parent
        busy: false
        results: [{provider: "codex", name: "Codex", connected: true, loading: false, error: "",
            rows: [{label: "5h", known: true, remaining: 80, resetsAt: "", resetDescription: "5-hour"}],
            details: {fuelRows: [], creditRows: [], resetRows: []},
            history: {state: "idle", tokens: null, partial: false, note: ""}}]
        onDetailsRequested: ++root.detailRequests
    }

    TestCase {
        name: "TokenTankKeyboard"
        when: windowShown

        function find(item, name) {
            if (item.objectName === name)
                return item;
            for (const child of item.children) {
                const match = find(child, name);
                if (match)
                    return match;
            }
            return null;
        }

        function test_summaryKeys() {
            const summary = find(popup, "providerSummary-codex");
            verify(summary !== null);
            summary.forceActiveFocus();
            verify(summary.activeFocus);
            keyClick(Qt.Key_A);
            compare(root.propagatedKeys, 1);
            compare(popup.isExpanded("codex"), false);
            keyClick(Qt.Key_Space);
            compare(popup.isExpanded("codex"), true);
            compare(root.detailRequests, 1);
            compare(root.propagatedKeys, 1);
            keyClick(Qt.Key_Return);
            compare(popup.isExpanded("codex"), false);
            compare(root.propagatedKeys, 1);
            keyClick(Qt.Key_Enter);
            compare(popup.isExpanded("codex"), false);
            compare(root.propagatedKeys, 2);
        }
    }
}
