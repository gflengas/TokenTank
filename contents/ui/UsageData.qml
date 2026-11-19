pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: data

    readonly property int maximumPayloadChars: 1048576
    readonly property int maximumQuotaWindows: 32
    readonly property int maximumDetailRows: 64

    function checkedObject(value) {
        if (!value || typeof value !== "object" || Array.isArray(value))
            throw new Error("Invalid provider data.");
        return value;
    }

    function checkedArray(value, limit = 64) {
        if (value === null || value === undefined)
            return [];
        if (!Array.isArray(value))
            throw new Error("Invalid provider data.");
        if (value.length > limit)
            throw new Error("Provider data exceeds TokenTank limits.");
        return value;
    }

    function checkedText(value, limit = 256) {
        if (value === null || value === undefined)
            return "";
        if (typeof value !== "string")
            throw new Error("Invalid provider data.");
        if (value.length > limit)
            throw new Error("Provider data exceeds TokenTank limits.");
        return value;
    }

    function numeric(value) {
        return typeof value === "number" && isFinite(value);
    }

    function usageKnown(window) {
        return window.usageKnown !== false && numeric(window.usedPercent);
    }

    function recordFor(stdout, provider) {
        if (typeof stdout !== "string")
            throw new Error("Invalid provider data.");
        if (stdout.length > data.maximumPayloadChars)
            throw new Error("Provider data exceeds TokenTank limits.");
        var payload = JSON.parse(stdout);
        var records = Array.isArray(payload) ? checkedArray(payload, 16) : [payload];
        records.forEach(row => data.checkedObject(row));
        var record = records.find(row => row && row.provider === provider);
        if (!record)
            throw new Error("No provider result");
        if (record.error)
            throw new Error(checkedText(typeof record.error === "string" ? record.error : checkedObject(record.error).message, 1024) || "Fetch failed");
        return record;
    }

    function windowLabel(window, fallback) {
        fallback = checkedText(fallback);
        if (fallback)
            return fallback;
        var minutes = window.windowMinutes;
        if (minutes === 10080)
            return "Weekly";
        if (minutes === 1440)
            return "Daily";
        if (numeric(minutes) && minutes > 0)
            return minutes % 60 === 0 ? minutes / 60 + "h" : minutes + " minutes";
        return "Quota";
    }

    function windowRow(window, label) {
        var known = usageKnown(window);
        var used = known ? Math.max(0, Math.min(100, window.usedPercent)) : 0;
        return {
            label: windowLabel(window, label),
            known: known,
            remaining: known ? 100 - used : 0,
            resetsAt: checkedText(window.resetsAt),
            resetDescription: checkedText(window.resetDescription)
        };
    }

    function duration(seconds) {
        var minutes = Math.max(1, Math.ceil(seconds / 60));
        var days = Math.floor(minutes / 1440);
        var hours = Math.floor(minutes % 1440 / 60);
        return days > 0 ? days + "d " + hours + "h" : hours > 0 ? hours + "h " + minutes % 60 + "m" : minutes + "m";
    }

    function amount(value, currency) {
        currency = checkedText(currency, 16);
        if (currency === "USD")
            return "$" + value.toFixed(2);
        if (currency === "CNY")
            return "¥" + value.toFixed(2);
        if (currency === "EUR")
            return "€" + value.toFixed(2);
        return Number(value).toLocaleString(Qt.locale(), "f", value % 1 === 0 ? 0 : 2) + (currency ? " " + currency.toLowerCase() : "");
    }

    function detailAvailable(row) {
        var value = checkedText(typeof row.value === "number" ? String(row.value) : row.value, 1024).trim();
        if (/^(unavailable|expired|none|disabled|not reported|not available|no\b)/i.test(value))
            return false;
        if (row.progress && numeric(row.progress.used) && numeric(row.progress.total))
            return row.progress.total > row.progress.used;
        if (numeric(row.usageValue))
            return row.usageValue > 0;
        var number = value.replace(/,/g, "").match(/[-+]?\d+(?:\.\d+)?/);
        return number !== null && Number(number[0]) > 0;
    }

    function dedupeByCadence(windows) {
        const selected = [];
        const byCadence = Object.create(null);
        windows.forEach(function (entry) {
            const cadence = data.numeric(entry.window.windowMinutes) && entry.window.windowMinutes > 0 ? String(entry.window.windowMinutes) : entry.label || entry.id;
            const prior = byCadence[cadence];
            if (prior) {
                if (!prior.key && entry.key && prior.window.usedPercent === entry.window.usedPercent)
                    prior.key = entry.key;
                return;
            }
            byCadence[cadence] = entry;
            entry.label = data.windowLabel(entry.window, data.numeric(entry.window.windowMinutes) ? "" : entry.label);
            selected.push(entry);
        });
        selected.sort((a, b) => (a.window.windowMinutes || Infinity) - (b.window.windowMinutes || Infinity));
        return selected;
    }

    function quotaWindows(record, provider) {
        var usage = checkedObject(record.usage);
        var labels = record.rateWindowLabels == null ? {} : checkedObject(record.rateWindowLabels);
        var windows = [];
        ["primary", "secondary", "tertiary"].forEach(function (key) {
            if (usage[key])
                windows.push({
                    window: data.checkedObject(usage[key]),
                    label: data.checkedText(labels[key]),
                    key: key,
                    priority: 1
                });
        });
        checkedArray(usage.extraRateWindows, maximumQuotaWindows).forEach(function (extra) {
            data.checkedObject(extra);
            var window = extra.window == null ? extra : data.checkedObject(extra.window);
            if (extra.usageKnown === false)
                window = Object.assign({}, window, {
                    usageKnown: false
                });
            windows.push({
                window: window,
                label: data.checkedText(extra.label || extra.title || extra.name),
                id: data.checkedText(extra.id),
                priority: /^antigravity-quota-summary-gemini-/.test(extra.id || "") ? 0 : 2
            });
        });
        if (windows.length > maximumQuotaWindows)
            throw new Error("Provider data exceeds TokenTank limits.");
        if (provider !== "antigravity")
            return windows;

        windows.sort(function (a, b) {
            const aKnown = data.usageKnown(a.window);
            const bKnown = data.usageKnown(b.window);
            return aKnown !== bKnown ? (aKnown ? -1 : 1) : a.priority - b.priority || (aKnown ? b.window.usedPercent - a.window.usedPercent : 0);
        });
        const general = [];
        const argon = [];
        windows.forEach(function (entry) {
            const id = entry.id || "";
            const identity = entry.label + " " + id;
            if (/^antigravity-quota-summary-gemini-argon(?:-|$)/.test(id) || /^Gemini 4 Argon weekly$/i.test(entry.label))
                argon.push(entry);
            else if (/\bgemini\b/i.test(identity) && !/\bargon\b/i.test(identity))
                general.push(entry);
        });

        // Argon can share a reset cadence with general Gemini while drawing from a separate quota.
        return dedupeByCadence(general).concat(dedupeByCadence(argon).map(entry => {
            if (!/^Gemini 4 Argon\b/i.test(entry.label))
                entry.label = "Gemini 4 Argon " + entry.label.toLowerCase();
            entry.shortLabel = /^Gemini 4 Argon weekly$/i.test(entry.label) ? "Argon" : "";
            return entry;
        }));
    }

    function decodeUsage(stdout, provider) {
        var record = recordFor(stdout, provider);
        var usage = checkedObject(record.usage);
        var paceByWindow = record.pace == null ? {} : checkedObject(record.pace);
        var detailCount = 0;
        function addDetail(target, label, value, note = "") {
            if (++detailCount > data.maximumDetailRows)
                throw new Error("Provider data exceeds TokenTank limits.");
            target.push({
                label: data.checkedText(label),
                value: data.checkedText(value, 1024),
                note: data.checkedText(note, 1024)
            });
        }
        var rows = [];
        var fuelRows = [];
        data.quotaWindows(record, provider).forEach(function (entry) {
            var row = data.windowRow(entry.window, entry.label);
            if (entry.shortLabel)
                row.shortLabel = entry.shortLabel;
            rows.push(row);
            var pace = paceByWindow[entry.key];
            if (!pace || !row.known)
                return;
            data.checkedObject(pace);
            data.checkedText(pace.summary, 1024);
            var value = pace.willLastToReset === true ? "Should last until reset" : pace.willLastToReset === false && data.numeric(pace.etaSeconds) ? (pace.etaSeconds <= 0 ? "Quota exhausted" : "Projected empty in " + data.duration(pace.etaSeconds)) : pace.summary || "";
            if (value)
                addDetail(fuelRows, row.label, value, pace.summary && pace.summary !== value ? pace.summary : "");
        });
        var creditRows = [];
        var resetRows = [];
        var credits = record.credits;
        if (credits != null)
            checkedObject(credits);
        if (credits && numeric(credits.remaining) && credits.remaining > 0 && credits.creditsAvailable !== false && credits.balanceReadSucceeded !== false)
            addDetail(creditRows, credits.balanceIsWorkspace ? "Workspace credits" : "Extra credits", amount(credits.remaining, "credits"));
        var cost = usage.providerCost;
        if (cost) {
            checkedObject(cost);
            if (numeric(cost.balance) && cost.balance > 0 && cost.balanceIsUnavailable !== true && creditRows.length === 0)
                addDetail(creditRows, "Prepaid balance", amount(cost.balance, cost.currencyCode));
            if (numeric(cost.limit) && cost.limit > 0 && numeric(cost.used) && cost.limit > cost.used)
                addDetail(creditRows, "Extra usage budget", amount(Math.max(0, cost.limit - cost.used), cost.currencyCode) + " left", amount(cost.used, cost.currencyCode) + " used of " + amount(cost.limit, cost.currencyCode));
        }

        var resets = usage.codexResetCredits;
        if (resets != null)
            checkedObject(resets);
        if (resets && numeric(resets.availableCount) && resets.availableCount > 0) {
            addDetail(resetRows, "Available", String(resets.availableCount));
            checkedArray(resets.credits).forEach(function (credit) {
                data.checkedObject(credit);
                if (credit.status !== "available")
                    return;
                var expiry = new Date(data.checkedText(credit.expires_at));
                if (!credit.expires_at || !isFinite(expiry.getTime()))
                    return;
                addDetail(resetRows, credit.title || "Reset credit", "Expires " + Qt.formatDateTime(expiry, "d MMM, HH:mm"));
            });
        }

        var sections = checkedArray(usage.details, 16);
        sections.forEach(function (section) {
            data.checkedObject(section);
            data.checkedText(section.title);
            data.checkedArray(section.rows).forEach(function (row) {
                data.checkedObject(row);
                data.checkedText(row.label);
                data.checkedText(row.secondaryValue, 1024);
                if (row.value === null || row.value === undefined || !data.detailAvailable(row))
                    return;
                var text = (section.title || "") + " " + (row.label || "");
                var target;
                if (/reset.*credit|credit.*reset|available resets|saved resets|refills?/i.test(text))
                    target = resetRows;
                else if (/credit|balance|prepaid|extra usage/i.test(text) && !/quota/i.test(row.label || ""))
                    target = creditRows;
                if (target)
                    addDetail(target, row.label || section.title || "Balance", String(row.value), row.secondaryValue || "");
            });
        });
        return {
            rows: rows,
            details: {
                fuelRows: fuelRows,
                creditRows: creditRows,
                resetRows: resetRows
            },
            providerHistory: historyFromDetails(sections)
        };
    }

    function dayKey(date) {
        function pad(value) {
            return value < 10 ? "0" + value : String(value);
        }
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
    }

    function historyFromDetails(sections, now) {
        var today = new Date(now === undefined ? Date.now() : now);
        var start = new Date(today);
        start.setDate(start.getDate() - 6);
        var firstDay = dayKey(start);
        var lastDay = dayKey(today);
        for (var i = 0; i < sections.length; ++i) {
            var chart = sections[i].chart;
            if (chart != null)
                checkedObject(chart);
            if (!chart || chart.unit !== "tokens" || !/daily/i.test(sections[i].title || chart.title || ""))
                continue;
            var points = checkedArray(chart.points, 366);
            var total = 0;
            var count = 0;
            for (var j = 0; j < points.length; ++j) {
                var point = checkedObject(points[j]);
                var date = checkedText(point.label).match(/^\d{4}-\d{2}-\d{2}/);
                if (!date || !numeric(point.value) || point.value < 0)
                    continue;
                if (date[0] >= firstDay && date[0] <= lastDay) {
                    total += point.value;
                    ++count;
                }
            }
            if (count)
                return numeric(total) ? data.historyResult(total, true, "Recorded provider activity") : data.historyResult(null, true, "Invalid token total", "error");
        }
        return null;
    }

    function historyResult(tokens, partial, note, state) {
        return {
            state: state || (data.numeric(tokens) ? "ready" : "empty"),
            tokens: tokens,
            partial: partial,
            note: note
        };
    }

    function decodeHistory(stdout, provider) {
        var record = recordFor(stdout, provider);
        var gemini = provider === "antigravity";
        if (record.totals != null)
            checkedObject(record.totals);
        var total = gemini ? null : record.totals && record.totals.totalTokens;
        var partial = record.historyCoverageIsEstablished === false || record.incompleteRequestCount > 0;
        var daily = checkedArray(record.daily, 31);
        if (!data.numeric(total)) {
            var known = false;
            total = 0;
            function add(value) {
                if (data.numeric(value) && (!gemini || value >= 0)) {
                    total += value;
                    known = true;
                } else
                    partial = true;
            }
            daily.forEach(function (day) {
                data.checkedObject(day);
                if (!gemini) {
                    add(day.totalTokens);
                    return;
                }
                var models = data.checkedArray(day.modelBreakdowns, 128);
                if (models.length) {
                    models.forEach(function (model) {
                        data.checkedObject(model);
                        if (/\bgemini\b/i.test(data.checkedText(model.modelName)))
                            add(model.totalTokens);
                    });
                } else {
                    var modelsUsed = data.checkedArray(day.modelsUsed, 128);
                    if (modelsUsed.some(model => typeof model !== "string"))
                        throw new Error("Invalid provider data.");
                    if (modelsUsed.length && modelsUsed.every(model => /\bgemini\b/i.test(data.checkedText(model))))
                        add(day.totalTokens);
                    else
                        partial = true;
                }
            });
            if (!known)
                return data.historyResult(null, gemini && partial, gemini ? "Gemini token totals not reported separately" : daily.length ? "Token totals are unavailable" : "No token history reported for the last 7 days");
        }
        if (!numeric(total) || total < 0)
            throw new Error("Invalid token total");
        return data.historyResult(total, partial, gemini ? (partial ? "Recorded Gemini total · history is incomplete" : "Recorded Gemini token usage") : (partial ? "Recorded total · history is incomplete" : "Recorded local token usage"));
    }
}
