#import "LauncherCardLayoutViewController.h"
#import "LauncherMenuViewController.h"
#import "UIViewController+AMEPanel.h"   // ★ 子面板原生基底样式(移植)
#import "LauncherNewsViewController.h"
#import "LauncherRightPanelViewController.h"
#import "DownloadViewController.h"
#import "VersionManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "BackgroundManager.h"
#import "PLProfiles.h"
#import "utils.h"
#import "ModsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "ModpackImportViewController.h"
#import "LauncherPrefGameDirViewController.h"
#import "CustomControlsViewController.h"
// ZeroTier/Terracotta 联机暂时移除（排查启动崩溃）
// #import "MultiplayerViewController.h"
// #import "TerracottaViewController.h"
// #import "TerracottaManager.h"
// #import "TerracottaBridge.h"
#import "AccountListViewController.h"
#import "AI/AIViewController.h"
#import "AI/AiSessionStore.h"

// 布局常量（iPad/宽屏基准值；iPhone 上通过 traitCollection 适配后会变窄）
static const CGFloat kSidebarWidthPad = 70.0;      // iPad 左侧边栏卡片宽度
static const CGFloat kSidebarWidthPhone = 56.0;    // iPhone 左侧边栏卡片宽度（仅图标）
static const CGFloat kRightPanelWidthPad = 220.0;  // iPad 右侧面板卡片宽度
static const CGFloat kRightPanelWidthPhone = 168.0; // iPhone 右侧面板卡片宽度（保证启动/JAR 按钮可读）
static const CGFloat kCardSpacing = 12.0;          // 卡片间距
static const CGFloat kCardOuterMarginPad = 12.0;   // iPad 卡片到外边缘的间距
static const CGFloat kCardOuterMarginPhone = 8.0;  // iPhone 卡片到外边缘的间距（窄屏减小留白）
static const CGFloat kCardCornerRadius = 16.0;     // 卡片圆角

// ★ [UI-A][PORTRAIT-FIX] 竖屏底部菜单条高度:菜单按钮 50pt + stack 上下内边距 8+8 = 66pt,
//   取 72 留 6pt 余量,避免按钮被 sidebarCard 的圆角 + masksToBounds 裁掉 1~2pt。
static const CGFloat kPortraitMenuBarHeight = 72.0;

/// 检测物理设备是否为 iPhone（不受 debug.debug_ipad_ui 的 idiom hook 影响）。
/// UIKit+hook.m 会把 idiom 强制改成 Pad，导致 trait.userInterfaceIdiom 不可靠。
/// 这里用 UIDevice.model 检测真实设备类型。
static BOOL LauncherCardLayoutIsPhysicalPhone(void) {
    NSString *model = [[UIDevice currentDevice].model lowercaseString];
    return [model containsString:@"iphone"];
}

/// 根据物理设备类型决定卡片外边距
static CGFloat LauncherCardLayoutOuterMargin(UITraitCollection *trait) {
    if (LauncherCardLayoutIsPhysicalPhone()) return kCardOuterMarginPhone;
    return kCardOuterMarginPad;
}

/// 根据物理设备类型决定侧栏宽度
/// - iPhone 横屏（含 SE/8/Plus/X/Pro Max）：56pt（菜单只有图标，56pt 足够）
/// - iPad：70pt
static CGFloat LauncherCardLayoutSidebarWidth(UITraitCollection *trait) {
    if (LauncherCardLayoutIsPhysicalPhone()) return kSidebarWidthPhone;
    return kSidebarWidthPad;
}

/// 根据物理设备类型决定右侧面板宽度
/// - iPhone 横屏：168pt（保证启动/编辑控件/执行 Jar 按钮文字不截断）
/// - iPad：220pt
static CGFloat LauncherCardLayoutRightPanelWidth(UITraitCollection *trait) {
    if (LauncherCardLayoutIsPhysicalPhone()) return kRightPanelWidthPhone;
    return kRightPanelWidthPad;
}

@interface LauncherCardLayoutViewController ()

@property(nonatomic, strong) UIView *sidebarCard;
@property(nonatomic, strong) UIView *contentCard;
@property(nonatomic, strong) UIView *rightPanelCard;

@property(nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property(nonatomic, strong) NSLayoutConstraint *rightPanelWidthConstraint;
// 存储外边距约束，traitCollection 变化时动态更新
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *outerMarginConstraints;
// ★ [GLASS-SAFE] 贴屏边的那 4 个约束单独持有:只有"有灵动岛/刘海的那一侧"需要补 safeArea 补偿。
//   其余(卡片之间的间距、宽度)不受安全区影响,保持原样。
@property(nonatomic, strong) NSLayoutConstraint *edgeLeadingConstraint;    // 侧栏 leading → +insets.left
@property(nonatomic, strong) NSLayoutConstraint *edgeTrailingConstraint;   // 右栏 trailing → -insets.right
@property(nonatomic, strong) NSLayoutConstraint *edgeTopConstraint;        // → +insets.top(竖屏时避岛)
@property(nonatomic, strong) NSLayoutConstraint *edgeBottomConstraint;     // → -max(margin, insets.bottom)
// 关键修复（UI 累积异常）：同 LauncherRootViewController，持有当前内容 VC 的约束
// 并先 deactivate 再激活，避免 tmpRootVC 保留场景下缓存复用子 VC 的约束叠加。
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *currentContentConstraints;

// ★ [PORTRAIT] 竖屏(紧凑高)时的"三卡竖摞"约束集;与横屏约束互斥激活。
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *portraitConstraints;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *landscapeConstraints;
@property(nonatomic, assign) BOOL usingPortraitLayout;

// ★ [PORTRAIT] 菜单页引用(切横/竖排布时要用)
@property(nonatomic, strong) LauncherMenuViewController *menuViewController;

@property(nonatomic, assign) BOOL isShowingProfileEditor;
@property(nonatomic, strong) ProfileSettingsViewController *profileEditorVC;

// ★ [UI-A][PORTRAIT-FIX] 中栏夹在左/右两卡之间那两条横向相邻约束(横屏专用)。
//   原实现只在 setupCardContainers 里 activate 了它们、却没存进 landscapeConstraints,
//   导致切竖屏时它们仍 active:中栏同时被"贴着菜单卡右边"和"贴 view.leading"两条约束拉扯
//   ⇒ 竖屏三卡错位 / 自动布局打断约束(竖屏 bug 根因)。
@property(nonatomic, strong) NSLayoutConstraint *contentBetweenLeadConstraint;
@property(nonatomic, strong) NSLayoutConstraint *contentBetweenTrailConstraint;

// ★ [UI-A][DARK-MODE] 深浅色切换时重刷卡片基底(实现在下方)
- (void)applyAppearanceForCurrentInterfaceStyle;

@end

@implementation LauncherCardLayoutViewController

#pragma mark - Lifecycle

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    
    // 初始化版本列表（必须在其他视图控制器之前）
    [self initializeVersionLists];
    
    // 创建三个卡片容器视图
    [self setupCardContainers];
    
    // 添加子视图控制器
    [self setupChildViewControllers];
    
    // 应用背景
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];

    // 监听启动器外观变化（自定义字体/卡片颜色），刷新卡片背景
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyCustomAppearance)
                                                 name:@"LauncherAppearanceChanged"
                                               object:nil];
}

