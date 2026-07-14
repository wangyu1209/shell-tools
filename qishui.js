// ====================
// 1. 初始化
// ====================
auto.waitFor();
console.show();
log("脚本已启动...");

// ====================
// 2. 高频反直播弹窗线程（核心修复）
// ====================
var cancelLiveThreadFlag = true;

var cancelLiveThread = threads.start(function () {
    log("[反直播线程] 已启动，持续监控中...");
    var cancelCount = 0;

    while (cancelLiveThreadFlag) {
        try {
            // === 策略1：检测"取消"按钮（text/desc/className 多维度）===
            var cancelBtns = text("取消").find()
                .concat(desc("取消").find())
                .concat(className("android.widget.TextView").text("取消").find());

            if (cancelBtns.length > 0) {
                for (var i = 0; i < cancelBtns.length; i++) {
                    var btn = cancelBtns[i];
                    var b = btn.bounds();
                    // 确认在屏幕可视范围内
                    if (b && b.left >= 0 && b.top >= 0
                        && b.right <= device.width
                        && b.bottom <= device.height
                        && b.width() > 10 && b.height() > 10) {

                        // 检查周围是否有直播相关关键词（提高置信度）
                        var hasLiveHint = textContains("直播").findOnce()
                            || textContains("即将进入").findOnce()
                            || textContains("正在进入").findOnce()
                            || textContains("秒后进入").findOnce()
                            || descContains("直播").findOnce()
                            || descContains("即将进入").findOnce();

                        if (hasLiveHint) {
                            cancelCount++;
                            log("[反直播线程] ★★★ 确认直播弹窗，第 " + cancelCount + " 次点击取消");
                            click(b.centerX(), b.centerY());
                            sleep(500);
                            // 二次确认是否已消失
                            if (!text("取消").findOnce() || !textContains("直播").findOnce()) {
                                log("[反直播线程] ✔ 弹窗已关闭");
                            }
                        }
                    }
                }
            }

            // === 策略2：无"取消"文字但检测到直播弹窗关键词 → 坐标兜底 ===
            var livePopup =
                textContains("即将进入直播").findOnce() ||
                textContains("正在进入直播").findOnce() ||
                textContains("秒后自动进入").findOnce() ||
                textContains("秒后进入").findOnce() ||
                descContains("即将进入直播").findOnce() ||
                descContains("秒后自动进入").findOnce();

            if (livePopup) {
                log("[反直播线程] ★★★ 检测到直播弹窗关键词（无取消按钮），尝试坐标点击");
                // 弹窗通常在屏幕中部偏上，取消在右下角区域
                // 根据描述"右边有个取消字符"，尝试点击右侧
                var guessX = Math.round(device.width * 0.75);
                var guessY = Math.round(device.height * 0.58);
                click(guessX, guessY);
                sleep(300);
                // 也尝试偏右上的位置
                click(Math.round(device.width * 0.82), Math.round(device.height * 0.55));
                sleep(300);
            }

            // === 策略3：通过控件树深度搜索，查找含"消"字的可点击元素 ===
            var anyCancel = className("android.widget.Button").textContains("消").findOnce()
                || className("android.view.View").descContains("消").findOnce()
                || className("android.widget.ImageView").descContains("消").findOnce();

            if (anyCancel) {
                var b2 = anyCancel.bounds();
                if (b2 && b2.width() > 0) {
                    log("[反直播线程] ★ 通过'消'字模糊匹配找到按钮，点击");
                    click(b2.centerX(), b2.centerY());
                    sleep(500);
                }
            }

        } catch (e) {
            // 静默处理，不打断主流程
        }

        sleep(300); // 每 300ms 轮询一次
    }
    log("[反直播线程] 已停止");
});

// 确保脚本退出时线程也停止
events.on("exit", function () {
    cancelLiveThreadFlag = false;
    if (cancelLiveThread && cancelLiveThread.isAlive()) {
        cancelLiveThread.interrupt();
    }
});

