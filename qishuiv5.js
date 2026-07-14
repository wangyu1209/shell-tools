// =====================================================
//  汽水音乐自动化脚本 v2
//  功能：跳过开屏广告 → 领时长 → 拦截自动进入直播间
// =====================================================

auto.waitFor();
console.show();
log("脚本已启动...");

// ==================== 设备参数缓存 ====================
var W = device.width;
var H = device.height;

// ==================== 全局控制 ====================
var stopLiveGuard = false;
var alreadyInLiveGuard = false; // 防止重复启动

// =====================================================
//  模块一：开屏广告跳过
// =====================================================
function skipSplashAd(timeoutMs) {
    timeoutMs = timeoutMs || 8000;
    var deadline = Date.now() + timeoutMs;
    var skipped = false;

    log("[开屏] 开始监控跳过按钮（" + (timeoutMs / 1000) + "秒超时）...");

    while (Date.now() < deadline && !skipped) {
        // 匹配 "跳过" / "跳过广告" / "跳过 x" / 倒计时跳过
        var skipBtn =
            textMatches(/跳过\s*\d*/).findOnce() ||
            textContains("跳过").findOnce() ||
            descMatches(/跳过\s*\d*/).findOnce() ||
            descContains("跳过").findOnce();

        if (skipBtn) {
            var b = skipBtn.bounds();
            if (b && b.width() > 5 && b.height() > 5) {
                log("[开屏] ★ 发现跳过按钮，点击");
                // 先尝试点 clickable 自身
                if (skipBtn.clickable && skipBtn.clickable()) {
                    skipBtn.click();
                } else {
                    // 向上找 clickable 父节点
                    var p = skipBtn.parent();
                    for (var i = 0; i < 4 && p; i++) {
                        if (p.clickable && p.clickable()) {
                            p.click();
                            break;
                        }
                        p = p.parent();
                    }
                    if (!p) click(b.centerX(), b.centerY());
                }
                sleep(500);
                skipped = true;
            }
        }

        // 额外检测：有些APP跳过按钮是纯图标，坐标通常在右上角
        // 如果文字检测没找到，尝试点击右上角区域（仅在开屏阶段）
        if (!skipped && Date.now() > deadline - 3000) {
            // 最后3秒仍未找到，尝试盲点右上角
            var blind = className("android.view.View")
                .boundsInside(W - 250, 0, W, 200)
                .findOnce();
            if (blind && blind.clickable) {
                log("[开屏] 盲点右上角可点击区域");
                blind.click();
                sleep(500);
                skipped = true;
            }
        }

        sleep(200);
    }

    if (!skipped) {
        log("[开屏] 未检测到跳过按钮，可能无开屏广告");
    }
    return skipped;
}

// =====================================================
//  模块二：拦截自动进入直播间（多策略）
// =====================================================

// --- 策略A：文字匹配（最快的策略）---
function tryCancelByText() {
    var targets = text("取消").find()
        .concat(textContains("取消").find())
        .concat(desc("取消").find())
        .concat(descContains("取消").find());

    for (var i = 0; i < targets.length; i++) {
        var node = targets[i];
        var b = node.bounds();
        if (!b || b.width() < 10 || b.height() < 10) continue;
        if (b.left < 0 || b.top < 0 || b.right > W + 10 || b.bottom > H + 10) continue;

        // 验证：附近有直播相关文字 → 确认是直播间弹窗
        var nearby = boundsInScreen().find();
        var isLivePopup = false;

        var liveCheck =
            textContains("直播").findOnce() ||
            textContains("即将进入").findOnce() ||
            textContains("正在进入").findOnce() ||
            textContains("秒后").findOnce() ||
            textContains("自动进入").findOnce() ||
            descContains("直播").findOnce() ||
            descContains("即将进入").findOnce() ||
            descContains("自动进入").findOnce();

        if (liveCheck) {
            isLivePopup = true;
        }

        // 如果没有直播关键词但当前在直播相关Activity，也判定为需要取消
        var act = currentActivity() || "";
        if (act.toLowerCase().indexOf("live") >= 0 ||
            act.toLowerCase().indexOf("webcast") >= 0 ||
            act.toLowerCase().indexOf("streaming") >= 0) {
            isLivePopup = true;
        }

        if (isLivePopup) {
            click(b.centerX(), b.centerY());
            sleep(300);
            return true;
        }
    }
    return false;
}