- (void)initializeVersionLists {
    // 初始化本地版本列表
    if (!localVersionList) {
        localVersionList = [NSMutableArray new];
    }
    [localVersionList removeAllObjects];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/", getenv("POJAV_GAME_DIR")];
    NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:nil];
    for (NSString *versionId in list) {
        NSString *localPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionId];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:localPath isDirectory:&isDirectory] && isDirectory) {
            [localVersionList addObject:@{
                @"id": versionId,
                @"type": @"custom"
            }];
        }
    }
    
    // 初始化远程版本列表
    if (!remoteVersionList) {
        remoteVersionList = [NSMutableArray new];
    }
    [remoteVersionList removeAllObjects];
    [remoteVersionList addObjectsFromArray:@[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"}
    ]];
    
    // 异步获取远程版本列表
    [self fetchRemoteVersionList];
}

- (void)fetchRemoteVersionList {
    NSString *downloadSource = getPrefObject(@"general.download_source");
    NSString *versionManifestURL;
    
    if ([downloadSource isEqualToString:@"bmclapi"]) {
        versionManifestURL = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";
    } else {
        versionManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
    }
    
    NSURL *url = [NSURL URLWithString:versionManifestURL];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (json && json[@"versions"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [remoteVersionList addObjectsFromArray:json[@"versions"]];
                    setPrefObject(@"internal.latest_version", json[@"latest"]);
                    NSDebugLog(@"[LauncherCardVC] Loaded %d remote versions", remoteVersionList.count);
                });
            }
        } else {
            NSDebugLog(@"[LauncherCardVC] Failed to fetch version list: %@", error.localizedDescription);
        }
    }];
    [task resume];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[BackgroundManager sharedManager] resumeVideo];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[BackgroundManager sharedManager] pauseVideo];
}

/// ★ [GLASS-SAFE] 转屏(岛换边)或竖屏进出时,safeAreaInsets 变化 ⇒ 重算屏边补偿。
/// 这是灵动岛/刘海屏唯一可靠的重排时机:viewDidLayoutSubviews 里 insets 可能还没更新。
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateLayoutForCurrentOrientation];
    [self applyEdgeInsets];
}

/// ★ [PORTRAIT] 按当前方向二选一激活约束集。竖屏 = 紧凑高(verticalSizeClass == Regular 且宽 < 高)。
/// 只在真正需要切换时动约束,避免每次转屏都重建(原工程有"约束累积"的历史教训)。
- (void)updateLayoutForCurrentOrientation {
    if (!self.portraitConstraints || !self.landscapeConstraints) return;
    BOOL portrait = (self.view.bounds.size.height > self.view.bounds.size.width);
    if (self.usingPortraitLayout == portrait) return;
    self.usingPortraitLayout = portrait;
    // ★ [UI-A] 自证日志:切到哪套布局 + 当前尺寸与安全区,便于装机核对竖/横屏是否真的切了。
    NSLog(@"[UI-A][ORIENT] layout=%@ size=%.0fx%.0f safe(top=%.0f bottom=%.0f left=%.0f right=%.0f)",
          portrait ? @"PORTRAIT" : @"LANDSCAPE",
          self.view.bounds.size.width, self.view.bounds.size.height,
          self.view.safeAreaInsets.top, self.view.safeAreaInsets.bottom,
          self.view.safeAreaInsets.left, self.view.safeAreaInsets.right);
    if (portrait) {
        [NSLayoutConstraint deactivateConstraints:self.landscapeConstraints];
        [NSLayoutConstraint activateConstraints:self.portraitConstraints];
        if (self.sidebarWidthConstraint) { self.sidebarWidthConstraint.active = NO; }
        if (self.rightPanelWidthConstraint) { self.rightPanelWidthConstraint.active = NO; }
    } else {
        [NSLayoutConstraint deactivateConstraints:self.portraitConstraints];
        [NSLayoutConstraint activateConstraints:self.landscapeConstraints];
        if (self.sidebarWidthConstraint) { self.sidebarWidthConstraint.active = YES; }
        if (self.rightPanelWidthConstraint) { self.rightPanelWidthConstraint.active = YES; }
    }
    // 菜单卡在竖屏走横向排布(图标横排一行),横屏恢复竖排
    if ([self.menuViewController respondsToSelector:@selector(setCompactHorizontalLayout:)]) {
        [self.menuViewController performSelector:@selector(setCompactHorizontalLayout:) withObject:@(portrait)];
    }
    [self applyEdgeInsets];
    [self.view setNeedsLayout];
}

