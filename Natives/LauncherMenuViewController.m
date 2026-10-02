#import "LauncherMenuViewController.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherPreferences.h"
#import "VersionManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "PLProfiles.h"
#import "BackgroundManager.h"
#import "utils.h"

// ===========================================================================
//  ★ [E2] 菜单(导航)改造 —— 按 E 方案(Liquid Glass)SPEC §2/§3 落地
//  ---------------------------------------------------------------------------
//  竖屏:底部【4 个标签】(实例 / 下载 / 资源 / 设置),图标在上、文字在下,
//        选中 = 系统强调蓝(#0A84FF 深 / #007AFF 浅)。
//  横屏:左侧栏【带文字的命名项】(实例 / 下载中心 / 资源管理 / 多人游戏 / 设置)
//        + 顶部「Air」品牌头 + 底部一行版本信息(Metal · 26.2 / v5.1.0)。
//  颜色令牌全部来自 SPEC §2.1(E-glass 行 9/11、E-land 行 39),深浅两套走
//        colorWithDynamicProvider: 自动随系统外观切换。
//  灵动岛占位项:横屏侧栏正中(≈屏幕垂直中心 = 岛所在)保留【同尺寸不可见占位】,
//        避免删项后 UIStackView(EqualSpacing) 重新均分导致其余按钮整体位移。
//  依据稿:E-glass.html(行 38-151)、E-land.html(行 9/14/15/39)、
//          _uiwork/ref/E-glass_四态.png(四态视觉基准)。
// ===========================================================================

/// 强调蓝:深色 #0A84FF / 浅色 #007AFF(SPEC §2.1 · E-glass 行 9/11)
static UIColor *E2AccentColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        if (t.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithRed:0x0A / 255.0 green:0x84 / 255.0 blue:0xFF / 255.0 alpha:1.0];
        }
        return [UIColor colorWithRed:0x00 / 255.0 green:0x7A / 255.0 blue:0xFF / 255.0 alpha:1.0];
    }];
}

/// 主文字 fg:深 #FFFFFF / 浅 #0B0B0C(E-glass 行 9/11;E-land 用 #1C1C1E)
static UIColor *E2ForegroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        if (t.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor whiteColor];
        }
        return [UIColor colorWithRed:0x0B / 255.0 green:0x0B / 255.0 blue:0x0C / 255.0 alpha:1.0];
    }];
}

/// 次要文字 dim:深 rgba(255,255,255,.58) / 浅 rgba(0,0,0,.55)(SPEC §2.1)
static UIColor *E2DimColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        if (t.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:1.0 alpha:0.58];
        }
        return [UIColor colorWithWhite:0.0 alpha:0.55];
    }];
}

/// 品牌 logo 渐变:紫(#7b5cff)→ 青(#42d6ff)(E-land 行 13)
static UIColor *E2BrandLogoStart(void) {
    return [UIColor colorWithRed:0x7b / 255.0 green:0x5c / 255.0 blue:0xff / 255.0 alpha:1.0];
}
static UIColor *E2BrandLogoEnd(void) {
    return [UIColor colorWithRed:0x42 / 255.0 green:0xd6 / 255.0 blue:0xff / 255.0 alpha:1.0];
}

static const NSInteger kE2IconTag  = 4201;   // 菜单按钮内的 UIImageView(图标)
static const NSInteger kE2LabelTag = 4202;   // 菜单按钮内的 UILabel(文字)

// 竖屏底部标签栏尺寸 / 横屏侧栏尺寸(E-glass 底栏高 56、E-land 项 9×14 内边距)
static const CGFloat kE2PortraitIconSize  = 22.0;
static const CGFloat kE2PortraitTitleSize = 11.0;
static const CGFloat kE2LandscapeIconSize  = 18.0;
static const CGFloat kE2LandscapeTitleSize = 9.5;
static const CGFloat kE2LandscapeButtonW = 46.0;
static const CGFloat kE2LandscapeButtonH = 36.0;
static const CGFloat kE2LandscapeSpacing = 4.0;

@interface LauncherMenuViewController ()

