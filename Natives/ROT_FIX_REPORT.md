# 【A|旋转适配】顶部工具条「旋转后只剩半截」——根因与修复报告

工程树：`D:\CTF\_uibuild\repo`（fork 分支 `ui/e-design-1` 工作树）
改动文件（**仅**这 2 个，均在 `Natives/` 内）：
- `Natives/LauncherRootViewController.m`
- `Natives/LauncherMenuViewController.m`

每个改动处均带 `// ★ [ROT-FIX]` 注释；两文件在布置后都会打一行
`NSLog(@"[ROT] %@ size=%.0fx%.0f barW=%.0f", ...)` 便于装机核对。

**本机为 Windows、无 Xcode：以下改动未编译、未装机验证，只做了静态自检（见 §6）。**

---

## 1. 旋转 / 布局更新路径（改前：谁在监听转屏、各做了什么）

### 1.1 `LauncherRootViewController.m`
| 时机 | 方法（改前行号） | 改前做了什么 |
|---|---|---|
| 转屏 | `viewWillTransitionToSize:` | **不存在**（该文件没有实现它） |
| trait 变化（含 iPhone/iPad、分屏、部分转屏） | `traitCollectionDidChange:`（214–231） | 写 `sidebarWidthConstraint.constant` 与 `rightPanelWidthConstraint.constant`；对子 VC `setNeedsLayout` |
| 安全区变化（转屏时灵动岛换边/Home 指示条进出） | `viewSafeAreaInsetsDidChange`（由并发 `[PORTRAIT-FIX]` 新增） | 重选竖/横形态 + 重算安全区补偿 |
| 每次布局后 | `viewDidLayoutSubviews`（241） | 只清 `contentVC` 的 `additionalSafeAreaInsets`（+ 由 `[PORTRAIT-FIX]` 新增的 `applyRootLayoutForCurrentOrientation`） |

> 结论：**RootVC 从不显式重算顶栏宽度**，也没有 `viewWillTransitionToSize:`。

### 1.2 `LauncherMenuViewController.m`
| 时机 | 方法（改前行号） | 改前做了什么 |
|---|---|---|
| 转屏 | `viewWillTransitionToSize:` | **不存在** |
| 每次布局后 | `viewDidLayoutSubviews`（277） | 重绘 `brandLogoGradient` 的 frame；按 `compactLayout` **只重申 `menuStackView.axis`** |
| trait 变化 | `traitCollectionDidChange:`（772） | **只刷按钮颜色**（深浅色），不重算尺寸/约束 |
| 排布重放 | `applyE2LayoutForCompact:`（124） | 只在 `viewDidLoad`（274，强制 `YES`）与 `setupSidebar`（375）里各跑一次 —— **转屏后不再被调用** |

> 结论：菜单的 `hug` / 按钮尺寸 / `trailing` 约束状态**只在启动时断言过一次**，转屏不重放。

---

## 2. 低层根因（文件:行 证据）

### 根因 1（主因）：横屏顶栏宽度**欠定**，且转屏后无人重算 → 被 `masksToBounds` 裁掉
在「顶部横条」形态下，横屏顶栏的宽度**没有任何显式约束**，形成一条自指链：

- `LauncherMenuViewController.m:146`
  `self.ameHugWidthConstraint = [self.view.widthAnchor constraintEqualToAnchor:self.menuStackView.widthAnchor]`
  （菜单视图宽 = 栈宽），而菜单视图又被 RootVC 钉死在 `sidebarContainer` 四边 →
  等价于「容器宽 = 栈宽」；
- 但栈宽只由 **750 优先级**的按钮宽度决定：
  `LauncherMenuViewController.m:209` `c.constant = compact ? (sizeIdx == 0 ? 56.0 : 44.0) : c.constant;`
  配合 `LauncherMenuViewController.m:138` `UIStackViewDistributionFillEqually`；
- RootVC 侧横屏对顶栏只有一条**上限**约束：
  `LauncherRootViewController.m:393` `ameTopBarTrail = … constraintLessThanOrEqualToAnchor:self.rightPanelContainer.leadingAnchor`
  且原先的定宽约束被关掉：
  `LauncherRootViewController.m:389` `self.sidebarWidthConstraint.active = NO;`

⇒ 横屏顶栏宽度 = 「hug（自指）+ 750 按钮宽 + `≤` 上限」的解，**没有 required 约束把它钉死**。
转屏时没有任何代码为它重算/给定宽度，solver 在新 bounds 下会落到偏小的解；而顶栏容器
`LauncherRootViewController.m:362` `self.sidebarContainer.layer.masksToBounds = YES;`
会把超出的那部分**直接裁掉** → 用户看到的「工具条只剩下半截」。

