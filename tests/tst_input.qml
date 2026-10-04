import QtQuick
import QtTest
import org.kde.plasma.plasma5support as Plasma5Support
import "../contents/ui" as Tank

TestCase {
    id: test
    name: "TokenTankInput"
    width: 560
    height: 600
    visible: true
    when: windowShown

    Tank.UsageData { id: decoder }
    Component { id: popupComponent; Tank.Popup {} }
    property var processOutput: null
    Plasma5Support.DataSource {
        id: processRunner
        engine: "executable"
        connectedSources: []
        onNewData: function (command, output) {
            disconnectSource(command);
            test.processOutput = output;
        }
    }

    function usage(usage, labels) {
        return decoder.decodeUsage(JSON.stringify({provider: "codex", usage: usage, rateWindowLabels: labels}), "codex");
    }

    function history(record) {
        return decoder.decodeHistory(JSON.stringify(Object.assign({provider: "antigravity"}, record)), "antigravity");
    }

    function rejects(callback, message) {
        let failure = "";
        try { callback(); } catch (error) { failure = error.message; }
        compare(failure, message);
    }

    function oversized(callback) {
        rejects(callback, "Provider data exceeds TokenTank limits.");
    }

    function test_payloadLimit() {
        const json = JSON.stringify({provider: "codex", usage: {primary: {usedPercent: 25, windowMinutes: 300}}});
        const padded = json + " ".repeat(decoder.maximumPayloadChars - json.length);
        compare(decoder.decodeUsage(padded, "codex").rows[0].remaining, 75);
        oversized(() => decoder.decodeUsage(padded + " ", "codex"));
        oversized(() => decoder.decodeUsage("x".repeat(decoder.maximumPayloadChars + 1), "codex"));
        oversized(() => decoder.decodeHistory(padded + " ", "codex"));
        oversized(() => decoder.decodeUsage(JSON.stringify(Array(17).fill({provider: "codex", usage: {}})), "codex"));
    }

    function test_windowLimit() {
        const windows = Array(decoder.maximumQuotaWindows).fill({title: "Quota", window: {usedPercent: 25}});
        compare(usage({extraRateWindows: windows}).rows.length, decoder.maximumQuotaWindows);
        oversized(() => usage({extraRateWindows: windows.concat(windows[0])}));
        oversized(() => usage({primary: {usedPercent: 10}, extraRateWindows: windows}));
    }

    function test_detailLimits() {
        const rows = Array(decoder.maximumDetailRows).fill({label: "Extra credits", value: "1"});
        compare(usage({details: [{title: "Balance", rows: rows}]}).details.creditRows.length, decoder.maximumDetailRows);
        oversized(() => usage({details: [{rows: rows.concat(rows[0])}]}));
        oversized(() => usage({details: [{rows: rows}, {rows: [rows[0]]}]}));
        oversized(() => usage({details: Array(17).fill({rows: []})}));
        oversized(() => usage({codexResetCredits: {availableCount: 65, credits: Array(65).fill({status: "available"})}}));
        oversized(() => usage({details: [{chart: {title: "Daily tokens", unit: "tokens", points: Array(367).fill({label: "2030-01-01", value: 1})}}]}));
    }

    function test_textLimits() {
        const window = {usedPercent: 10, windowMinutes: 300};
        compare(usage({primary: window}, {primary: "x".repeat(256)}).rows[0].label.length, 256);
        oversized(() => usage({primary: window}, {primary: "x".repeat(257)}));
        oversized(() => usage({primary: Object.assign({}, window, {resetDescription: "x".repeat(257)})}));
        oversized(() => decoder.decodeUsage(JSON.stringify({provider: "codex", usage: {primary: window}, pace: {primary: {summary: "x".repeat(1025)}}}), "codex"));
        compare(usage({details: [{rows: [{label: "Extra credits", value: "1" + " ".repeat(1023)}]}]}).details.creditRows[0].value.length, 1024);
        oversized(() => usage({details: [{rows: [{label: "Extra credits", value: "1" + " ".repeat(1024)}]}]}));
    }

    function test_malformedCollections_data() {
        return [
            {tag: "usage array", value: []},
            {tag: "usage null", value: null},
            {tag: "extra object", value: {extraRateWindows: {}}},
            {tag: "extra string", value: {extraRateWindows: "wrong"}},
            {tag: "extra null entry", value: {extraRateWindows: [null]}},
            {tag: "window array", value: {primary: []}},
            {tag: "details object", value: {details: {}}},
            {tag: "section null", value: {details: [null]}},
            {tag: "rows object", value: {details: [{rows: {}}]}},
            {tag: "row null", value: {details: [{rows: [null]}]}},
            {tag: "label object", value: {extraRateWindows: [{title: {}, usedPercent: 10}]}},
            {tag: "chart point null", value: {details: [{chart: {title: "Daily tokens", unit: "tokens", points: [null]}}]}}
        ];
    }

    function test_malformedCollections(row) {
        rejects(() => usage(row.value), "Invalid provider data.");
    }

    function test_historyLimitsAndShapes() {
        oversized(() => history({daily: Array(32).fill({})}));
        oversized(() => history({daily: [{modelBreakdowns: Array(129).fill({modelName: "gemini", totalTokens: 1})}]}));
        oversized(() => history({daily: [{modelsUsed: Array(129).fill("gemini"), totalTokens: 1}]}));
        oversized(() => history({daily: [{modelBreakdowns: [{modelName: "gemini" + "x".repeat(256), totalTokens: 1}]}]}));
        [
            {daily: {}}, {daily: [null]}, {daily: [{modelBreakdowns: {}}]},
            {daily: [{modelBreakdowns: [null]}]}, {daily: [{modelsUsed: {}}]},
            {daily: [{modelsUsed: [null]}]}, {totals: []}
        ].forEach(record => rejects(() => history(record), "Invalid provider data."));
        rejects(() => history({daily: [{modelBreakdowns: [{modelName: "gemini", totalTokens: 1e308}, {modelName: "gemini", totalTokens: 1e308}]}]}), "Invalid token total");
    }

    function test_plainTooltip() {
        const markup = '<b>Quota</b><img src="file:///tmp/tokentank-test-missing-image.png">';
        const decoded = usage({primary: {usedPercent: 25}}, {primary: markup});
        const result = {provider: "codex", name: "Codex", connected: true, loading: false, error: "",
            rows: decoded.rows, details: decoded.details, history: {state: "idle", tokens: null, note: ""}};
        const popup = createTemporaryObject(popupComponent, test, {width: 560, height: 300, results: [result], busy: false});
        verify(popup);
        wait(0);
        const label = findChild(popup, "quotaLabel");
        verify(label);
        const tooltip = Array.from(label.data).find(child => child.objectName === "quotaLabelToolTip");
        verify(tooltip);
        compare(tooltip.text, markup);
        compare(tooltip.textFormat, Text.PlainText);
        tooltip.delay = 0;
        tooltip.visible = true;
        tryCompare(tooltip, "opened", true);
        const textItem = tooltip.contentItem.children[0];
        compare(textItem.textFormat, Text.PlainText);
        compare(textItem.text, markup);
    }

    function test_executableStatus() {
        const commands = [
            {command: "/usr/bin/printf ok", code: 0, stdout: "ok"},
            {command: '/usr/bin/sh -c "printf ok; exit 7"', code: 7, stdout: "ok"},
            {command: "/usr/bin/timeout --kill-after=1s 0.1s /usr/bin/sleep 2", code: 124, stdout: ""}
        ];
        for (const entry of commands) {
            processOutput = null;
            processRunner.connectSource(entry.command);
            tryVerify(() => processOutput !== null);
            compare(processOutput["exit code"], entry.code);
            compare(processOutput["exit status"], 0);
            compare(processOutput.stdout, entry.stdout);
        }
    }

    function test_hiddenProviderInputError() {
        const result = {provider: "codex", name: "Codex", connected: false, loading: false,
            error: "Provider returned too much data to display."};
        const popup = createTemporaryObject(popupComponent, test, {width: 560, height: 300, results: [result], busy: false});
        verify(popup);
        compare(popup.connectedResults.length, 0);
        const status = findChild(popup, "emptyStatus");
        verify(status.visible);
        compare(status.text, "Codex: Provider returned too much data to display.");
        compare(status.textFormat, Text.PlainText);
    }
}
