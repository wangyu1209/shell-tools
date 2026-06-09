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

// ====================
// 3. 主循环 (简化版)
// ====================
log("--- 进入主循环 ---");
var adsWatched = 0;

while (true) {
    if (textContains("恭喜获得第30日畅听").findOnce()) {
        log("已领取第30日畅听，任务完成，准备返回桌面");
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
// 4. 广告处理 (含连播逻辑)
// ====================
function waitAndCloseAd() {
    log("正在加载广告...");
    sleep(3000);

    while (true) {
        log(">>> 广告播放中 (等待41秒) <<<");
        sleep(41000);

        var zhiboBtn = textContains("更多直播").findOne(3000);
        if(zhiboBtn){
          log("发现'更多直播'，点击退出");
          click(device.width * 0.92, device.height * 0.065);
        }

        var feedbackBtn = text("反馈").findOne(2000);
        if (feedbackBtn) {
            log("通过'反馈'定位关闭");
            click(device.width - 80, feedbackBtn.bounds().centerY());
        } else {
            log("盲点右上角关闭");
            click(device.width * 0.92, device.height * 0.065);
        }

        log("检测是否有下一条...");
        sleep(3000);

        var inRewardAdPage = currentActivity().indexOf("ExcitingVideoActivity") >= 0;

        if (inRewardAdPage) {
            adsWatched++;
            log("仍在广告奖励页，已看第 " + adsWatched + " 条广告");

            if (adsWatched >= 2) {
                log("已看满2条，尝试领取奖励");
                var clickedByFallback = click(device.width * 0.5, device.height * 0.55);
                log("领取奖励盲点结果: " + clickedByFallback);
                adsWatched = 0;
            }

            sleep(2500);
            continue;
        }

        var exitBtn = textContains("坚持退出").findOne(1000);
        if (exitBtn) {
            log("点击'坚持退出'");
            click(exitBtn.bounds().centerX(), exitBtn.bounds().centerY());
            sleep(2000);
            break;
        }

        log("最终未检测到奖励页或退出页，没关系不进行 break，不断的去撞击广告。");
    }
}