### 根因 2：尺寸常数被写到一条**已关闭**的约束上（“尺寸约束常数未真正重算”）
改前 `LauncherRootViewController.m`（214–221）：
```objc
CGFloat sidebarWidth = LauncherRootLayoutSidebarWidth(self.traitCollection);
if (self.sidebarWidthConstraint.constant != sidebarWidth) {
    self.sidebarWidthConstraint.constant = sidebarWidth;   // ← 该约束已在 setupContainers active=NO
}
```
该约束在 `:389` 已被 `active = NO`，改它的 `constant` **等于没改** —— 唯一的“按尺寸重算”路径是死代码。

### 根因 3：顶栏形态在转屏时**不被重申**（“约束未重建/未激活”）
`applyE2LayoutForCompact:`（含 `hug` 与按钮尺寸的完整断言）只在启动跑一次；
`viewDidLayoutSubviews` 里只重申了 `axis`。若任一路径把菜单 `compactLayout` 置成 `NO`
（历史提交里 `LauncherCardLayoutViewController` 横屏曾传 `NO`），56pt 的顶栏里塞进**竖排**菜单
就只会露出约一个按钮 —— 同样表现为「只剩下半截」。

> 说明：根因 1 是结构上最确定的一条（宽度欠定 + 无重算 + 裁剪）；根因 3 是同症状的另一条可能路径。
> 两者都已按下面 §3 一并修掉。

---

## 3. 改法（锚点唯一 + replace 后校验 count==1）

所有改动均通过脚本以「**唯一锚点**」定位后 replace，并对每处校验
`anchor count == 1`、`len(out) == len(in) - len(old) + len(new)`、`new count == 1`；
脚本输出 12/12 全部 `ok`。文件行尾（CRLF）原样保留。

### 3.1 `LauncherRootViewController.m`
1. **新增显式顶栏宽度约束**（只加入【横屏】约束集，优先级 999）
   - 属性：`:87` `ameTopBarWidthConstraint`
   - 创建：`:395–399`
     ```objc
     self.ameTopBarWidthConstraint = [self.sidebarContainer.widthAnchor constraintEqualToConstant:kAmeTopBarFallbackWidth];
     self.ameTopBarWidthConstraint.priority = UILayoutPriorityRequired - 1;   // 999 < ≤ 的 required
     ```
   - 入集：`:412` 加进 `ameLandscapeConstraints`
   - 兜底常量：`:35` `kAmeTopBarFallbackWidth = 376.0`（6×56 + 5×8）
   > 优先级 999 而非 1000：极窄屏时让 `≤ (`rightPanel.leading`)` 的 required 上限赢，
   > 不会出现 `Unable to simultaneously satisfy constraints`。
2. **新增宽度重算辅助 + 转屏入口**（`:306` `#pragma mark - ★ [ROT-FIX] …`）
   - `ameTopBarContentWidth`（向菜单要 `preferredTopBarWidth`，拿不到用兜底 376）
   - `ameClampedTopBarWidthForSize:`（夹到 `屏宽 - 右栏宽`，不压右上角头像）
   - `ameRefreshTopBarWidthForSize:`（值真变才写回，避免反复触发布局）
   - `viewWillTransitionToSize:withTransitionCoordinator:`（按**目标 size** 重算宽度 → 让菜单重放紧凑横排 → `setNeedsLayout` → 打 `[ROT]` 日志）
     > 注意：**不**在此主动 `activate` 某一套约束集 —— 竖/横互斥由 `[PORTRAIT-FIX]` 的
     > `applyRootLayoutForCurrentOrientation` 统一管理，再激活一套会与它打架。
3. **`viewDidLayoutSubviews` 每次布局后重算宽度 + `[ROT]` 自证**：`:263–273`
4. **`traitCollectionDidChange:` 改为重算显式宽度**（不再写死约束）：`:239–242`
5. **分类声明**（免改头文件）：`:67–71` `@interface LauncherMenuViewController (RotFixWidth)`

### 3.2 `LauncherMenuViewController.m`
1. **`preferredTopBarWidth`**（把“内容宽”告诉 RootVC）：`:230–236`
   `visible 按钮数 × 56 + (visible-1) × 8`（占位/hidden 项不计）
2. **`viewWillTransitionToSize:` 重放紧凑排布**：`:241–244`
3. **`viewDidLayoutSubviews` 顶栏形态自愈 + `[ROT]` 自证**：`:303–325`
   - 容器高 < 80pt（顶栏形态）时，若 `compactLayout == NO` 则强制纠正回横排并重放尺寸；
   - 轴向后断言加 `|| ameTopBarForm` 兜底。