@property(nonatomic, strong) UIView *sidebarView;
@property(nonatomic, strong) UIStackView *menuStackView;
@property(nonatomic, strong) NSArray<NSDictionary *> *menuItems;
// ★ [E2] 按 index 顺序持有菜单按钮,便于朝向切换时统一改文字/尺寸/可见性
@property(nonatomic, strong) NSMutableArray<UIButton *> *menuButtons;
@property(nonatomic, strong) NSMutableArray<NSArray<NSLayoutConstraint *> *> *buttonSizeConstraints; // @[w,h]
@property(nonatomic, strong) NSMutableArray<NSArray<NSLayoutConstraint *> *> *iconSizeConstraints;   // @[w,h]
// ★ [E2] 品牌头(横屏)与版本脚注(横屏)
@property(nonatomic, strong) UIView *brandHeaderView;
@property(nonatomic, strong) UIView *versionFooterView;
@property(nonatomic, strong) CAGradientLayer *brandLogoGradient;
// ★ [UI-C] 菜单图标自愈定时器(CoreUI 冷启首调用竞态 ⇒ 主界面图标可能拿到 nil)
@property(nonatomic, strong) NSTimer *menuIconSelfHealTimer;
@property(nonatomic, assign) NSInteger selectedIndex;
// ★ [UI-A] 菜单条上下内边距约束(竖屏横排时收紧,给按钮留居中余量)
@property(nonatomic, strong) NSLayoutConstraint *stackTopInsetConstraint;
@property(nonatomic, strong) NSLayoutConstraint *stackBottomInsetConstraint;
// ★ [TOP-BAR] 末尾弹簧:吃掉剩余宽度 ⇒ 图标保持原尺寸、靠左紧挨(不再被 FillEqually 摊开)
@property(nonatomic, strong) UIView *ameMenuSpacer;
// ★ [TOP-BAR] 顶栏"贴合内容":松开栈的右边钉、给菜单视图一个"等于栈宽"的约束
@property(nonatomic, strong) NSLayoutConstraint *ameStackTrailingConstraint;
@property(nonatomic, strong) NSLayoutConstraint *ameHugWidthConstraint;
// ★ [ROT-FIX] 顶栏内容宽度 / 转屏自证日志
@property(nonatomic, assign) CGSize ameLastRotLoggedSize;
- (CGFloat)preferredTopBarWidth;
// ★ [E2] 当前是否竖屏(底部标签栏)。NO = 横屏(左侧栏)。
@property(nonatomic, assign) BOOL compactLayout;
@property(nonatomic, assign) BOOL hasPendingCompact;
@property(nonatomic, assign) BOOL pendingCompact;

@end

@implementation LauncherMenuViewController

#pragma mark - ★ [E2] 排布切换(竖屏底部标签栏 / 横屏左侧栏)

/// 父布局 VC(LauncherCardLayoutViewController)在转屏时调用:
/// 竖屏(compact=YES)⇒ 底部标签栏;横屏(compact=NO)⇒ 左侧栏 + 品牌头 + 版本脚注。
/// 只改 stack 的 axis/alignment/distribution 与按钮尺寸/文字,不动父子约束。
- (void)setCompactHorizontalLayout:(NSNumber *)compactNumber {
    BOOL compact = [compactNumber boolValue];
    if (!self.menuStackView) {          // viewDidLoad 尚未跑完:先记下,稍后补应用
        self.pendingCompact = compact;
        self.hasPendingCompact = YES;
        return;
    }
    [self applyE2LayoutForCompact:compact];
}