// --- 策略B：Activity 监控（弹窗如果跳转到直播Activity立即返回）---
var lastActivity = "";
var activityHistory = [];

function monitorActivity() {
    var cur = currentActivity();
    if (cur && cur !== lastActivity) {
        activityHistory.push({ name: cur, time: Date.now() });
        if (activityHistory.length > 20) activityHistory.shift();

        var curLower = cur.toLowerCase();
        var isLiveActivity =
            curLower.indexOf("live") >= 0 ||
            curLower.indexOf("webcast") >= 0 ||
            curLower.indexOf("streaming") >= 0 ||
            curLower.indexOf("room") >= 0;

        if (isLiveActivity) {
            log("[直播拦截] ★ 检测到直播Activity: " + cur);
            sleep(500);
            back();
            sleep(500);
            back();
            lastActivity = currentActivity();
            return true;
        }
        lastActivity = cur;
    }
    return false;
}

// --- 策略C：坐标盲点（透明弹窗无障碍树抓不到时的终极方案）---
var blindClickCount = 0;

function blindCancelLive() {
    // 多个常见"取消"位置坐标
    var positions = [
        // 右侧偏上（你描述的"右边有取消"）
        [Math.round(W * 0.82), Math.round(H * 0.52)],
        [Math.round(W * 0.80), Math.round(H * 0.50)],
        [Math.round(W * 0.85), Math.round(H * 0.55)],
        // 弹窗右上角关闭
        [Math.round(W * 0.90), Math.round(H * 0.35)],
        [Math.round(W * 0.88), Math.round(H * 0.38)],
        // 弹窗底部取消按钮区域
        [Math.round(W * 0.65), Math.round(H * 0.62)],
        [Math.round(W * 0.70), Math.round(H * 0.60)],
        // 屏幕右侧中央
        [Math.round(W * 0.75), Math.round(H * 0.50)],
    ];

    // 检测是否有半透明覆盖层（通过找直播弹窗关键词确认）
    var hasOverlay =
        textContains("直播").findOnce() ||
        textContains("即将进入").findOnce() ||
        textContains("自动进入").findOnce() ||
        textContains("秒后").findOnce();

    if (hasOverlay) {
        log("[直播拦截-C] 检测到弹窗覆盖层，尝试坐标盲点");
        for (var i = 0; i < positions.length; i++) {
            click(positions[i][0], positions[i][1]);
            sleep(150);
        }
        blindClickCount++;
        return true;
    }
    return false;
}

// --- 策略D：检测浮层View（检查z-order高的可疑View）---
function detectOverlayByNodeTree() {
    // 查找屏幕上所有带"消"或"关闭"或"×"文字/desc的控件
    var suspects =
        textContains("消").find()
            .concat(descContains("消").find())
            .concat(textContains("关闭").find())
            .concat(descContains("关闭").find())
            .concat(textContains("×").find())
            .concat(descContains("×").find())
            .concat(textContains("✕").find())
            .concat(descContains("✕").find());

    for (var i = 0; i < suspects.length; i++) {
        var node = suspects[i];
        var b = node.bounds();
        if (!b) continue;
        // 排除明显不是按钮的元素（太大=全屏，太小=不是按钮）
        if (b.width() > 5 && b.width() < 200 && b.height() > 5 && b.height() < 120) {
            // 在弹窗常见区域（屏幕中央偏上到中央）
            if (b.top > H * 0.3 && b.bottom < H * 0.75) {
                log("[直播拦截-D] 找到可疑关闭/取消控件: " +
                    (node.text() || node.desc() || "") +
                    " bounds=" + b);
                click(b.centerX(), b.centerY());
                sleep(300);
                return true;
            }
        }
    }
    return false;
}

// --- 主守护线程（整合ABCD策略）---
function startLiveGuard() {
    if (alreadyInLiveGuard) return;
    alreadyInLiveGuard = true;
    stopLiveGuard = false;

    threads.start(function () {
        log("[直播守护线程] ★ 已启动");

        var cycle = 0;
        while (!stopLiveGuard) {
            cycle++;

            try {
                // 策略A：文字匹配（最优先，每轮都跑）
                if (tryCancelByText()) {
                    log("[直播守护线程-A] ✔ 已取消（文字匹配）");
                    sleep(1000);
                    continue;
                }

                // 策略D：控件树深度搜索
                if (detectOverlayByNodeTree()) {
                    log("[直播守护线程-D] ✔ 已取消（控件树搜索）");
                    sleep(1000);
                    continue;
                }

                // 策略C：坐标盲点（仅在检测到直播相关关键词时触发）
                if (blindCancelLive()) {
                    log("[直播守护线程-C] ✔ 已执行坐标盲点");
                    sleep(1000);
                    continue;
                }

                // 策略B：Activity 监控（低频，每2秒一次）
                if (cycle % 7 === 0) {
                    if (monitorActivity()) {
                        log("[直播守护线程-B] ✔ 已返回（Activity检测）");
                    }
                }

            } catch (e) {
                // 静默
            }

            sleep(300);
        }

        log("[直播守护线程] 已停止");
        alreadyInLiveGuard = false;
    });
}

