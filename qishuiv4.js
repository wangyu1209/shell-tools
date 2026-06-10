// ====================
// 1. 初始化
// ====================
auto.waitFor();
console.show();
log("脚本已启动...");

// ====================
// 2. 启动并进入"我的"页面
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

// ★ 通用：检测并点击"取消"，防止进入直播间
function tryClickCancel() {
    var cancelBtn = text("取消").findOnce() || textContains("取消").findOnce() || descContains("取消").findOnce();
    if (cancelBtn) {
        log("检测到'取消'，点击关闭（防止进入直播间）");
        var b = cancelBtn.bounds();
        click(b.centerX(), b.centerY());
        sleep(1000);
        return true;
    }
    return false;
}

// ====================
// 3. 主循环
// ====================
log("--- 进入主循环 ---");
var adsWatched = 0;

while (true) {

    // ★ 主循环也检测一下取消
    tryClickCancel();

    // 检测"提醒我每天来" → 点击后退出
    var remindBtn = textContains("提醒我每天来").findOnce() || descContains("提醒我每天来").findOnce();
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
        log("已领取第30日畅听，任务完成，准备返回桌面");
        log("执行完毕");
        home();
        break;
    }

    var startBtn = textContains("继续领").findOne(3000) || textContains("领时长").findOne(3000);

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
// 4. 等待广告结束
// ====================
function waitForAdFinish(maxWaitMs) {
    var deadline = new Date().getTime() + maxWaitMs;
    var waited = 0;

    while (new Date().getTime() < deadline) {

        // ★ 检测"取消"防止进入直播间
        if (tryClickCancel()) {
            // 点了取消后继续等，不跳出
        }

        var continueBtn = textContains("继续观看").findOnce() || descContains("继续观看").findOnce();
        if (continueBtn) {
            log("检测到'继续观看'按钮，点击继续");
            var b = continueBtn.bounds();
            click(b.centerX(), b.centerY());
            sleep(2000);
        }

        var interactBtn = textContains("继续互动").findOnce() || descContains("继续互动").findOnce();
        if (interactBtn) {
            log("检测到'继续互动'按钮，点击继续");
            var b2 = interactBtn.bounds();
            click(b2.centerX(), b2.centerY());
            sleep(2000);
        }

        var claimSuccessBtn = textContains("领取成功").findOnce() || descContains("领取成功").findOnce();
        if (claimSuccessBtn) {
            log("检测到'领取成功'按钮，广告已播放完毕 (已等" + waited + "秒)");
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
// 5. 点击"领取成功"后的处理
// ====================
function handleAfterClaimSuccess() {
    log("等待'领取奖励'/'继续观看'/'继续互动'出现...");
    sleep(2000);

    var deadline = new Date().getTime() + 10000;

    while (new Date().getTime() < deadline) {

        // ★ 检测"取消"防止进入直播间
        if (tryClickCancel()) {
            // 点了取消后继续检测
        }

        var rewardBtn = textContains("领取奖励").findOnce() || descContains("领取奖励").findOnce();
        if (rewardBtn) {
            log("✔ 出现'领取奖励'，点击领取");
            var b = rewardBtn.bounds();
            click(b.centerX(), b.centerY());
            sleep(2000);
            return "reward";
        }

        var watchBtn = textContains("继续观看").findOnce() || descContains("继续观看").findOnce();
        if (watchBtn) {
            log("出现'继续观看'，点击继续看下一条广告");
            var b2 = watchBtn.bounds();
            click(b2.centerX(), b2.centerY());
            sleep(2000);
            return "continue";
        }

        var interactBtn = textContains("继续互动").findOnce() || descContains("继续互动").findOnce();
        if (interactBtn) {
            log("出现'继续互动'，点击继续");
            var b3 = interactBtn.bounds();
            click(b3.centerX(), b3.centerY());
            sleep(2000);
            return "continue";
        }

        var remindBtn = textContains("提醒我每天来").findOnce() || descContains("提醒我每天来").findOnce();
        if (remindBtn) {
            log("出现'提醒我每天来'，点击");
            var b4 = remindBtn.bounds();
            click(b4.centerX(), b4.centerY());
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
// 6. 广告处理
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
                var b = claimBtn.bounds();
                click(b.centerX(), b.centerY());
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

                // ★ 领完奖励后也检测取消
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
            // ★ 关闭后也检测取消
            sleep(1000);
            tryClickCancel();
            sleep(2000);

        } else if (result === "moreLive") {
            log("发现'更多直播'，点击退出");
            click(device.width * 0.92, device.height * 0.065);
            // ★ 关闭后也检测取消
            sleep(1000);
            tryClickCancel();
            sleep(2000);

        } else if (result === "reward") {
            log("直接出现领取奖励，点击");
            var rewardBtn = textContains("领取奖励").findOnce();
            if (rewardBtn) {
                click(rewardBtn.bounds().centerX(), rewardBtn.bounds().centerY());
            } else {
                click(device.width * 0.5, device.height * 0.55);
            }
            // ★ 领完后也检测取消
            sleep(1000);
            tryClickCancel();
            sleep(1500);

        } else if (result === "exit") {
            log("点击'坚持退出'");
            var exitBtn = textContains("坚持退出").findOnce();
            if (exitBtn) {
                click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
            }
            sleep(2000);
            break;
        }

        // ★ 通用后续：先检测取消
        tryClickCancel();
        sleep(2000);

        var exitBtn = textContains("坚持退出").findOne(1000);
        if (exitBtn) {
            log("点击'坚持退出'");
            click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
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