/// ★ [E2] 统一应用"竖屏 / 横屏"两套菜单排布。
- (void)applyE2LayoutForCompact:(BOOL)compact {
    if (!self.menuStackView) return;
    self.compactLayout = compact;

    // 1) 方向 / 对齐 / 分布
    //    竖屏:横向一行、等宽铺满、撑满高度(底部标签栏,E-glass 行 61 底栏 4 项 flex:1)。
    //    横屏:竖向一列、居中、按最小间距均分(E-glass 行 98 侧栏 gap 5)。
    self.menuStackView.axis         = compact ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.menuStackView.alignment    = compact ? UIStackViewAlignmentFill     : UIStackViewAlignmentCenter;
    // ★ [TOP-BAR] 改成 Fill + 末尾弹簧:图标维持自身尺寸并靠左,不再被等宽摊开
    // ★ [TOP-BAR] 用户:"间隔等宽" ⇒ 用 FillEqually(每个按钮等宽 ⇒ 视觉上间隔也均匀)
    self.menuStackView.distribution = compact ? UIStackViewDistributionFillEqually
                                              : UIStackViewDistributionEqualSpacing;
    self.menuStackView.spacing      = compact ? 8.0 : kE2LandscapeSpacing;
    // ★ [TOP-BAR] 顶栏:松开栈的右边钉、并让菜单视图宽度=栈宽 ⇒ 整条工具条贴合内容
    if (compact) {
        // ★ [TOP-BAR] 贴合内容:轴向 bug(竖排)已修,这次正确 —— 工具条只占内容那么宽
        self.ameStackTrailingConstraint.active = NO;
        if (!self.ameHugWidthConstraint) {
            self.ameHugWidthConstraint = [self.view.widthAnchor constraintEqualToAnchor:self.menuStackView.widthAnchor];
        }
        self.ameHugWidthConstraint.active = YES;
        if (NO) {
        if (!self.ameMenuSpacer) {
            UIView *sp = [[UIView alloc] init];
            sp.backgroundColor = [UIColor clearColor];
            sp.userInteractionEnabled = NO;
            [sp setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
            [sp setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
            self.ameMenuSpacer = sp;
        }
        }
    } else {
        self.ameHugWidthConstraint.active = NO;
        self.ameStackTrailingConstraint.active = YES;
        if (self.ameMenuSpacer.superview == self.menuStackView) {
            [self.menuStackView removeArrangedSubview:self.ameMenuSpacer];
            [self.ameMenuSpacer removeFromSuperview];
        }
    }

    // 2) 上下内边距(E-glass 底栏 56 高 / 侧栏 padding 10)
    CGFloat inset = compact ? 6.0 : 8.0;
    self.stackTopInsetConstraint.constant    =  inset;
    self.stackBottomInsetConstraint.constant = -inset;

    // 3) 品牌头 / 版本脚注:仅横屏显示(竖屏容器是底部标签栏,放不下也不该有)
    self.brandHeaderView.hidden   = compact;
    self.versionFooterView.hidden = compact;

    // 4) 逐项:文字命名、可见性、尺寸
    for (NSInteger i = 0; i < self.menuButtons.count; i++) {
        UIButton *btn = self.menuButtons[i];
        NSDictionary *item = self.menuItems[i];
        BOOL isPlaceholder  = [item[@"placeholder"] boolValue];
        BOOL landscapeOnly  = [item[@"landscapeOnly"] boolValue];

        // 可见性(★ [TOP-BAR-FIX] 工具栏已搬到【顶部】⇒ 旧的两条隐藏规则过时):
        //  - 占位项(空白,原为横屏侧栏的灵动岛让位):顶部形态不需要 ⇒ 一律隐藏;
        //  - 横屏独有项(多人游戏):以前只在侧栏显示,现在顶栏横着有地方 ⇒ 两种形态都显示。
        if (isPlaceholder) {
            btn.hidden = YES;
        } else {
            btn.hidden = NO;
        }
        (void)landscapeOnly;

        if (!isPlaceholder) {
            UILabel *lbl = (UILabel *)[btn viewWithTag:kE2LabelTag];
            // 命名:竖屏短名(实例/下载/资源/设置);横屏全名(实例/下载中心/资源管理/多人游戏/设置)
            lbl.text = (compact ? item[@"portrait"] : item[@"landscape"]) ?: @"";
            lbl.font = [UIFont systemFontOfSize:(compact ? kE2PortraitTitleSize : kE2LandscapeTitleSize)
                                         weight:UIFontWeightMedium];
            for (NSLayoutConstraint *c in self.iconSizeConstraints[i]) {
                c.constant = compact ? kE2PortraitIconSize : kE2LandscapeIconSize;
            }
        }

        // ★ [TOP-BAR] 固定尺寸;顶栏形态统一成 56×44 ⇒ 所有按钮【等宽】(不再被长短标签撑差)
        NSUInteger sizeIdx = 0;
        for (NSLayoutConstraint *c in self.buttonSizeConstraints[i]) {
            c.active = YES;
            c.constant = compact ? (sizeIdx == 0 ? 56.0 : 44.0) : c.constant;
            sizeIdx++;
        }
    }

    [self updateButtonColors];
    [self.menuStackView setNeedsLayout];
    [self.view setNeedsLayout];

    // ★ [E2] 自证日志:装机后可用 `log stream --predicate 'processImagePath CONTAINS "Air"'` 核对朝向是否真的切了。
    NSUInteger visible = 0;
    for (UIButton *b in self.menuButtons) { if (!b.hidden) visible++; }
    NSLog(@"[E2][MENU] layout=%@ items=%lu/%lu (竖屏=底部4标签 / 横屏=侧栏5项+占位) sideW=%.0f",
          compact ? @"PORTRAIT-TABBAR" : @"LANDSCAPE-SIDEBAR",
          (unsigned long)visible, (unsigned long)self.menuButtons.count,
          self.view.bounds.size.width);
}

/// ★ [ROT-FIX] 顶栏内容宽度:紧凑形态 = visible 按钮 × 56 + (visible-1) × 8。
/// RootVC 用它显式设定顶栏容器宽度 ⇒ 宽度确定，不再被 solver 解成“半截”。
/// (56/8 必须与 applyE2LayoutForCompact: 里的紧凑常量一致)
- (CGFloat)preferredTopBarWidth {
    if (!self.compactLayout || !self.menuStackView) return 0.0;
    NSUInteger visible = 0;
    for (UIButton *b in self.menuButtons) { if (!b.hidden) visible++; }
    if (visible == 0) return 0.0;
    return (CGFloat)visible * 56.0 + (CGFloat)(visible - 1) * 8.0;
}

/// ★ [ROT-FIX] 转屏时按当前 compactLayout 重放一次紧凑排布:
/// 旧实现 applyE2LayoutForCompact: 仅 viewDidLoad 跑过一次 ⇒ 转屏后
/// hug / 按钮尺寸 / 可见性状态不再被断言，顶栏会停留或退化成旧宽度。
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self applyE2LayoutForCompact:self.compactLayout];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 即使本控制器在 LauncherRootViewController 中作为子 VC 添加，仍需在自身 viewDidLoad 中调用。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    // 监听外观变更（字体颜色变化时刷新菜单按钮颜色）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyCustomAppearance)
                                                 name:@"LauncherAppearanceChanged"
                                               object:nil];

    // ★ [E2] 菜单项配置(6 项)。
    //   portrait  = 竖屏底部标签栏用的短名(4 项:实例/下载/资源/设置)
    //   landscape = 横屏左侧栏用的全名(5 项:实例/下载中心/资源管理/多人游戏/设置)
    //   landscapeOnly = 仅横屏可见(多人游戏 / 占位)
    //   placeholder   = 灵动岛同尺寸不可见占位(横屏侧栏正中 ≈ 屏幕垂直中心)
    //   命名依据:E-land.html 行 14-18(实例/下载中心/资源管理/多人游戏/设置);
    //             E-glass.html 行 62(竖屏底栏 实例/下载/资源/设置)。
    self.menuItems = @[
        @{@"icon": @"house.fill",             @"portrait": @"实例", @"landscape": @"实例",   @"index": @0},
        @{@"icon": @"arrow.down.circle.fill", @"portrait": @"下载", @"landscape": @"下载中心", @"index": @1},
        // ★ [TOP-BAR-FIX] AI 入口恢复显示:工具栏已搬到【顶部】,灵动岛在条外,
        //   原来"让位给灵动岛"的空占位不再需要(用户:"那 ai 按钮呢")。
        @{@"icon": @"sparkles", @"portrait": @"AI", @"landscape": @"AI", @"index": @2},
        @{@"icon": @"puzzlepiece.fill",       @"portrait": @"资源", @"landscape": @"资源管理", @"index": @3},
        // [E2] 多人游戏:E-land 行 17(🌐 多人游戏),横屏侧栏第 4 项,竖屏底栏不放。
        @{@"icon": @"network",                @"portrait": @"",     @"landscape": @"多人游戏", @"index": @4,
          @"landscapeOnly": @YES},
        @{@"icon": @"gearshape.fill",         @"portrait": @"设置", @"landscape": @"设置",   @"index": @5}
    ];

    self.selectedIndex = 0;

    [self setupSidebar];

    // ★ [TOP-BAR-FIX] 顶栏形态是【横排】:这里强制应用一次,不再依赖外部调用
    //   (301 行 setupSidebar 里硬编码过 axis=Vertical ⇒ 曾经把按钮排成一列)
    [self applyE2LayoutForCompact:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 品牌 logo 渐变背景要跟随 logo 视图尺寸(E-land 行 13:27×27 圆角 8;此处按侧栏窄宽度缩到 22)
    self.brandLogoGradient.frame = self.brandLogoGradient.superlayer.bounds;
    // ★ [ROT-FIX] 顶栏形态自愈:顶栏容器很矮(≈56)时菜单必须是【横排】，
    //   竖排塞进 56pt 只会露出约一个按钮(用户实测“旋转后顶部工具条只剩下半截”)。
    //   若朝向/父布局把 compactLayout 弄成 NO，这里强制纠正回横排并重放尺寸。
    BOOL ameTopBarForm = (self.view.bounds.size.height > 0.0 && self.view.bounds.size.height < 80.0);
    if (ameTopBarForm && !self.compactLayout) {
        [self applyE2LayoutForCompact:YES];
    }
    // ★ [TOP-BAR-FIX] 兜底:每次布局都按 compactLayout 重新断言一次轴向,防止被别处覆盖
    if (self.menuStackView) {
        UILayoutConstraintAxis want = (self.compactLayout || ameTopBarForm) ? UILayoutConstraintAxisHorizontal
                                                                           : UILayoutConstraintAxisVertical;
        if (self.menuStackView.axis != want) { self.menuStackView.axis = want; }
    }
    // ★ [ROT-FIX] 布置后自证:尺寸变化(含转屏)才打一行，便于装机核对条宽。
    //   menu 视图宽 == 顶栏容器宽(compact 下 RootVC/菜单两处约束一致)。
    CGSize ameSize = self.view.bounds.size;
    if (fabs(ameSize.width - self.ameLastRotLoggedSize.width) > 0.5 ||
        fabs(ameSize.height - self.ameLastRotLoggedSize.height) > 0.5) {
        self.ameLastRotLoggedSize = ameSize;
        NSLog(@"[ROT] %@ size=%.0fx%.0f barW=%.0f",
              self.compactLayout ? @"TOPBAR-H" : @"TOPBAR-V",
              ameSize.width, ameSize.height, ameSize.width);
    }
}

