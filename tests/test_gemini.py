from pathlib import Path
import json
import os
import subprocess

base = Path(__file__).resolve().parents[1]
fixture = json.loads((base / "tests/fixtures/google-usage.json").read_text())
qml = r'''
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "file://SOURCE_DIR" as Tank
Window {
    id: root
    visible: true
    width: 560
    height: popup.Layout.preferredHeight + 24
    color: "#202427"
    property var fixture: USAGE_FIXTURE
    property var decoded: decoder.decodeUsage(JSON.stringify(fixture),"antigravity")
    property int phase: 0
    Tank.UsageData { id: decoder }
    function check(condition,message) { if(!condition) throw new Error(message); }
    function find(item,name,text) {
        if(item.objectName===name && (text===undefined || item.text===text)) return item;
        for(var i=0;i<item.children.length;++i) { var match=find(item.children[i],name,text);if(match) return match; }
        return null;
    }
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function usage(record) { return decoder.decodeUsage(JSON.stringify(record),"antigravity"); }
    function history(record) { return decoder.decodeHistory(JSON.stringify(Object.assign({provider:"antigravity",historyCoverageIsEstablished:true},record)),"antigravity"); }
    function previewResult() {
        return [{provider:"antigravity",name:"DeepMind",connected:true,loading:false,error:"",rows:decoded.rows,
            details:decoded.details,history:{state:"empty",tokens:null,note:"Gemini token totals not reported separately"}}];
    }
    Rectangle { anchors.fill: parent; color: root.color }
    Tank.Popup {
        id: popup
        anchors.fill: parent
        anchors.margins: 12
        results: root.previewResult()
        busy: false
        maximumPopupHeight: 600
        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: "#202427"
        Kirigami.Theme.textColor: "#eff0f1"
    }
    Component.onCompleted: {
        try {
            check(decoded.rows.length===3,"Google fixture did not keep Argon separate from equal general weekly values");
            check(decoded.rows[0].label==="5h" && decoded.rows[1].label==="Weekly","Cadence labels/order incorrect");
            check(decoded.rows[0].remaining===100 && decoded.rows[1].remaining===100,"Remaining quota changed");
            check(decoded.rows[0].resetsAt===fixture.usage.extraRateWindows[0].window.resetsAt && decoded.rows[1].resetsAt===fixture.usage.extraRateWindows[1].window.resetsAt,"Reset values changed");
            check(decoded.rows[2].label==="Gemini 4 Argon weekly" && decoded.rows[2].remaining===100,"Missing Argon quota");
            var differentArgon=copy(fixture);
            differentArgon.usage.extraRateWindows[4].window.usedPercent=65;
            differentArgon.usage.extraRateWindows[4].window.resetsAt="2030-01-09T13:00:00Z";
            var argonRows=usage(differentArgon).rows;
            check(argonRows[1].remaining===100 && argonRows[2].remaining===35 && argonRows[2].resetsAt==="2030-01-09T13:00:00Z","Argon usage or reset overwrote the general weekly quota");
            differentArgon.usage.extraRateWindows[4].usageKnown=false;
            check(!usage(differentArgon).rows[2].known,"Unmeasured Argon quota rendered as known");
            var argonOnly=copy(fixture);
            argonOnly.usage.primary=null;
            argonOnly.usage.extraRateWindows=[argonOnly.usage.extraRateWindows[4]];
            check(usage(argonOnly).rows.length===1 && usage(argonOnly).rows[0].shortLabel==="Argon","Argon substituted for absent general quota");
            var conflict=copy(fixture);
            conflict.usage.primary.usedPercent=75;
            conflict.usage.extraRateWindows[0].window.usedPercent=20;
            check(usage(conflict).rows[0].remaining===80,"Family alias overrode explicit Gemini bucket");
            var unknown=copy(fixture);
            unknown.usage.primary.usageKnown=false;
            unknown.usage.extraRateWindows[0].usageKnown=false;
            check(!usage(unknown).rows[0].known,"Unmeasured quota became 100% available");
            var measured=copy(unknown);measured.usage.primary.usageKnown=true;measured.usage.primary.usedPercent=25;
            check(usage(measured).rows[0].known && usage(measured).rows[0].remaining===75,"Measured fallback was ignored");
            var weekly=copy(fixture);
            weekly.usage.primary=copy(weekly.usage.extraRateWindows[1].window);
            weekly.usage.extraRateWindows=weekly.usage.extraRateWindows.filter(function(e){return !/5h$|argon/.test(e.id);});
            var weekRows=usage(weekly).rows;
            check(weekRows.length===1 && weekRows[0].label==="Weekly","Weekly-only plan fabricated a session bar");
            var legacy=copy(fixture);legacy.usage.extraRateWindows=[];
            check(usage(legacy).rows.length===1 && usage(legacy).rows[0].label==="5h","Legacy Gemini representative was lost");
            legacy.rateWindowLabels.primary="Claude and GPT";
            legacy.pace={primary:{willLastToReset:true}};
            check(usage(legacy).rows.length===0 && usage(legacy).details.fuelRows.length===0,"Non-Gemini usage/forecast remained");
            var models={provider:"antigravity",usage:{extraRateWindows:[
                {title:"Gemini Pro",window:{windowMinutes:300,usedPercent:20}},
                {title:"Gemini Flash",window:{windowMinutes:300,usedPercent:80}},
                {title:"Claude",window:{windowMinutes:300,usedPercent:99}}
            ]}};
            check(usage(models).rows.length===1 && usage(models).rows[0].remaining===20,"Model fallback did not use most constrained Gemini window");
            var mixed=history({totals:{totalTokens:999999},daily:[
                {totalTokens:600,modelBreakdowns:[{modelName:"gemini-3-pro",totalTokens:100},{modelName:"claude-sonnet",totalTokens:500}]},
                {totalTokens:500,modelBreakdowns:[{modelName:"gemini-3-flash",totalTokens:200},{modelName:"gpt-5",totalTokens:300}]}
            ]});
            check(mixed.tokens===300 && !mixed.partial,"Token history included Claude/GPT or aggregate totals");
            check(history({totals:{totalTokens:999},daily:[{totalTokens:999}]}).tokens===null,"Unattributed aggregate counted as Gemini");
            check(history({daily:[{modelBreakdowns:[{modelName:"gemini-3-pro",totalTokens:0}]}]}).tokens===0,"Measured Gemini zero was lost");
            check(history({daily:[{modelsUsed:["gemini-3-pro"],totalTokens:30}]}).tokens===30,"Gemini-only day fallback failed");
            check(history({daily:[{modelsUsed:["gemini-3-pro","claude-sonnet"],totalTokens:30}]}).tokens===null,"Mixed unseparated day became Gemini usage");
            check(history({daily:[{modelBreakdowns:[{modelName:"gemini-3-pro",totalTokens:20}]},{totalTokens:100}]}).partial,"Unattributed day did not mark history partial");
            check(history({daily:[]}).state==="empty","Absent Gemini history became zero");
            console.warn("PASS: separate Argon and general quotas, duplicate preference, unknown/weekly-only/legacy quotas, Gemini-only fuel and token history");
        } catch(error) { console.error("FAIL: "+error.message);Qt.exit(1); }
    }
    Timer {
        interval: 350
        running: true
        repeat: true
        onTriggered: {
            try {
                if(root.phase===0) {
                    var text=popup.resetSummary(root.decoded.rows);
                    root.check(text.indexOf("Claude")<0 && text.indexOf("GPT")<0 && text.indexOf("5h resets")>=0 && text.indexOf("Weekly resets")>=0 && text.indexOf("Gemini 4 Argon weekly resets")>=0,"Reset header did not distinguish Gemini quotas");
                    var argonLabel=root.find(popup,"quotaLabel","Argon");
                    root.check(argonLabel && argonLabel.visible && !argonLabel.truncated,"Argon bar label missing or clipped");
                    popup.toggleExpanded("antigravity");
                } else {
                    root.check(root.find(popup,"providerDetails-antigravity").visible,"Google card did not expand");
                    root.check(root.find(popup,"weeklyTokenTotal").text==="Not reported","Absent model-scoped tokens showed aggregate total");
                    console.warn("PASS: Gemini card has compact reset header and expandable details");Qt.quit();
                    running=false;
                }
                ++root.phase;
            } catch(error) { console.error("FAIL: "+error.message);running=false;Qt.exit(1); }
        }
    }
}
'''
qml=qml.replace("SOURCE_DIR",str(base/"contents/ui")).replace("USAGE_FIXTURE",json.dumps(fixture))
fd=os.memfd_create("tokentank-gemini-test.qml")
os.write(fd,qml.encode());os.lseek(fd,0,os.SEEK_SET)
env=os.environ.copy()
for key,value in {"QT_QPA_PLATFORM":"offscreen","QT_QUICK_BACKEND":"software","QT_FORCE_STDERR_LOGGING":"1","QML_DISABLE_DISK_CACHE":"1"}.items():
    env.setdefault(key,value)
result=subprocess.run([os.environ.get("QML_BIN","/usr/lib/qt6/bin/qml"),"-f",f"/proc/self/fd/{fd}"],pass_fds=(fd,),capture_output=True,text=True,timeout=15,env=env)
output=result.stdout+result.stderr
print(output)
raise SystemExit(result.returncode if "FAIL:" not in output else 1)