// ====================
// 3. 启动并进入"我的"页面
// ====================
function ensureAtMyPage() {
    if (textContains("继续领").exists() || text("我的").exists()) return true;

    log("正在重置状态，回到'我的'页面...");
    launchApp("汽水音乐");
    sleep(3000);

    var myTab = text("我的").findOne(5000);
    if (myTab) {
        click(myTab.bounds().centerX(), myTab.bounds().centerY());
        sleep(2000);
        return true;
    }
    return false;
}

ensureAtMyPage();

// ★ 保留作为主线程辅助（线程是主力，这里是补充）
function tryClickCancel() {
    var cancelBtn = text("取消").findOnce()
        || textContains("取消").findOnce()
        || descContains("取消").findOnce();
    if (cancelBtn) {
        var b = cancelBtn.bounds();
        if (b && b.width() > 10 && b.height() > 10) {
            log("[主线程] 检测到'取消'，点击");
            click(b.centerX(), b.centerY());
            sleep(800);
            return true;
        }
    }
    return false;
}

// ====================
// 4. 主循环
// ====================
log("--- 进入主循环 ---");
var adsWatched = 0;

while (true) {

    tryClickCancel();

    // 检测"提醒我每天来" → 点击后退出
    var remindBtn = textContains("提醒我每天来").findOnce()
        || descContains("提醒我每天来").findOnce();
    if (remindBtn) {
        log("检测到'提醒我每天来'，点击");
        var b = remindBtn.bounds();
        click(b.centerX(), b.centerY());
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

function findRewardButton(timeoutMs) {
    var deadline = new Date().getTime() + timeoutMs;
    while (new Date().getTime() < deadline) {
        var btn =
            textContains("领取奖励").findOnce() ||
            descContains("领取奖励").findOnce() ||
            textMatches(/.*领取.*奖励.*/).findOnce() ||
            descMatches(/.*领取.*奖励.*/).findOnce();
        if (btn) return btn;
        sleep(300);
    }
    return null;
}

function clickRewardButton(btn) {
    if (btn) {
        var current = btn;
        for (var i = 0; current && i < 5; i++) {
            if (current.clickable && current.clickable()) {
                return current.click();
            }
            current = current.parent();
        }
        var b = btn.bounds();
        return click(b.centerX(), b.centerY());
    }
    return click(device.width * 0.5, device.height * 0.55);
}

// ====================
// 5. 等待广告结束
// ====================
function waitForAdFinish(maxWaitMs) {
    var deadline = new Date().getTime() + maxWaitMs;
    var waited = 0;

    while (new Date().getTime() < deadline) {

        tryClickCancel();

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
            log("检测到'领取成功'，广告已播放完毕 (已等" + waited + "秒)");
            return "claimSuccess";
        }

        if (text("反馈").findOnce()) {
            log("广告已出现关闭按钮 (已等" + waited + "秒)");
            return "feedback";
        }
        if (textContains("更多直播").findOnce()) {
            log("检测到'更多直播' (已等" + waited + "秒)");
            return "moreLive";
        }
        if (textContains("坚持退出").findOnce()) {
            log("检测到'坚持退出'弹窗 (已等" + waited + "秒)");
            return "exit";
        }
        if (textContains("领取奖励").findOnce()) {
            log("检测到'领取奖励' (已等" + waited + "秒)");
            return "reward";
        }

        sleep(1000);
        waited++;
        if (waited % 10 === 0) {
            log("广告播放中... 已等待 " + waited + " 秒");
        }
    }

    log("已等待满 " + (maxWaitMs / 1000) + " 秒，执行关闭");
    return "timeout";
}

// ====================
// 6. 点击"领取成功"后的处理
// ====================
function handleAfterClaimSuccess() {
    log("等待'领取奖励'/'继续观看'/'继续互动'出现...");
    sleep(2000);

    var deadline = new Date().getTime() + 10000;

    while (new Date().getTime() < deadline) {

        tryClickCancel();

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
            log("出现'继续观看'，点击继续看下一条广告");
            click(watchBtn.bounds().centerX(), watchBtn.bounds().centerY());
            sleep(2000);
            return "continue";
        }

        var interactBtn = textContains("继续互动").findOnce()
            || descContains("继续互动").findOnce();
        if (interactBtn) {
            log("出现'继续互动'，点击继续");
            click(interactBtn.bounds().centerX(), interactBtn.bounds().centerY());
            sleep(2000);
            return "continue";
        }

        var remindBtn2 = textContains("提醒我每天来").findOnce()
            || descContains("提醒我每天来").findOnce();
        if (remindBtn2) {
            log("出现'提醒我每天来'，点击");
            click(remindBtn2.bounds().centerX(), remindBtn2.bounds().centerY());
            sleep(2000);
            return "remind";
        }

        var exitBtn = textContains("坚持退出").findOnce();
        if (exitBtn) {
            log("出现'坚持退出'");
            click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
            sleep(2000);
            return "exit";
        }

        sleep(500);
    }

    log("未检测到后续按钮，盲点领取区域");
    click(device.width * 0.5, device.height * 0.55);
    sleep(2000);
    return "unknown";
}