/// 只做"屏边补偿"这一件事,便于从 traitCollectionDidChange / viewSafeAreaInsetsDidChange 两处调用。
- (void)applyEdgeInsets {
    CGFloat outerMargin = LauncherCardLayoutOuterMargin(self.traitCollection);
    UIEdgeInsets safe = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safe = self.view.safeAreaInsets;
    }
    CGFloat mTop, mBottom;
    if (self.usingPortraitLayout) {
        // ★ [UI-A][PORTRAIT-SAFE] 竖屏:岛在顶部 ⇒ 顶吃 safe.top(内容区整体下移,不进岛);
        //   底部菜单卡吃 safe.bottom(避开 home indicator)。竖屏 safe.left/right 恒为 0。
        mTop    = outerMargin + safe.top;
        mBottom = outerMargin + safe.bottom;
    } else {
        // ★ [UI-A][LANDSCAPE-FIX] 横屏:底边只让开 home indicator 本体,不再额外叠 outerMargin*0.5,
        //   否则底边(≈29pt)比顶边(≈8pt)宽 3.6 倍,三张卡整体偏上、下空隙过大。
        mTop    = outerMargin + safe.top;
        mBottom = MAX(outerMargin, safe.bottom);
    }
    self.edgeLeadingConstraint.constant  =  outerMargin + safe.left;
    self.edgeTrailingConstraint.constant = -(outerMargin + safe.right);
    self.edgeTopConstraint.constant      =  mTop;
    self.edgeBottomConstraint.constant   = -mBottom;
    for (NSLayoutConstraint *c in self.outerMarginConstraints) {
        if ([c.identifier isEqualToString:@"edge-top"])         { c.constant =  mTop; }
        else if ([c.identifier isEqualToString:@"edge-bottom"]) { c.constant = -mBottom; }
    }
    // ★ [UI-A][PORTRAIT-SAFE] 竖屏专用两条:顶部内容卡吃灵动岛安全区、底部菜单卡吃 home indicator。
    //   横屏用不到这两条(portraitConstraints 未激活),统一复位,避免常量残留。
    for (NSLayoutConstraint *c in self.portraitConstraints) {
        if ([c.identifier isEqualToString:@"portrait-top"]) {
            c.constant = self.usingPortraitLayout ? (kCardOuterMarginPhone + safe.top) : kCardOuterMarginPhone;
        } else if ([c.identifier isEqualToString:@"portrait-bottom"]) {
            c.constant = self.usingPortraitLayout ? -(kCardOuterMarginPhone + safe.bottom) : -kCardOuterMarginPhone;
        }
    }
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // ★ [PORTRAIT] 首次进入 / 转屏后对齐布局(只切一次,内部有 usingPortraitLayout 去重)
    [self updateLayoutForCurrentOrientation];
    // card 布局四边外边距一致性由约束保证（用 view.edgeAnchor + kCardOuterMargin，
    // 不依赖 safeAreaLayoutGuide），此处无需额外补偿。
    // 之前用 additionalSafeAreaInsets 补偿 safeArea 不对称，但补偿后外边距 =
    // max(safeArea) + kCardOuterMargin 反而更大（"下边和左右两边空隙过大"），
    // 故移除该补偿方案，改用 view.edgeAnchor 直接约束。
    //
    // 关键修复（阶段4：Card 布局进入设置崩溃，无日志）：
    // 与 LauncherRootViewController 对齐：清理 additionalSafeAreaInsets 累积。
    // 之前此方法体为空，导致 LauncherPreferencesViewController（含 UISearchController）在
    // nav 栈中时 additionalSafeAreaInsets 可能累积异常，UISearchController.searchBar
    // （作为 tableHeaderView）frame 计算异常 → EXC_BAD_ACCESS（不被 NSUncaughtExceptionHandler
    // 捕获，故无日志）。VS 布局不崩溃是因为 Root 的 viewDidLayoutSubviews 持续清理 inset。
    UIViewController *contentVC = _contentViewController;
    if (!contentVC) return;
    if ([contentVC isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)contentVC;
        for (UIViewController *vc in nav.viewControllers) {
            UIEdgeInsets insets = vc.additionalSafeAreaInsets;
            if (insets.top != 0 || insets.left != 0 || insets.right != 0 || insets.bottom != 0) {
                vc.additionalSafeAreaInsets = UIEdgeInsetsZero;
            }
        }
    } else {
        UIEdgeInsets insets = contentVC.additionalSafeAreaInsets;
        if (insets.top != 0 || insets.left != 0 || insets.right != 0 || insets.bottom != 0) {
            contentVC.additionalSafeAreaInsets = UIEdgeInsetsZero;
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // iPhone 与 iPad 切换、或分屏调整大小时，更新侧栏与右侧面板宽度
    CGFloat sidebarWidth = LauncherCardLayoutSidebarWidth(self.traitCollection);
    CGFloat rightPanelWidth = LauncherCardLayoutRightPanelWidth(self.traitCollection);
    if (self.sidebarWidthConstraint.constant != sidebarWidth) {
        self.sidebarWidthConstraint.constant = sidebarWidth;
    }
    if (self.rightPanelWidthConstraint.constant != rightPanelWidth) {
        self.rightPanelWidthConstraint.constant = rightPanelWidth;
    }
    // 更新外边距约束（iPhone/iPad 切换时 outerMargin 不同）
    CGFloat outerMargin = LauncherCardLayoutOuterMargin(self.traitCollection);
    for (NSLayoutConstraint *c in self.outerMarginConstraints) {
        if ([c.identifier isEqualToString:@"edge-top"] || [c.identifier isEqualToString:@"edge-bottom"]) {
            continue;   // ★ [GLASS-SAFE]/[UI-A] 带 edge-top/bottom 标识的几条由 applyEdgeInsets 统一按安全区设置
        }
        // 其余(卡片之间 / 尺寸)不受屏边安全区影响,按符号取 ±outerMargin
        if (c.constant >= 0) {
            c.constant = outerMargin;
        } else {
            c.constant = -outerMargin;
        }
    }
    // ★ [UI-A][GLASS-SAFE] 屏边补偿统一走 applyEdgeInsets,避免两处公式漂移:
    //   岛在左/右时该侧让开 safe.left/right;竖屏时顶部内容卡让开岛、底部菜单卡让开 home indicator。
    [self applyEdgeInsets];
    // 关键修复（阶段4：Card 布局进入设置崩溃，无日志）：
    // 与 LauncherRootViewController 对齐：仅遍历直接子 VC，避免递归栈溢出风险。
    // 之前递归遍历所有后代 VC（adjustChildLayoutForTraitCollection:），若 VC 树存在
    // 循环引用会栈溢出（SIGSEGV，不被 NSUncaughtExceptionHandler 捕获，故无日志）。
    // respondsToSelector:@selector(viewWillAppear:) 检查永真（所有 UIViewController 都响应），
    // 属冗余代码，一并删除。
    // ★ [UI-A][DARK-MODE] 深浅色切换:重刷卡片基底(毛玻璃/自定义叠色);布局不变、颜色要对。
    if (previousTraitCollection &&
        previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        [self applyAppearanceForCurrentInterfaceStyle];
    }
    for (UIViewController *child in self.childViewControllers) {
        [child.view setNeedsLayout];
    }
}

#pragma mark - Setup

- (UIView *)createCardContainer {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = kCardCornerRadius;
    card.layer.masksToBounds = YES;
    [[BackgroundManager sharedManager] applyEffectToView:card];
    [self applyCustomCardColorToCard:card];
    return card;
}

/// 读取 general.card_color 偏好，若已设置则在毛玻璃上叠加半透明色。
///
/// 统一参照 ZL2 的 Haze + tint 方案和 RootVC 的 applySemiTransparentColor: 实现：
/// 保留 BackgroundManager 的毛玻璃 UIVisualEffectView（让背景图能透出），
/// 在容器背景色上叠加用户自定义的半透明颜色。
///
/// 之前 CardVC 的做法是移除毛玻璃用纯色覆盖，导致：
/// 1. 与 RootVC 行为不一致（RootVC 保留毛玻璃叠加半透明色）
/// 2. 自定义背景图被完全遮挡，无法透出
/// 3. 视觉效果与 FCL/ZL2 不符（FCL/ZL2 都保留模糊效果 + 颜色叠加）
///
/// 现统一为：保留毛玻璃 + 叠加半透明色（与 RootVC 完全一致）
- (void)applyCustomCardColorToCard:(UIView *)card {
    NSString *hex = getPrefObject(@"general.card_color");
    UIColor *color = [self colorFromHexString:hex];
    if (!color) return;
    // 保留 BackgroundManager 插入的毛玻璃 UIVisualEffectView，仅叠加半透明色
    // 这样既显示用户自定义的卡片颜色，又能透出背景图（与 RootVC 行为一致）
    // 使用 0.7 alpha 让背景图能适度透出（参照 ZL2 的 influencedByBackgroundColor 思路）
    // ★ [UI-A][DARK-MODE] 深色外观下同样的自定义色若仍叠 0.7 会偏亮发灰,
    //   降到 0.5 让深色毛玻璃基底多透出一些,保证深浅两套观感一致。
    CGFloat alpha = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? 0.5 : 0.7;
    card.backgroundColor = [color colorWithAlphaComponent:alpha];
}

- (nullable UIColor *)colorFromHexString:(id)hex {
    if (![hex isKindOfClass:[NSString class]] || [(NSString *)hex length] == 0) return nil;
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

/// 外观变化时重新应用卡片颜色（保留圆角，重建背景）
- (void)applyCustomAppearance {
    [self applyCustomCardColorToCard:self.sidebarCard];
    [self applyCustomCardColorToCard:self.contentCard];
    [self applyCustomCardColorToCard:self.rightPanelCard];
}

/// ★ [UI-A][DARK-MODE] 深浅色切换时重刷三张卡的基底:
/// 重新应用毛玻璃/半透明效果 + 按新外观重刷自定义卡片叠色(applyCustomCardColorToCard 内按 style 取 alpha)。
/// 布局本身不随深浅色变化,变化的只有卡片基底色与毛玻璃亮度。
- (void)applyAppearanceForCurrentInterfaceStyle {
    for (UIView *card in @[self.sidebarCard, self.contentCard, self.rightPanelCard]) {
        if (!card) continue;
        [[BackgroundManager sharedManager] applyEffectToView:card];
        [self applyCustomCardColorToCard:card];
    }
    [self.view setNeedsLayout];
}

- (void)setupCardContainers {
    // 左侧菜单卡片
    self.sidebarCard = [self createCardContainer];
    [self.view addSubview:self.sidebarCard];

    // 中间内容卡片
    self.contentCard = [self createCardContainer];
    [self.view addSubview:self.contentCard];

    // 右侧信息/启动卡片
    self.rightPanelCard = [self createCardContainer];
    [self.view addSubview:self.rightPanelCard];

    // 用自适应宽度创建可变宽度约束，便于 traitCollection 变化时更新
    self.sidebarWidthConstraint = [self.sidebarCard.widthAnchor constraintEqualToConstant:LauncherCardLayoutSidebarWidth(self.traitCollection)];
    self.rightPanelWidthConstraint = [self.rightPanelCard.widthAnchor constraintEqualToConstant:LauncherCardLayoutRightPanelWidth(self.traitCollection)];

    // 卡片外边距：iPhone 窄屏用较小值减少留白
    CGFloat outerMargin = LauncherCardLayoutOuterMargin(self.traitCollection);

    // 设置约束
    // 四个方向均用 view.edgeAnchor（而非 safeAreaLayoutGuide），使外边距完全由 outerMargin 控制，
    // 上下左右边距一致（均 = outerMargin），不受刘海/home indicator 导致的 safeArea 不对称影响。
    //
    // 修复"下面过宽"问题：之前上下用 safeAreaLayoutGuide + outerMargin，
    // 导致底部边距 = homeIndicatorInset + outerMargin（约 21+8=29pt），
    // 而顶部边距 = 0 + outerMargin = 8pt，底部比顶部宽 3.6 倍。
    // 改为 view.topAnchor/view.bottomAnchor 后，上下边距均 = outerMargin，保持一致。
    // 卡片背景会延伸到 home indicator 下方，视觉上无影响（卡片有不透明/毛玻璃背景）。
    NSLayoutConstraint *sidebarLeading = [self.sidebarCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:outerMargin];
    NSLayoutConstraint *sidebarTop = [self.sidebarCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:outerMargin];
    NSLayoutConstraint *sidebarBottom = [self.sidebarCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-outerMargin];
    NSLayoutConstraint *rightTrailing = [self.rightPanelCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-outerMargin];
    NSLayoutConstraint *rightTop = [self.rightPanelCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:outerMargin];
    NSLayoutConstraint *rightBottom = [self.rightPanelCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-outerMargin];
    NSLayoutConstraint *contentTop = [self.contentCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:outerMargin];
    NSLayoutConstraint *contentBottom = [self.contentCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-outerMargin];

    self.outerMarginConstraints = @[sidebarLeading, sidebarTop, sidebarBottom,
                                    rightTrailing, rightTop, rightBottom,
                                    contentTop, contentBottom];

    // ★ [GLASS-SAFE] 记下"贴屏边"的 4 个,供安全区补偿使用(sidebarTop/Top 同值,取其一即可)
    self.edgeLeadingConstraint  = sidebarLeading;
    self.edgeTrailingConstraint = rightTrailing;
    self.edgeTopConstraint      = sidebarTop;
    self.edgeBottomConstraint   = sidebarBottom;
    // contentCard 的上下与侧栏一致,同步补偿(否则中栏会被岛侧顶出去而错位)
    contentTop.identifier    = @"edge-top";
    contentBottom.identifier = @"edge-bottom";
    sidebarTop.identifier    = @"edge-top";
    sidebarBottom.identifier = @"edge-bottom";
    // ★ [UI-A][LANDSCAPE-FIX] 右栏上下也必须吃同一套屏边补偿:原实现漏了这两条 ⇒ 横屏下右栏卡片
    //   比左/中栏多伸出约 17pt(底边不齐)、整体错位。补上 identifier 后 applyEdgeInsets 的循环
    //   会把右栏和左/中栏一起对齐(此前只有 sidebar/content 带 identifier)。
    rightTop.identifier    = @"edge-top";
    rightBottom.identifier = @"edge-bottom";

    // ★ [PORTRAIT] 记下横屏那一套(供切换用)
    self.landscapeConstraints = @[sidebarLeading, sidebarTop, sidebarBottom,
                                  rightTrailing, rightTop, rightBottom,
                                  contentTop, contentBottom];

    // ★ [UI-A][PORTRAIT-FIX] 中栏与左/右两卡的横向相邻约束:必须单独持有,否则切竖屏时无法 deactivate。
    self.contentBetweenLeadConstraint  = [self.contentCard.leadingAnchor  constraintEqualToAnchor:self.sidebarCard.trailingAnchor    constant:kCardSpacing];
    self.contentBetweenTrailConstraint = [self.contentCard.trailingAnchor constraintEqualToAnchor:self.rightPanelCard.leadingAnchor constant:-kCardSpacing];

    [NSLayoutConstraint activateConstraints:@[
        // 左侧菜单卡片
        sidebarLeading, sidebarTop, sidebarBottom,
        self.sidebarWidthConstraint,

        // 右侧面板卡片
        rightTrailing, rightTop, rightBottom,
        self.rightPanelWidthConstraint,

        // 中间内容卡片——填满侧栏与右面板之间的空间，两侧间距均等为 kCardSpacing
        self.contentBetweenLeadConstraint,
        self.contentBetweenTrailConstraint,
        contentTop, contentBottom
    ]];

    // ★ [UI-A][PORTRAIT-FIX] 把中栏左右两条也并入横屏约束集 ⇒ 切竖屏时随 landscapeConstraints 一起
    //   deactivate,消除"中栏同时贴菜单卡右边 + 贴 view.leading"的约束冲突(竖屏三卡错位根因)。
    self.landscapeConstraints = [self.landscapeConstraints arrayByAddingObjectsFromArray:
                                 @[self.contentBetweenLeadConstraint, self.contentBetweenTrailConstraint]];

    // ★ [PORTRAIT] 竖屏折法:三张卡【竖着摞】—— 内容在上、右栏(含启动键)居中、菜单在底。
    //   选择"竖摞"而不是"彻底重排成底部标签栏"的原因:右栏承载【启动游戏/下载进度】等核心操作,
    //   彻底折叠会丢功能;竖摞则三块都在、功能零损失,且天然贴合安全区(岛在顶部时顶部留白)。
    //   与横屏那一套互斥:由 updateLayoutForCurrentOrientation 二选一激活。
    NSLayoutConstraint *pContentTop   = [self.contentCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:kCardOuterMarginPhone];
    // ★ [PORTRAIT-SAFE] 竖屏时岛在顶部 ⇒ 这条 top 约束要在 applyEdgeInsets 里额外加 insets.top
    pContentTop.identifier = @"portrait-top";
    NSLayoutConstraint *pContentLead  = [self.contentCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kCardOuterMarginPhone];
    NSLayoutConstraint *pContentTrail = [self.contentCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kCardOuterMarginPhone];
    NSLayoutConstraint *pRightTop     = [self.rightPanelCard.topAnchor constraintEqualToAnchor:self.contentCard.bottomAnchor constant:kCardSpacing];
    NSLayoutConstraint *pRightLead    = [self.rightPanelCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kCardOuterMarginPhone];
    NSLayoutConstraint *pRightTrail   = [self.rightPanelCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kCardOuterMarginPhone];
    NSLayoutConstraint *pSideLead     = [self.sidebarCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kCardOuterMarginPhone];
    NSLayoutConstraint *pSideTrail    = [self.sidebarCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kCardOuterMarginPhone];
    NSLayoutConstraint *pSideBottom   = [self.sidebarCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-kCardOuterMarginPhone];
    NSLayoutConstraint *pSideTop      = [self.sidebarCard.topAnchor constraintEqualToAnchor:self.rightPanelCard.bottomAnchor constant:kCardSpacing];
    NSLayoutConstraint *pSideHeight   = [self.sidebarCard.heightAnchor constraintEqualToConstant:kPortraitMenuBarHeight];
    for (NSLayoutConstraint *c in @[pContentTop, pContentLead, pContentTrail, pRightTop, pRightLead, pRightTrail,
                                    pSideLead, pSideTrail, pSideBottom, pSideTop, pSideHeight]) {
        c.identifier = @"portrait-set";
    }
    // ★ [UI-A][PORTRAIT-SAFE] 底部菜单卡单独打标,竖屏要避开 home indicator(见 applyEdgeInsets)。
    pSideBottom.identifier = @"portrait-bottom";
    self.portraitConstraints = @[pContentTop, pContentLead, pContentTrail, pRightTop, pRightLead, pRightTrail,
                                 pSideLead, pSideTrail, pSideBottom, pSideTop, pSideHeight];
}

- (void)setupChildViewControllers {
    // 左侧边栏 - 功能菜单
    LauncherMenuViewController *sidebarVC = [[LauncherMenuViewController alloc] init];
    self.menuViewController = sidebarVC;   // ★ [PORTRAIT] 记下引用
    [self addChildViewController:sidebarVC];
    sidebarVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebarCard addSubview:sidebarVC.view];
    [NSLayoutConstraint activateConstraints:@[
        [sidebarVC.view.leadingAnchor constraintEqualToAnchor:self.sidebarCard.leadingAnchor],
        [sidebarVC.view.trailingAnchor constraintEqualToAnchor:self.sidebarCard.trailingAnchor],
        [sidebarVC.view.topAnchor constraintEqualToAnchor:self.sidebarCard.topAnchor],
        [sidebarVC.view.bottomAnchor constraintEqualToAnchor:self.sidebarCard.bottomAnchor]
    ]];
    [sidebarVC didMoveToParentViewController:self];
    _sidebarViewController = sidebarVC;
    
    // 中间内容 - 默认显示新闻页
    LauncherNewsViewController *newsVC = [[LauncherNewsViewController alloc] init];
    [self setContentViewController:newsVC animated:NO];
    
    // 右侧面板 - 账户和启动
    LauncherRightPanelViewController *rightPanelVC = [[LauncherRightPanelViewController alloc] init];
    [self addChildViewController:rightPanelVC];
    rightPanelVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rightPanelCard addSubview:rightPanelVC.view];
    [NSLayoutConstraint activateConstraints:@[
        [rightPanelVC.view.leadingAnchor constraintEqualToAnchor:self.rightPanelCard.leadingAnchor],
        [rightPanelVC.view.trailingAnchor constraintEqualToAnchor:self.rightPanelCard.trailingAnchor],
        [rightPanelVC.view.topAnchor constraintEqualToAnchor:self.rightPanelCard.topAnchor],
        [rightPanelVC.view.bottomAnchor constraintEqualToAnchor:self.rightPanelCard.bottomAnchor]
    ]];
    [rightPanelVC didMoveToParentViewController:self];
    _rightPanelViewController = rightPanelVC;
    
    // 注册通知监听
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showHomePage)
                                                 name:@"ShowHomePage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showDownloadPage)
                                                 name:@"ShowDownloadPage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showVersionManager)
                                                 name:@"ShowVersionManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showProfileEditor:)
                                                 name:@"ShowProfileEditor"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showSettings)
                                                 name:@"ShowSettings"
                                               object:nil];
    // ZeroTier/Terracotta 联机暂时移除（排查启动崩溃）
    // [[NSNotificationCenter defaultCenter] addObserver:self
    //                                          selector:@selector(showMultiplayer)
    //                                              name:@"ShowMultiplayer"
    //                                            object:nil];
    // [[NSNotificationCenter defaultCenter] addObserver:self
    //                                          selector:@selector(showZeroTier)
    //                                              name:@"ShowZeroTier"
    //                                            object:nil];
    // 账户管理：右侧面板点击头像会发 ShowAccountManager 通知。
    // 原实现遗漏此监听，导致卡片布局下点头像无反应、无法登录账号。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showAccountManager)
                                                 name:@"ShowAccountManager"
                                               object:nil];
    // AI 助手：卡片布局下点侧边栏 AI Agent 按钮发 ShowAIPage 通知。
    // 关键修复（点 AI 中间栏不切换）：卡片布局此前未监听 ShowAIPage，
    // 导致菜单发出通知后无人响应、中间栏不变。与 LauncherRootViewController 对齐。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showAIPage)
                                                 name:@"ShowAIPage"
                                               object:nil];
    // 首页快捷瓷砖触发：切到对应内容区子页面（不再 FormSheet 弹窗）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showModsManager)
                                                 name:@"ShowModsManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showShadersManager)
                                                 name:@"ShowShadersManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showModpackImport)
                                                 name:@"ShowModpackImport"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showGameDirectory)
                                                 name:@"ShowGameDirectory"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backgroundChanged)
                                                 name:@"BackgroundChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(uiEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
    // 监听版本切换，重新加载编辑器
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfileEditorIfNeeded)
                                                 name:@"SelectedProfileChanged"
                                               object:nil];
    // 监听游戏目录切换，重新加载版本列表
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadVersionLists)
                                                 name:@"ReloadProfileList"
                                               object:nil];
    // 监听查找版本请求
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(findVersionInRemoteList:)
                                                 name:@"FindVersionInRemoteList"
                                               object:nil];
}

