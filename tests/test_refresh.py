from pathlib import Path
import os
import subprocess

base = Path(__file__).resolve().parents[1]
source = (base / "contents/ui/main.qml").read_text()

def body(marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

functions = "\n".join(body("function " + name + "(") for name in (
    "initialResult", "quotaCommand", "historySupported", "historyCommand",
    "setResult", "historyIsFresh", "fetchHistory", "fetchError", "refresh"))
functions = functions.replace("as Popup", "as Tank.Popup")
callback = body("function (command, output)")
callback = callback.replace("function (command, output)", "function deliver(command, output)", 1)
callback = callback.replace("disconnectSource(command);", "runner.disconnectSource(command);", 1)

qml = r'''
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import "file://SOURCE_DIR" as Tank
Window {
    id: root
    visible: true
    width: 560
    height: 650
    property var results: [initialResult("codex", "Codex"), initialResult("claude", "Claude"), initialResult("zai", "z.ai"), initialResult("antigravity", "DeepMind")]
    readonly property bool busy: results.some(function(result) { return result.loading; })
    readonly property int historyCacheDurationMs: 60000
    property alias fullRepresentationItem: popup
    property var originalCard
    property var originalSummary
    property int phase: 0
    property var usageFixture: ({provider:"codex",usage:{primary:{usedPercent:10,windowMinutes:300},secondary:{usedPercent:20,windowMinutes:10080}}})
    Tank.UsageData { id: usageData }
    QtObject {
        id: runner
        property var launches: []
        function connectSource(command) { launches = launches.concat([command]); }
        function disconnectSource(command) {}
    }
    FUNCTIONS
    CALLBACK
    function check(condition, message) { if (!condition) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (var i=0;i<item.children.length;++i) {
            var match=find(item.children[i],name);
            if(match) return match;
        }
        return null;
    }
    function historyLaunches() { return runner.launches.filter(function(c) { return c.indexOf("codexbar cost") >= 0; }).length; }
    function updateCodex(changes) { var next=results.slice();next[0]=Object.assign({},next[0],changes);results=next; }
    function historyReply(value) { deliver(historyCommand("codex"),{stdout:JSON.stringify(value),"exit code":0}); }
    function readyHistory() { return {state:"ready",tokens:1234567,partial:false,note:""}; }
    function failureChecks() {
        popup.collapseAll();
        results=[initialResult("codex","Codex")];
        const valid=JSON.stringify(usageFixture);
        deliver(quotaCommand("codex"),{stdout:valid,"exit code":124});
        check(!results[0].connected && !results[0].loading && /timed out/.test(results[0].error),"Timeout JSON accepted as first success");
        deliver(quotaCommand("codex"),{stdout:valid,"exit code":0});
        const savedRows=results[0].rows;
        const savedDetails=results[0].details;
        const changed=JSON.stringify({provider:"codex",usage:{primary:{usedPercent:99}}});
        deliver(quotaCommand("codex"),{stdout:changed,stderr:"connection failed","exit code":1});
        check(results[0].connected && results[0].rows===savedRows && results[0].details===savedDetails,"Failed command replaced saved quota/details");
        check(/Unable to connect/.test(results[0].error),"Failed command stderr was not mapped");
        deliver(quotaCommand("codex"),{stdout:changed});
        check(results[0].rows===savedRows && !!results[0].error,"Missing process status accepted as success");
        deliver(quotaCommand("codex"),{stdout:changed,"exit code":0,"exit status":1});
        check(results[0].rows===savedRows && !!results[0].error,"Abnormal process termination accepted as success");
        updateCodex({history:readyHistory(),historyFetchedAt:123});
        deliver(historyCommand("codex"),{stdout:JSON.stringify({provider:"codex",totals:{totalTokens:999}}),"exit code":137});
        check(results[0].history.tokens===1234567 && results[0].history.stale && results[0].historyFetchedAt===123,"Failed history JSON replaced saved total or timestamp");
        historyReply({provider:"codex",totals:{totalTokens:999}});
        check(results[0].history.tokens===999 && !results[0].history.stale && results[0].historyFetchedAt>123,"Successful history retry did not clear stale state");
        deliver(quotaCommand("codex"),{stdout:JSON.stringify({provider:"codex",error:{message:"Credentials missing"}}),"exit code":1});
        check(!results[0].connected && /^Sign in/.test(results[0].error),"Structured CLI authentication failure did not hide disconnected provider");
        deliver(quotaCommand("codex"),{stdout:valid,"exit code":0});
        check(results[0].connected && !results[0].error,"Reconnect did not recover after failed authentication");
        results=[initialResult("codex","Codex")];
        deliver(quotaCommand("codex"),{stdout:"x".repeat(usageData.maximumPayloadChars+1),"exit code":0});
        check(!results[0].connected && /too much data/.test(results[0].error),"Oversized payload missing explicit error");
        check(popup.inputError.indexOf("Codex: Provider returned too much data")===0,"Hidden provider overflow not surfaced");
        deliver(quotaCommand("codex"),{stdout:JSON.stringify({provider:"codex",usage:{extraRateWindows:{}}}),"exit code":0});
        check(/invalid data/.test(results[0].error),"Malformed collections missing explicit error");
        console.warn("PASS: nonzero/missing/abnormal process status, stderr/JSON error mapping, saved data, authentication recovery and visible input errors");
    }
    function stable() {
        check(find(popup,"providerCard-codex") === originalCard, "Provider card rebuilt");
        check(find(popup,"providerSummary-codex") === originalSummary, "Summary rebuilt");
        check(originalSummary.activeFocus, "Keyboard focus lost");
    }
    Tank.Popup {
        id: popup
        anchors.fill: parent
        results: root.results
        busy: root.busy
        onDetailsRequested: function(provider) { root.fetchHistory(provider); }
    }
    Component.onCompleted: {
        var decoded=usageData.decodeUsage(JSON.stringify(usageFixture),"codex");
        updateCodex({connected:true,rows:decoded.rows,details:decoded.details});
    }
    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            try {
                if(root.phase===0) {
                    root.originalCard=root.find(popup,"providerCard-codex");
                    root.originalSummary=root.find(popup,"providerSummary-codex");
                    root.check(!!root.originalCard,"Connected provider missing");
                    root.originalSummary.forceActiveFocus();
                    popup.toggleExpanded("codex");
                    root.check(root.historyLaunches()===1,"Initial expansion did not scan once");
                    root.check(!runner.launches.some(command => / --refresh(?: |$)/.test(command)),"History bypasses the CodexBar scan cache");
                } else if(root.phase===1) {
                    root.stable();
                    root.historyReply({provider:"codex",totals:{totalTokens:1234567},historyCoverageIsEstablished:true});
                    root.check(root.results[0].historyFetchedAt>0,"Success did not timestamp cache");
                } else if(root.phase===2) {
                    root.stable();
                    root.check(root.find(popup,"weeklyTokenTotal").text.indexOf("1.23M")>=0,"Token total not displayed");
                    popup.toggleExpanded("codex");popup.toggleExpanded("codex");
                    root.check(root.historyLaunches()===1,"Recent expansion rescanned history");
                    root.refresh();
                    root.check(runner.launches.length===5 && root.historyLaunches()===1,"Refresh skipped quotas or rescanned recent history");
                } else if(root.phase===3) {
                    root.stable();
                    root.deliver(root.quotaCommand("codex"),{stdout:JSON.stringify(root.usageFixture),"exit code":0});
                    ["claude","zai"].forEach(function(p) { root.deliver(root.quotaCommand(p),{stdout:"", "exit code":1}); });
                    root.check(root.busy && root.find(popup,"refreshButton").enabled,"Pending provider disabled healthy refresh");
                    root.refresh();
                    root.check(runner.launches.length===8 && runner.launches.filter(command => command===root.quotaCommand("antigravity")).length===1,"Refresh failed to skip only the pending provider");
                    root.refresh();
                    root.check(runner.launches.length===8 && !root.find(popup,"refreshButton").enabled,"All-loading guard allowed duplicate requests");
                    root.deliver(root.quotaCommand("codex"),{stdout:JSON.stringify(root.usageFixture),"exit code":0});
                    ["claude","zai","antigravity"].forEach(function(p) { root.deliver(root.quotaCommand(p),{stdout:"", "exit code":1}); });
                    console.warn("PASS: pending provider does not block idle providers; all-loading guard prevents duplicate requests");
                } else if(root.phase===4) {
                    root.stable();
                    root.check(!root.busy,"Quota callbacks left refresh busy");
                    root.updateCodex({historyFetchedAt:Date.now()-60001});
                    root.fetchHistory("codex");root.fetchHistory("codex");
                    root.check(root.historyLaunches()===2,"Expired cache or loading guard failed");
                } else if(root.phase===5) {
                    root.stable();
                    root.check(root.find(popup,"weeklyTokenTotal").text.indexOf("1.23M")>=0,"Loading hid saved token total");
                    root.historyReply({provider:"codex",daily:[]});
                    root.check(root.results[0].history.state==="empty","Empty history not decoded");
                    root.fetchHistory("codex");
                    root.check(root.historyLaunches()===2,"Fresh empty history rescanned");
                    root.updateCodex({history:Object.assign(root.readyHistory(),{stale:true}),historyFetchedAt:Date.now()});
                    root.fetchHistory("codex");
                    root.check(root.historyLaunches()===3,"Stale history was incorrectly cached");
                    root.deliver(root.historyCommand("codex"),{stdout:"invalid", "exit code":1});
                    root.check(root.results[0].history.stale && root.results[0].history.tokens===1234567,"Failure discarded saved total");
                    root.fetchHistory("codex");
                    root.check(root.historyLaunches()===4,"Failed scan could not retry");
                    root.historyReply({provider:"codex",totals:{totalTokens:0},historyCoverageIsEstablished:true});
                    root.fetchHistory("codex");
                    root.check(root.historyLaunches()===4,"Measured zero was not cached");
                    root.updateCodex({history:root.readyHistory(),historyFetchedAt:Date.now()-86400000});
                    root.fetchHistory("codex");
                    root.check(root.historyLaunches()===5,"Previous day history was retained");
                    root.historyReply({provider:"codex",totals:{totalTokens:1234567},historyCoverageIsEstablished:true});
                    root.fetchHistory("zai");
                    root.check(root.historyLaunches()===5,"Unsupported provider launched local scan");
                    root.refresh();
                    root.check(runner.launches.length===16 && root.historyLaunches()===5,"Second click did not refresh all four quotas");
                    console.warn("PASS: cache hits, expiry, empty and zero history, stale and failed retries, saved totals, four quota calls per click");
                } else if(root.phase===6) {
                    root.stable();
                    root.updateCodex({connected:false});
                } else if(root.phase===7) {
                    root.check(!root.find(popup,"providerCard-codex"),"Disconnected provider remained visible");
                    root.updateCodex({connected:true,loading:false});
                } else {
                    root.check(!!root.find(popup,"providerCard-codex"),"Reconnected provider remained hidden");
                    console.warn("PASS: provider and summary identity, keyboard focus across expansion/history/quota updates, disconnect/reconnect");
                    root.failureChecks();
                    running=false;Qt.quit();
                }
                ++root.phase;
            } catch(error) { console.error("FAIL: "+error.message);running=false;Qt.exit(1); }
        }
    }
}
'''
qml=qml.replace("SOURCE_DIR", str(base / "contents/ui")).replace("FUNCTIONS",functions).replace("CALLBACK",callback)
fd=os.memfd_create("tokentank-refresh-test.qml")
os.write(fd,qml.encode())
os.lseek(fd,0,os.SEEK_SET)
env=os.environ.copy()
for key,value in {"QT_QPA_PLATFORM":"offscreen","QT_QUICK_BACKEND":"software","QT_FORCE_STDERR_LOGGING":"1","QML_DISABLE_DISK_CACHE":"1"}.items():
    env.setdefault(key,value)
result=subprocess.run([os.environ.get("QML_BIN","/usr/lib/qt6/bin/qml"),"-f",f"/proc/self/fd/{fd}"],pass_fds=(fd,),capture_output=True,text=True,timeout=15,env=env)
print(result.stdout+result.stderr)
raise SystemExit(result.returncode)