#pragma mark - UI Setup

- (void)setupSidebar {
    self.sidebarView = [[UIView alloc] init];
    self.sidebarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.sidebarView];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.sidebarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.sidebarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.sidebarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.menuButtons          = [NSMutableArray array];
    self.buttonSizeConstraints = [NSMutableArray array];
    self.iconSizeConstraints   = [NSMutableArray array];

    // 创建垂直均分的 UIStackView，替代固定偏移布局。
    // 之前用 startY=60 + 固定间距 15，5 个按钮总高 370pt，在 iPhone 横屏（卡片高度不足）
    // 时第 5 个按钮（设置）被卡片 masksToBounds 裁剪，且按钮只锚定 top 无 bottom 约束，
    // 下方留出大块空白加剧"下面空隙大"的观感。
    // 改用 UIStackView EqualSpacing 让按钮在可用空间内垂直均匀分布，上下留白相同，
    // 无论卡片高度如何都能完整显示所有按钮，且消除固定 startY 导致的下方空白。
    self.menuStackView = [[UIStackView alloc] init];
    self.menuStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.menuStackView.axis = UILayoutConstraintAxisVertical;
    self.menuStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.menuStackView.alignment = UIStackViewAlignmentCenter;
    self.menuStackView.spacing = kE2LandscapeSpacing;
    [self.sidebarView addSubview:self.menuStackView];

    // ★ [E2] 品牌头(横屏顶部:E-land 行 14「✦ Air」)——作为 stack 的首个 arrangedSubview
    self.brandHeaderView = [self buildBrandHeaderView];
    [self.menuStackView addArrangedSubview:self.brandHeaderView];

    for (NSInteger i = 0; i < self.menuItems.count; i++) {
        NSDictionary *item = self.menuItems[i];
        UIButton *btn = [self createMenuButtonWithItem:item index:i];
        [self.menuStackView addArrangedSubview:btn];
        [self.menuButtons addObject:btn];

        // 尺寸约束:横屏激活(固定 46×36),竖屏关闭(靠 FillEqually/Fill 撑满)
        NSLayoutConstraint *w = [btn.widthAnchor  constraintEqualToConstant:kE2LandscapeButtonW];
        NSLayoutConstraint *h = [btn.heightAnchor constraintEqualToConstant:kE2LandscapeButtonH];
        w.priority = UILayoutPriorityDefaultHigh;   // 空间不足(小屏横屏)时允许压缩,避免约束冲突
        h.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[w, h]];
        [self.buttonSizeConstraints addObject:@[w, h]];

        // 图标尺寸约束(朝向切换时改 constant)
        UIImageView *iv = (UIImageView *)[btn viewWithTag:kE2IconTag];
        NSMutableArray<NSLayoutConstraint *> *pair = [NSMutableArray array];
        for (NSLayoutConstraint *c in iv.constraints) {
            if ((c.firstAttribute == NSLayoutAttributeWidth || c.firstAttribute == NSLayoutAttributeHeight) &&
                (c.firstItem == iv || c.secondItem == iv)) {
                [pair addObject:c];
            }
        }
        [self.iconSizeConstraints addObject:pair];
    }

    // ★ [E2] 版本脚注(横屏底部:Metal · 26.2 / v5.1.0,E-glass 行 106)
    self.versionFooterView = [self buildVersionFooterView];
    [self.menuStackView addArrangedSubview:self.versionFooterView];

    [self beginMenuIconSelfHeal];   // ★ [UI-C]

    // ★ [UI-A] 单独持有上下内边距约束,竖屏横排时收紧(见 applyE2LayoutForCompact:)
    self.stackTopInsetConstraint    = [self.menuStackView.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor constant:8];
    self.stackBottomInsetConstraint = [self.menuStackView.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [self.menuStackView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
        (self.ameStackTrailingConstraint = [self.menuStackView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor]),
        self.stackTopInsetConstraint,
        self.stackBottomInsetConstraint,
        [self.menuStackView.centerXAnchor constraintEqualToAnchor:self.sidebarView.centerXAnchor]
    ]];

    // 应用初始朝向:父 VC 若在 viewDidLoad 之前就调过 setCompactHorizontalLayout:,此处补应用;
    // 否则默认横屏(与历史默认一致),随后父 VC 转屏时会再纠正。
    if (self.hasPendingCompact) {
        self.hasPendingCompact = NO;
        [self applyE2LayoutForCompact:self.pendingCompact];
    } else {
        [self applyE2LayoutForCompact:NO];
    }
}