- (void)findVersionInRemoteList:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *versionId = userInfo[@"versionId"];
    void (^callback)(NSDictionary *) = userInfo[@"callback"];
    
    if (!versionId || !callback) {
        return;
    }
    
    // 在远程版本列表中查找
    NSDictionary *versionObject = nil;
    for (NSDictionary *version in remoteVersionList) {
        if ([version[@"id"] isEqualToString:versionId]) {
            versionObject = version;
            break;
        }
    }
    
    // 如果在远程列表中找不到，检查是否是本地版本
    if (!versionObject) {
        for (NSDictionary *version in localVersionList) {
            if ([version[@"id"] isEqualToString:versionId]) {
                versionObject = version;
                break;
            }
        }
    }
    
    callback(versionObject);
}

- (void)reloadVersionLists {
    // 重新加载版本列表
    [self initializeVersionLists];
    // 通知右侧面板刷新版本显示
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
}

- (void)showHomePage {
    LauncherNewsViewController *newsVC = [[LauncherNewsViewController alloc] init];
    [self setContentViewController:newsVC animated:YES];
}

- (void)showDownloadPage {
    // 在中间内容区显示下载页面，包在 NavigationController 中以便子流程（版本选择/安装器）push 显示
    DownloadViewController *downloadVC = [[DownloadViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:downloadVC];
    nav.navigationBar.prefersLargeTitles = NO;
    [self setContentViewController:nav animated:YES];
}

- (void)showVersionManager {
    // 在中间内容区显示版本管理页面，包在 NavigationController 中以便子流程（模组/光影/游戏目录管理）push
    VersionManagerViewController *vc = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = NO;
    [self setContentViewController:nav animated:YES];
}

- (void)showProfileEditor:(NSNotification *)notification {
    // 在中间内容区显示版本编辑器页面（使用 ProfileSettingsViewController）
    NSString *profileName = notification.object;

    ProfileSettingsViewController *vc = [[ProfileSettingsViewController alloc] init];
    vc.profileName = profileName;

    // 包装在导航控制器中
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = NO;

    self.profileEditorVC = vc;
    self.isShowingProfileEditor = YES;
    [self setContentViewController:navVC animated:YES];
}

- (void)reloadProfileEditorIfNeeded {
    // 如果当前正在显示编辑器页面，重新加载
    if (self.isShowingProfileEditor) {
        NSString *currentProfile = PLProfiles.current.selectedProfileName;
        if (currentProfile) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowProfileEditor" object:currentProfile];
        }
    }
}