// ====================
// 7. 广告处理
// ====================
function waitAndCloseAd() {
    log("正在加载广告...");
    sleep(3000);

    while (true) {
        var result = waitForAdFinish(45000);

        if (result === "claimSuccess") {
            log("点击'领取成功'按钮");
            var claimBtn = textContains("领取成功").findOnce();
            if (claimBtn) {
                click(claimBtn.bounds().centerX(), claimBtn.bounds().centerY());
            } else {
                click(device.width * 0.92, device.height * 0.065);
            }
            sleep(1500);

            var afterResult = handleAfterClaimSuccess();

            if (afterResult === "continue") {
                log("进入下一条广告...");
                continue;
            }

            if (afterResult === "reward") {
                adsWatched++;
                log("已领奖励，累计观看 " + adsWatched + " 条");
                tryClickCancel();

                var exitBtn = textContains("坚持退出").findOne(2000);
                if (exitBtn) {
                    log("点击'坚持退出'");
                    click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
                    sleep(2000);
                    break;
                }

                sleep(2000);
                if (textContains("继续领").findOnce() || textContains("领时长").findOnce()) {
                    log("已回到任务页，退出广告流程");
                    break;
                }
                log("继续下一轮广告");
                continue;
            }

            if (afterResult === "remind") {
                log("执行完毕");
                home();
                exit();
            }

            break;

        } else if (result === "feedback") {
            log("通过'反馈'定位关闭");
            var feedbackBtn = text("反馈").findOnce();
            if (feedbackBtn) {
                click(device.width - 80, feedbackBtn.bounds().centerY());
            } else {
                click(device.width * 0.92, device.height * 0.065);
            }
            sleep(1000);
            tryClickCancel();
            sleep(2000);

        } else if (result === "moreLive") {
            log("发现'更多直播'，点击退出");
            click(device.width * 0.92, device.height * 0.065);
            sleep(1000);
            tryClickCancel();
            sleep(2000);

        } else if (result === "reward") {
            log("直接出现领取奖励，点击");
            var rewardBtn2 = textContains("领取奖励").findOnce();
            if (rewardBtn2) {
                click(rewardBtn2.bounds().centerX(), rewardBtn2.bounds().centerY());
            } else {
                click(device.width * 0.5, device.height * 0.55);
            }
            sleep(1000);
            tryClickCancel();
            sleep(1500);

        } else if (result === "exit") {
            log("点击'坚持退出'");
            var exitBtn2 = textContains("坚持退出").findOnce();
            if (exitBtn2) {
                click(exitBtn2.bounds().centerX(), exitBtn2.bounds().centerY());
            }
            sleep(2000);
            break;
        }

        tryClickCancel();
        sleep(2000);

        var exitBtn3 = textContains("坚持退出").findOne(1000);
        if (exitBtn3) {
            log("点击'坚持退出'");
            click(exitBtn3.bounds().centerX(), exitBtn3.bounds().centerY());
            sleep(2000);
            break;
        }

        var inRewardAdPage = currentActivity().indexOf("ExcitingVideoActivity") >= 0;
        if (inRewardAdPage) {
            log("仍在广告奖励页，继续下一条广告");
            continue;
        }

        log("广告流程结束，回到主页");
        break;
    }
}