#pragma mark - ★ [E2] 品牌头 / 版本脚注

/// 横屏侧栏顶部品牌头:「Air」(logo 渐变方块 + 粗体字,E-land 行 13-14)。
- (UIView *)buildBrandHeaderView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *logo = [[UIView alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.layer.cornerRadius = 7.0;
    logo.layer.masksToBounds = YES;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[(__bridge id)E2BrandLogoStart().CGColor, (__bridge id)E2BrandLogoEnd().CGColor];
    g.startPoint = CGPointMake(0.0, 0.0);
    g.endPoint   = CGPointMake(1.0, 1.0);
    [logo.layer addSublayer:g];
    self.brandLogoGradient = g;

    UIImageView *spark = [[UIImageView alloc] initWithImage:[self menuIconNamed:@"sparkles"]];
    spark.translatesAutoresizingMaskIntoConstraints = NO;
    spark.contentMode = UIViewContentModeScaleAspectFit;
    spark.tintColor = [UIColor whiteColor];
    [logo addSubview:spark];

    UILabel *air = [[UILabel alloc] init];
    air.translatesAutoresizingMaskIntoConstraints = NO;
    air.text = @"Air";
    air.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    air.textColor = E2ForegroundColor();
    air.adjustsFontSizeToFitWidth = YES;
    air.minimumScaleFactor = 0.6;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[logo, air]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 5.0;
    row.userInteractionEnabled = NO;
    [container addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor  constraintEqualToConstant:22.0],
        [logo.heightAnchor constraintEqualToConstant:22.0],
        [spark.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
        [spark.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [spark.widthAnchor  constraintEqualToConstant:12.0],
        [spark.heightAnchor constraintEqualToConstant:12.0],
        [row.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [row.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        // 等号(而非 >= / <=):让 container 宽度由内容唯一确定,避免 arrangedSubview 宽度歧义
        [row.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:2.0],
        [row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-2.0],
        [container.heightAnchor constraintEqualToConstant:24.0]
    ]];
    return container;
}

/// 横屏侧栏底部版本脚注:「Metal · 26.2」/「v5.1.0」(E-glass 行 106,E-land 行 19)。
/// 侧栏卡片窄(iPhone 横屏仅 56pt),两段并排放不下 ⇒ 竖排两行,居中,仍是"一行版本信息"的语义。
- (UIView *)buildVersionFooterView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *l1 = [self footNoteLabelWithText:@"Metal · 26.2"];
    UILabel *l2 = [self footNoteLabelWithText:@"v5.1.0"];

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[l1, l2]];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    col.axis = UILayoutConstraintAxisVertical;
    col.alignment = UIStackViewAlignmentCenter;
    col.spacing = 1.0;
    col.userInteractionEnabled = NO;
    [container addSubview:col];

    [NSLayoutConstraint activateConstraints:@[
        [col.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [col.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        // 等号:让 container 宽度由内容唯一确定(见品牌头同处理)
        [col.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:2.0],
        [col.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-2.0],
        [container.heightAnchor constraintEqualToConstant:22.0]
    ]];
    return container;
}

- (UILabel *)footNoteLabelWithText:(NSString *)text {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = text;
    lbl.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightRegular];
    lbl.textColor = E2DimColor();
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.adjustsFontSizeToFitWidth = YES;
    lbl.minimumScaleFactor = 0.7;
    return lbl;
}

#pragma mark - ★ [E2] 菜单按钮(图标在上、文字在下)

- (UIButton *)createMenuButtonWithItem:(NSDictionary *)item index:(NSInteger)index {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tag = index;

    // 统一圆角:横屏选中态是"蓝底白字"(E-glass 行 101 / E-land 行 15,圆角 9-11)
    btn.layer.cornerRadius = 10.0;
    btn.layer.masksToBounds = YES;
    btn.backgroundColor = [UIColor clearColor];

    // ★ 占位项(原 AI 位置):尺寸与普通按钮一致,但不可见、不可点 ⇒ 保持间距几何不变
    if ([item[@"placeholder"] boolValue]) {
        btn.userInteractionEnabled = NO;
        btn.tintColor = [UIColor clearColor];
        return btn;
    }

    // 图标(上)
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tag = kE2IconTag;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [btn addSubview:iconView];

    // 文字(下)
    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.tag = kE2LabelTag;
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.numberOfLines = 1;
    titleLbl.adjustsFontSizeToFitWidth = YES;
    titleLbl.minimumScaleFactor = 0.7;
    titleLbl.userInteractionEnabled = NO;
    [btn addSubview:titleLbl];

    // 图标在上、文字在下(竖排 UIStackView 居中) —— 比手调 titleEdgeInsets/imageEdgeInsets 更稳，
    // 不会随朝向/尺寸变化而错位(这正是原实现"竖屏下菜单错位"的根因)。
    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, titleLbl]];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    col.axis = UILayoutConstraintAxisVertical;
    col.alignment = UIStackViewAlignmentCenter;
    col.spacing = 2.0;
    col.userInteractionEnabled = NO;
    [btn addSubview:col];

    NSLayoutConstraint *iw = [iconView.widthAnchor  constraintEqualToConstant:kE2PortraitIconSize];
    NSLayoutConstraint *ih = [iconView.heightAnchor constraintEqualToConstant:kE2PortraitIconSize];
    NSLayoutConstraint *lblW = [titleLbl.widthAnchor constraintLessThanOrEqualToAnchor:btn.widthAnchor constant:-2.0];
    lblW.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [col.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
        [col.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
        [col.leadingAnchor  constraintGreaterThanOrEqualToAnchor:btn.leadingAnchor constant:2.0],
        [col.trailingAnchor constraintLessThanOrEqualToAnchor:btn.trailingAnchor constant:-2.0],
        iw, ih, lblW
    ]];

    [btn addTarget:self action:@selector(menuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - Actions

- (void)menuButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.menuItems.count) return;
    if ([self.menuItems[index][@"placeholder"] boolValue]) return;

    // FCL 风格：选中菜单项时添加弹跳动画（ScaleX/ScaleY 弹跳，OvershootInterpolator 效果）
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.5
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:0
                            options:UIViewAnimationCurveEaseOut
                         animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];

    // 更新选中状态
    self.selectedIndex = index;
    [self updateButtonColors];

    // 回调(上报当前朝向下的命名)
    NSString *title = self.compactLayout ? self.menuItems[index][@"portrait"]
                                         : self.menuItems[index][@"landscape"];
    if (self.onMenuItemSelected) {
        self.onMenuItemSelected(index, title ?: @"");
    }

    // 处理导航
    [self handleMenuSelection:index];
}