- (void)showSettings {
    // 在中间内容区显示设置页面
    LauncherPreferencesViewController *vc = [[LauncherPreferencesViewController alloc] init];
    // 包装在导航控制器中，使其子页面能够正常导航
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = YES;
    [self setContentViewController:navVC animated:YES];
}

- (void)showAIPage {
    // 在中间内容区显示 AI 助手页面（与 LauncherRootViewController showAIPage 一致）。
    // 关键修复（点 AI 中间栏不切换）：卡片布局此前缺失此方法，
    // 现在 ShowAIPage 通知到达后能正常切到 AI 页面。
    // 从 AiSessionStore 取最近会话，没有则让 AIViewController 新建一个。
    AiSession *session = [[AiSessionStore sharedStore] lastActiveSession];
    AIViewController *vc = [[AIViewController alloc] initWithSession:session];
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:vc];
    navVC.navigationBar.prefersLargeTitles = NO;
    [self setContentViewController:navVC animated:YES];
}

// ZeroTier/Terracotta 联机暂时移除（排查启动崩溃）
// - (void)showMultiplayer { ... TerracottaViewController ... }
// - (void)showZeroTier { ... MultiplayerViewController ... TerracottaManager ... }
- (void)showMultiplayer {
    [self showMultiplayerDisabledAlert];
}
- (void)showZeroTier {
    [self showMultiplayerDisabledAlert];
}
- (void)showMultiplayerDisabledAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"i18n_str_320", nil)
                          message:localize(@"i18n_str_321", nil)
                   preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_322", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAccountManager {
    // 卡片布局下账户管理在中间内容区显示（与 VS 布局 LauncherRootViewController 行为一致）。
    // 右侧面板点击头像发 ShowAccountManager 通知触发此方法。
    // 使用 insetGrouped 样式让账户列表呈现圆角分组卡片（原默认 plain 为直角行）。
    AccountListViewController *vc = [[AccountListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.whenItemSelected = ^void() {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
    };
    vc.whenDelete = ^void(NSString *name) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = NO;
    [self setContentViewController:nav animated:YES];
}

#pragma mark - 首页快捷入口 (替换原 FormSheet 弹窗)

- (void)showModsManager {
    // 切到版本管理页并直接 push 模组管理
    // 修复"前一界面未消失"竞态：先构建完整 nav 栈再 setContentViewController，
    // 这样 setContentViewController 内的 for 循环能一次性透明化栈中所有 VC，
    // 避免 animated:YES 的 crossDissolve 进行中再 animated:NO push 导致新 VC 未透明化。
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    ModsManagerViewController *m = [[ModsManagerViewController alloc] init];
    [nav pushViewController:m animated:NO];
    [self setContentViewController:nav animated:YES];
}

- (void)showShadersManager {
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    ShadersManagerViewController *s = [[ShadersManagerViewController alloc] init];
    s.initialMode = ShadersManagerModeLocal;
    [nav pushViewController:s animated:NO];
    [self setContentViewController:nav animated:YES];
}

- (void)showGameDirectory {
    VersionManagerViewController *vm = [[VersionManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vm];
    nav.navigationBar.prefersLargeTitles = NO;
    LauncherPrefGameDirViewController *g = [[LauncherPrefGameDirViewController alloc] init];
    [nav pushViewController:g animated:NO];
    [self setContentViewController:nav animated:YES];
}

- (void)showModpackImport {
    // 切到下载页并直接 push 整合包导入界面
    DownloadViewController *d = [[DownloadViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:d];
    nav.navigationBar.prefersLargeTitles = NO;
    ModpackImportViewController *m = [[ModpackImportViewController alloc] init];
    [nav pushViewController:m animated:NO];
    [self setContentViewController:nav animated:YES];
}

- (void)backgroundChanged {
    // 重新应用背景
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];
}

- (void)uiEffectChanged:(NSNotification *)notification {
    // 重新应用毛玻璃/半透明效果到卡片容器视图
    [[BackgroundManager sharedManager] applyEffectToView:self.sidebarCard];
    [[BackgroundManager sharedManager] applyEffectToView:self.contentCard];
    [[BackgroundManager sharedManager] applyEffectToView:self.rightPanelCard];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Content Switching

- (void)setContentViewController:(UIViewController *)viewController animated:(BOOL)animated {
    // ★ 子面板原生基底样式:统一页面底色(systemBackgroundColor)与表格基底
    //   (清透 + separatorColor),幂等;透明定制面板自动跳过(BackgroundManager 的全局背景不受影响)。
    //   移植自 Gsjsjzhznsz 的 Air fork(UIViewController+AMEPanel)。原来挂在导航容器 push 上,
    //   本工程是"内容 VC 替换"架构 ⇒ 改在这里调用。
    [viewController ame_applySubpanelBaseStyle];

    if (!viewController) return;

    // 关键修复（UI 累积异常）：同一实例直接跳过，避免对同一 VC 重复添加约束
    // 和反复调用 applyEffectToNavigationBar: 导致 hairline UIImageView 累积。
    if (viewController == _contentViewController) return;

    // 检查是否切换到非编辑器页面
    if (![viewController isKindOfClass:[UINavigationController class]] ||
        ![((UINavigationController *)viewController).topViewController isKindOfClass:[ProfileSettingsViewController class]]) {
        self.isShowingProfileEditor = NO;
        self.profileEditorVC = nil;
    }

    UIViewController *oldVC = _contentViewController;

    // 移除旧的 + 添加新的
    _contentViewController = viewController;
    [self addChildViewController:viewController];
    viewController.view.translatesAutoresizingMaskIntoConstraints = NO;

    // 修复：对齐 LauncherRootViewController 的 nav bar 透明化处理。
    // 原卡片布局缺失此逻辑，导致 VersionManagerViewController 等被 UINavigationController
    // 包裹的子页面顶部出现默认不透明 nav bar（白条），与卡片背景不融合。
    //
    // 统一参照 RootVC 的完整处理（setContentViewController 中对 nav 栈所有 VC 透明化 +
    // 设置 nav.delegate + didShowViewController 回调中重新透明化）：
    // 1. 透明化 nav 栈中所有 VC（不仅是 topViewController），防止 push 后子页面样式被重置
    // 2. 设置 nav.delegate = self，在 didShowViewController 回调中重新应用 nav bar 效果
    // 3. 重新应用 nav bar 效果，确保 push/pop 后样式一致
    if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)viewController;
        nav.delegate = self;
        [[BackgroundManager sharedManager] applyEffectToNavigationBar:nav.navigationBar];
        // 透明化栈中所有 VC（与 RootVC 一致），防止 push 后子页面背景不透明
        for (UIViewController *vc in nav.viewControllers) {
            [[BackgroundManager sharedManager] makeViewControllerTransparent:vc];
        }
    } else {
        [[BackgroundManager sharedManager] makeViewControllerTransparent:viewController];
    }

    // 关键修复（UI 累积异常）：deactivate 旧约束，避免在 tmpRootVC 保留场景下
    // 缓存复用的子 VC 反复激活约束导致 contentCard 内容区左右变宽。
    if (self.currentContentConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.currentContentConstraints];
        self.currentContentConstraints = nil;
    }

    NSArray<NSLayoutConstraint *> *newConstraints = @[
        [viewController.view.leadingAnchor constraintEqualToAnchor:self.contentCard.leadingAnchor],
        [viewController.view.trailingAnchor constraintEqualToAnchor:self.contentCard.trailingAnchor],
        [viewController.view.topAnchor constraintEqualToAnchor:self.contentCard.topAnchor],
        [viewController.view.bottomAnchor constraintEqualToAnchor:self.contentCard.bottomAnchor]
    ];

    if (animated && oldVC) {
        // 修复问题5：原实现用两个独立的 UIView transitionWithView:（一个移除旧视图、一个添加新视图），
        // 两个 crossDissolve 同时作用于 contentCard 会导致视觉冲突和残影（旧画面未完全消失就覆盖新界面）。
        // 改为单个 transition：在同一个 animations block 内完成"移除旧视图 + 添加新视图"，
        // crossDissolve 会正确抓取前后快照做交叉渐变，completion 中清理旧 VC 父子关系。
        //
        // 关键修复（入场动画从左上角弹出）：UIKit 在 animations block 返回后立即对容器做 snapshot，
        // 此时新视图虽然已 addSubview + activateConstraints，但尚未经历 layout pass，frame 仍是
        // (0,0,0,0)。配合 contentCard 的 masksToBounds=YES + 圆角裁剪，crossDissolve 渐变呈现
        // "从左上角小点扩展出来"的怪异效果。在 animations block 内显式 layoutIfNeeded 强制立即
        // 布局，让 snapshot B 时 frame 已撑满，crossDissolve 就是标准的淡入淡出。
        // duration 由 0.25 调整为 0.3 让过渡更柔和自然（与 LauncherRootViewController 一致）。
        [UIView transitionWithView:self.contentCard
                          duration:0.3
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                            [oldVC willMoveToParentViewController:nil];
                            [oldVC.view removeFromSuperview];
                            [self.contentCard addSubview:viewController.view];
                            [NSLayoutConstraint activateConstraints:newConstraints];
                            [self.contentCard layoutIfNeeded];
                        } completion:^(BOOL finished) {
                            [oldVC removeFromParentViewController];
                            [viewController didMoveToParentViewController:self];
                        }];
    } else {
        if (oldVC) {
            [oldVC willMoveToParentViewController:nil];
            [oldVC.view removeFromSuperview];
            [oldVC removeFromParentViewController];
        }
        [self.contentCard addSubview:viewController.view];
        [NSLayoutConstraint activateConstraints:newConstraints];
        [viewController didMoveToParentViewController:self];
    }

    self.currentContentConstraints = newConstraints;
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // ★ [PORTRAIT] 放开竖屏:原来是写死 Landscape ⇒ 竖屏进不去。
    // 竖屏排布由 LauncherCardLayoutViewController 切换(三卡竖摞 + 菜单横排);
    // 游戏(SurfaceViewController)单独锁横屏,保证游戏内不会竖过来。
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - UINavigationControllerDelegate

/// nav push/pop 后重新透明化所有 VC 并重新应用 nav bar 效果
/// 参照 RootVC 的同名实现，确保 push 后子页面样式与卡片背景一致
- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    // 透明化刚显示的 VC
    [[BackgroundManager sharedManager] makeViewControllerTransparent:viewController];
    // 同时透明化栈中所有 VC（防止前一个页面透出残留，解决"前一页面未及时消失"问题）
    for (UIViewController *stackVC in navigationController.viewControllers) {
        [[BackgroundManager sharedManager] makeViewControllerTransparent:stackVC];
    }
    // 重新应用导航栏毛玻璃效果（防止 push 后 nav bar 样式被重置）
    [[BackgroundManager sharedManager] applyEffectToNavigationBar:navigationController.navigationBar];
}

@end