---

## 4. 风险

- **与并发改动冲突（最大风险）**：本任务执行期间，另一个子代理（`[PORTRAIT-FIX]`：竖屏形态）
  已在改写同一个 `LauncherRootViewController.m`（新增竖/横两套约束集）。本次所有锚点都是
  按**改写后的当前内容**重新取样的；若对方之后再次整体写入该文件且基于更早快照，可能覆盖本次 `[ROT-FIX]`。
- **重复方法定义**：RootVC 现在新增了 `viewWillTransitionToSize:withTransitionCoordinator:`；
  若对方随后也新增同名方法 → 编译期 **duplicate method** 错误。合并时需检查。
- **竖屏不受影响**：`ameTopBarWidthConstraint` 只在【横屏】集里激活；竖屏顶栏是全宽
  （`[PORTRAIT-FIX]` 的 `amePortraitTopBarTrailing` 钉到 `view.trailing`）。
- **横屏可用宽**：`可用宽 = 屏宽 - 右栏宽`。iPhone 横屏 ≈852-168=684 > 376，正常取 376；
  极小屏/分屏时会被夹小（按钮由 FillEqually 压缩），这是既有设计，不是裁剪。
- **与 Card 布局共存**：`LauncherCardLayoutViewController` 也会调 `setCompactHorizontalLayout:YES`；
  本次未改它（任务只允许改这 2 个文件）。其横屏路径若传 `NO`，则靠 MenuVC 的“顶栏自愈”兜底。

---

## 5. 未验证项（如实标注）

- **未编译、未装机**：本机 Windows 无 Xcode；无 iOS 模拟器。仅静态自检。
- 未实测 `[ROT]` 日志的真实输出与 `barW` 数值，也未用 `log stream` 核对。
- 「旋转后只剩半截」的 100% 归因未做实机确认：根因 1 是结构上最确定的解释，
  但根因 2/3 是同症状的其它路径；三者均已修，但无法在无运行环境下区分主次。
- 未验证 `preferredTopBarWidth` 的 376 与真实布局在**大字号/动态字体**下是否仍为 56×6+8×5
  （按钮尺寸约束是固定值，理论上不受动态字体影响）。
- 未验证横屏 `safeAreaInsets.left/right`（刘海机）下顶栏贴 `view.leading`（x=0）的观感 ——
  本次未改动顶栏的水平贴边策略（仅改宽度），若要避让刘海属另一议题。

---

## 6. 静态自检结果（脚本 `rotfix_check.py`）

| 项 | RootVC | MenuVC |
|---|---|---|
| `{}` 配平（去注释/字符串后） | 114 vs 114 OK | 98 vs 98 OK |
| `()` 配平 | 250 vs 250 OK | 201 vs 201 OK |
| `[]` 配平 | 337 vs 337 OK | 255 vs 255 OK |
| `@implementation` / 方法唯一 | 1 / 各 1 | 1 / 各 1 |
| `@interface` + `@end` 配平 | 2 + 3 OK | 1 + 2 OK |
| `viewWillTransitionToSize:` 定义 | 1 | 1 |
| `[ROT]` 日志行 | 2 | 1 |
| `★ [ROT-FIX]` 标记 | 11 | 5 |
| 死写 `sidebarWidthConstraint.constant =` | 已移除 | — |
| 换行风格 | CRLF 保留 | CRLF 保留 |

- 编辑脚本：`rotfix_apply2.py`（12/12 处 `ok`，每处 `anchor count==1` + `new count==1` + 长度校验）。
- 自检脚本：`rotfix_check.py`。

---

## 7. 备份（改前）

- `D:\CTF\_uibuild\_bak_\LauncherRootViewController.m.preROT.bak`（本次改动**前**的当前内容）
- `D:\CTF\_uibuild\_bak_\LauncherMenuViewController.m.preROT.bak`
- 另有更早快照：`…_bak_\LauncherRootViewController.m.bak`、`…_bak_\LauncherMenuViewController.m.bak`
  （注：`_bak_` 目录同时被并发代理使用，已避免覆盖他人文件）

---

## 8. 装机核对方法（供下一环节）

```
log stream --predicate 'eventMessage CONTAINS "[ROT]"'
```
旋转屏幕后应看到每次转屏各一行 `[ROT] LANDSCAPE size=852x393 barW=376` 之类；
`barW` 在横屏应为 `min(内容宽, 屏宽-右栏宽)`，且**不会**在转屏后比转屏前变小。