/// 刷新所有菜单按钮的颜色(SPEC §2.1 令牌 + 保留用户自定义文字色)。
/// 竖屏(底部标签栏):选中 = 强调蓝文字/图标,无底色(E-glass 行 62)。
/// 横屏(左侧栏):选中 = 强调蓝底 + 白字(E-glass 行 101 / E-land 行 15);未选中 = fg 文字 + dim 图标。
- (void)updateButtonColors {
    UIColor *accent = E2AccentColor();
    UIColor *custom = [self customTextColor];

    for (UIButton *btn in self.menuButtons) {
        NSInteger idx = btn.tag;
        if (idx < 0 || idx >= (NSInteger)self.menuItems.count) continue;
        NSDictionary *item = self.menuItems[idx];
        if ([item[@"placeholder"] boolValue]) { btn.backgroundColor = [UIColor clearColor]; continue; }

        UIImageView *iconView = (UIImageView *)[btn viewWithTag:kE2IconTag];
        UILabel *titleLbl = (UILabel *)[btn viewWithTag:kE2LabelTag];
        BOOL selected = (idx == self.selectedIndex);

        UIColor *labelColor;
        UIColor *iconColor;
        UIColor *bg;

        if (selected) {
            UIColor *onColor = self.compactLayout ? accent : [UIColor whiteColor];
            labelColor = onColor;
            iconColor  = onColor;
            bg = self.compactLayout ? [UIColor clearColor] : accent;
        } else {
            if (custom) {
                labelColor = custom;
                iconColor  = custom;
            } else {
                labelColor = self.compactLayout ? E2DimColor() : E2ForegroundColor();
                iconColor  = E2DimColor();
            }
            bg = [UIColor clearColor];
        }
        titleLbl.textColor = labelColor;
        iconView.tintColor = iconColor;
        btn.backgroundColor = bg;
    }
}