// 脚本退出时停止
events.on("exit", function () {
    stopLiveGuard = true;
});

// =====================================================
//  模块三：任务主页操作
// =====================================================
function ensureAtMyPage() {
    if (textContains("继续领").exists() || text("我的").exists()) return true;

    log("正在重置状态，回到'我的'页面...");
    launchApp("汽水音乐");
    sleep(3000);

    // ★ 首次启动时跳过开屏广告
    skipSplashAd(6000);

    var myTab = text("我的").findOne(5000);
    if (myTab) {
        click(myTab.bounds().centerX(), myTab.bounds().centerY());
        sleep(2000);
        return true;
    }
    return false;
}

// =====================================================
//  主流程
// =====================================================
log("--- 启动应用 ---");
launchApp("汽水音乐");
sleep(2000);

// ① 跳过开屏广告
skipSplashAd(8000);

// ② 启动直播守护线程
startLiveGuard();

// ③ 进入"我的"页面
ensureAtMyPage();

// ④ 进入主循环
log("--- 进入主循环 ---");
var adsWatched = 0;

while (true) {

    // 检测"提醒我每天来" → 点击后退出
    var remindBtn = textContains("提醒我每天来").findOnce()
        || descContains("提醒我每天来").findOnce();
    if (remindBtn) {
        log("检测到'提醒我每天来'，点击");
        click(remindBtn.bounds().centerX(), remindBtn.bounds().centerY());
        sleep(2000);
        log("执行完毕");
        home();
        break;
    }

    if (textContains("恭喜获得第30日畅听").findOnce()) {
        log("已领取第30日畅听，任务完成");
        log("执行完毕");
        home();
        break;
    }

    var startBtn = textContains("继续领").findOne(3000)
        || textContains("领时长").findOne(3000);

    if (startBtn) {
        log("发现'继续领'，点击开始看广告");
        click(startBtn.bounds().centerX(), startBtn.bounds().centerY());
        waitAndCloseAd();

        var delayTime = random(4000, 7000);
        log("休息 " + (delayTime / 1000).toFixed(1) + " 秒...");
        sleep(delayTime);
    } else {
        log("未找到'继续领'按钮，正在检查状态...");
        var myTab = text("我的").findOnce();
        if (myTab && !myTab.isSelected()) {
            click(myTab.bounds().centerX(), myTab.bounds().centerY());
        }
        sleep(3000);
    }
}

// =====================================================
//  广告等待与关闭
// =====================================================
function waitForAdFinish(maxWaitMs) {
    var deadline = Date.now() + maxWaitMs;
    var waited = 0;

    while (Date.now() < deadline) {

        var continueBtn = textContains("继续观看").findOnce()
            || descContains("继续观看").findOnce();
        if (continueBtn) {
            log("检测到'继续观看'按钮，点击继续");
            click(continueBtn.bounds().centerX(), continueBtn.bounds().centerY());
            sleep(2000);
        }

        var interactBtn = textContains("继续互动").findOnce()
            || descContains("继续互动").findOnce();
        if (interactBtn) {
            log("检测到'继续互动'按钮，点击继续");
            click(interactBtn.bounds().centerX(), interactBtn.bounds().centerY());
            sleep(2000);
        }

        var claimSuccessBtn = textContains("领取成功").findOnce()
            || descContains("领取成功").findOnce();
        if (claimSuccessBtn) {
            log("检测到'领取成功' (已等" + waited + "秒)");
            return "claimSuccess";
        }

        if (text("反馈").findOnce()) return "feedback";
        if (textContains("更多直播").findOnce()) return "moreLive";
        if (textContains("坚持退出").findOnce()) return "exit";
        if (textContains("领取奖励").findOnce()) return "reward";

        sleep(1000);
        waited++;
        if (waited % 10 === 0) log("广告播放中... 已等待 " + waited + " 秒");
    }

    log("等待超时 " + (maxWaitMs / 1000) + " 秒");
    return "timeout";
}