// 字体颜色变更时刷新所有菜单按钮
- (void)applyCustomAppearance {
    [self updateButtonColors];
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 确保全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [self.menuIconSelfHealTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - ★ [E2] 颜色令牌辅助

/// 用户自定义文字色(设置页 general.text_color)——保留主界面自定义能力(brief 硬约束)。
/// 未设置返回 nil,由调用方回落到 SPEC §2.1 的 dim/fg 令牌。
- (UIColor *)customTextColor {
    NSString *hex = getPrefObject(@"general.text_color");
    if (hex.length > 0) {
        return [self colorFromHexString:hex];
    }
    return nil;
}

- (UIColor *)colorFromHexString:(NSString *)hexString {
    NSString *hex = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length != 6 && hex.length != 8) return nil;
    unsigned int r, g, b, a = 255;
    if (hex.length == 6) {
        [[NSScanner scannerWithString:hex] scanHexInt:&r];
        b = r & 0xFF;
        g = (r >> 8) & 0xFF;
        r = (r >> 16) & 0xFF;
    } else {
        [[NSScanner scannerWithString:hex] scanHexInt:&r];
        a = r & 0xFF;
        b = (r >> 8) & 0xFF;
        g = (r >> 16) & 0xFF;
        r = (r >> 24) & 0xFF;
    }
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a/255.0];
}

/// SF Symbol 取图:统一 point size/weight,避免不同调用点尺寸不一(SPEC §2.6 图标风格)。
- (UIImage *)menuIconNamed:(NSString *)name {
    if (name.length == 0) return nil;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:name withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:name];   // 兜底:退回默认配置
    return img;
}

#pragma mark - Navigation