function handleAfterClaimSuccess() {
    log("等待后续按钮出现...");
    sleep(2000);
    var deadline = Date.now() + 10000;

    while (Date.now() < deadline) {

        var rewardBtn = textContains("领取奖励").findOnce()
            || descContains("领取奖励").findOnce();
        if (rewardBtn) {
            log("✔ 出现'领取奖励'，点击领取");
            click(rewardBtn.bounds().centerX(), rewardBtn.bounds().centerY());
            sleep(2000);
            return "reward";
        }

        var watchBtn = textContains("继续观看").findOnce()
            || descContains("继续观看").findOnce();
        if (watchBtn) {
            log("出现'继续观看'");
            click(watchBtn.bounds().centerX(), watchBtn.bounds().centerY());
            sleep(2000);
            return "continue";
        }

        var interactBtn = textContains("继续互动").findOnce()
            || descContains("继续互动").findOnce();
        if (interactBtn) {
            log("出现'继续互动'");
            click(interactBtn.bounds().centerX(), interactBtn.bounds().centerY());
            sleep(2000);
            return "continue";
        }

        var remindBtn = textContains("提醒我每天来").findOnce()
            || descContains("提醒我每天来").findOnce();
        if (remindBtn) {
            log("出现'提醒我每天来'");
            click(remindBtn.bounds().centerX(), remindBtn.bounds().centerY());
            sleep(2000);
            return "remind";
        }

        if (textContains("坚持退出").findOnce()) {
            var exitBtn = textContains("坚持退出").findOnce();
            click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
            sleep(2000);
            return "exit";
        }

        sleep(500);
    }

    log("未检测到后续按钮，盲点领取区域");
    click(W * 0.5, H * 0.55);
    sleep(2000);
    return "unknown";
}

function waitAndCloseAd() {
    log("正在加载广告...");
    sleep(3000);

    while (true) {
        var result = waitForAdFinish(45000);

        if (result === "claimSuccess") {
            log("点击'领取成功'");
            var claimBtn = textContains("领取成功").findOnce();
            if (claimBtn) {
                click(claimBtn.bounds().centerX(), claimBtn.bounds().centerY());
            } else {
                click(W * 0.92, H * 0.065);
            }
            sleep(1500);

            var afterResult = handleAfterClaimSuccess();

            if (afterResult === "continue") {
                log("进入下一条广告...");
                continue;
            }

            if (afterResult === "reward") {
                adsWatched++;
                log("已领奖励，累计 " + adsWatched + " 条");
                var exitBtn = textContains("坚持退出").findOne(2000);
                if (exitBtn) {
                    click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
                    sleep(2000);
                    break;
                }
                sleep(2000);
                if (textContains("继续领").findOnce() || textContains("领时长").findOnce()) {
                    log("已回到任务页");
                    break;
                }
                log("继续下一轮");
                continue;
            }

            if (afterResult === "remind") {
                log("执行完毕");
                home();
                exit();
            }
            break;

        } else if (result === "feedback") {
            var fb = text("反馈").findOnce();
            if (fb) {
                click(W - 80, fb.bounds().centerY());
            } else {
                click(W * 0.92, H * 0.065);
            }
            sleep(2000);

        } else if (result === "moreLive") {
            click(W * 0.92, H * 0.065);
            sleep(2000);

        } else if (result === "reward") {
            var rb = textContains("领取奖励").findOnce();
            if (rb) {
                click(rb.bounds().centerX(), rb.bounds().centerY());
            } else {
                click(W * 0.5, H * 0.55);
            }
            sleep(1500);

        } else if (result === "exit") {
            var eb = textContains("坚持退出").findOnce();
            if (eb) click(eb.bounds().centerX(), eb.bounds().centerY());
            sleep(2000);
            break;
        }

        sleep(2000);
        var eb2 = textContains("坚持退出").findOne(1000);
        if (eb2) {
            click(eb2.bounds().centerX(), eb2.bounds().centerY());
            sleep(2000);
            break;
        }

        var act = currentActivity() || "";
        if (act.indexOf("ExcitingVideoActivity") >= 0) {
            log("仍在广告页，继续");
            continue;
        }

        log("广告流程结束");
        break;
    }
}