/// 导航映射(沿用既有通知名,不改父控制器行为):
///   0 实例   → ShowHomePage(主页/实例页)
///   1 下载   → ShowDownloadPage
///   2 占位   → 无(不可点)
///   3 资源   → ShowVersionManager(资源/版本管理,沿用原 index 3 语义)
///   4 多人游戏 → ShowMultiplayer(E-land 侧栏第 4 项;父控制器当前未监听 ⇒ 暂为空操作)
///   5 设置   → ShowSettings
- (void)handleMenuSelection:(NSInteger)index {
    switch (index) {
        case 0: // 实例 / 主页
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];
            break;

        case 1: // 下载 / 下载中心
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowDownloadPage" object:nil];
            break;

        case 2: // ★ AI 入口(工具栏搬到顶部后恢复;原为"让位给灵动岛"的空占位)
            [self showAI];
            break;

        case 3: // 资源 / 资源管理(版本管理,合并了原"当前版本设置"功能)
            [self showVersionManager];
            break;

        case 4: // 多人游戏(横屏独有)
            [self showMultiplayer];
            break;

        case 5: // 设置
            [self showSettings];
            break;
    }
}

- (void)showAI {
    // ★ 直接 present AI 会话列表(自包含,不依赖 RootVC 的通知处理器)
    Class cls = NSClassFromString(@"AISessionListViewController");
    if (!cls) { NSLog(@"[E2][MENU] AISessionListViewController 不存在,AI 入口无动作"); return; }
    UIViewController *vc = [[cls alloc] init];
    if (!vc) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *host = self.view.window.rootViewController ?: self;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)showVersionManager {
    // 发送通知让 LauncherRootViewController 在中间内容区显示
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowVersionManager" object:nil];
}

- (void)showMultiplayer {
    // 发送通知让 LauncherRootViewController 显示陶瓦联机界面
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowMultiplayer" object:nil];
}

- (void)showZeroTier {
    // 发送通知让 LauncherRootViewController 显示 ZeroTier 联机界面
    // ZeroTier 与陶瓦联机为并列的两套联机方案，独立菜单入口避免用户先进入陶瓦再切换。
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowZeroTier" object:nil];
}

- (void)showSettings {
    // 发送通知让 LauncherRootViewController 在中间内容区显示
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowSettings" object:nil];
}

#pragma mark - Data Updates

- (void)updateAccountInfo {
    // 账户信息在右侧面板显示，这里不需要处理
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

/// ★ [PORTRAIT] 放开方向:原来写死 Landscape ⇒ 竖屏根本进不去。
/// 竖屏下的排布由父布局 VC 通过 setCompactHorizontalLayout: 切换(三卡竖摞 + 菜单横排一行)。
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

/// 深浅色切换:标签颜色用 dynamic color 自动跟随,这里再刷一遍以防自定义色/底色残留。
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateButtonColors];
        }
    }
}

#pragma mark - ★ [UI-C] 菜单图标自愈

// 根因(上游 Task102/111):主界面按钮是循环里第一个调用 systemImageNamed: 的控件,
// 进程冷启动首调用存在 CoreUI 符号注册竞态 —— 首调用偶尔拿到 nil,后续调用全部正常,
// 症状固定为"只有主界面图标消失,其他按钮都在"。这里用 0.25s×40 的有界重试 + 强制重设兜底。
// [E2] 图标改为按钮内的独立 UIImageView(图标在上/文字在下),自愈目标随之改到该 imageView。
- (void)refreshMenuIconImages {
    [self refreshMenuIconImagesForced:NO];
}

- (void)refreshMenuIconImagesForced:(BOOL)forced {
    for (NSInteger i = 0; i < self.menuButtons.count; i++) {
        UIButton *btn = self.menuButtons[i];
        if (i >= (NSInteger)self.menuItems.count) continue;
        NSString *iconName = self.menuItems[i][@"icon"];
        if (iconName.length == 0) continue;              // 占位项没有图标
        UIImageView *iconView = (UIImageView *)[btn viewWithTag:kE2IconTag];
        if (!iconView) continue;
        if (!forced && iconView.image) continue;
        UIImage *icon = [self menuIconNamed:iconName];
        if (!icon) continue;
        iconView.image = icon;
        iconView.hidden = NO;
        [btn bringSubviewToFront:iconView];
    }
}

- (BOOL)allMenuIconsLoaded {
    for (NSInteger i = 0; i < self.menuButtons.count; i++) {
        UIButton *btn = self.menuButtons[i];
        if (i >= (NSInteger)self.menuItems.count) continue;
        NSString *iconName = self.menuItems[i][@"icon"];
        if (iconName.length == 0) continue;              // 占位项不计
        UIImageView *iconView = (UIImageView *)[btn viewWithTag:kE2IconTag];
        if (!iconView.image) return NO;
    }
    return YES;
}

- (void)beginMenuIconSelfHeal {
    [self refreshMenuIconImagesForced:YES];
    if (self.menuIconSelfHealTimer) return;
    __weak typeof(self) weakSelf = self;
    __block NSInteger attempts = 0;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { [t invalidate]; return; }
        [strongSelf refreshMenuIconImagesForced:YES];
        attempts += 1;
        if (([strongSelf allMenuIconsLoaded] && attempts >= 8) || attempts >= 40) {
            [strongSelf.menuIconSelfHealTimer invalidate];
            strongSelf.menuIconSelfHealTimer = nil;
        }
    }];
    self.menuIconSelfHealTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

@end
