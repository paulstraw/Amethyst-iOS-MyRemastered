#import "LauncherMenuViewController.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherPreferences.h"
#import "VersionManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "PLProfiles.h"
#import "BackgroundManager.h"
#import "utils.h"

@interface LauncherMenuViewController ()

@property(nonatomic, strong) UIView *sidebarView;
@property(nonatomic, strong) UIStackView *menuStackView;
@property(nonatomic, strong) NSArray<NSDictionary *> *menuItems;
// ★ [UI-C] 菜单图标自愈定时器(CoreUI 冷启首调用竞态 ⇒ 主界面图标可能拿到 nil)
@property(nonatomic, strong) NSTimer *menuIconSelfHealTimer;
@property(nonatomic, assign) NSInteger selectedIndex;
// ★ [UI-A] 菜单条上下内边距约束(竖屏横排时收紧,给 50pt 按钮留居中余量)
@property(nonatomic, strong) NSLayoutConstraint *stackTopInsetConstraint;
@property(nonatomic, strong) NSLayoutConstraint *stackBottomInsetConstraint;

@end

@implementation LauncherMenuViewController

#pragma mark - ★ [PORTRAIT] 排布切换

/// 竖屏(compact):菜单改成【横向一行】并与卡片等宽;横屏恢复【竖向一列】。
/// 只改 stack 的 axis/spacing,不动按钮与约束(约束是 leading/trailing 铺满,两向都成立)。
- (void)setCompactHorizontalLayout:(NSNumber *)compactNumber {
    BOOL compact = [compactNumber boolValue];
    if (!self.menuStackView) return;
    self.menuStackView.axis = compact ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.menuStackView.spacing = compact ? 6 : 8;
    self.menuStackView.alignment = UIStackViewAlignmentCenter;
    self.menuStackView.distribution = UIStackViewDistributionEqualSpacing;

    // ★ [UI-A] 竖屏横排:菜单卡矮(72pt),把上下内边距从 8 收到 4,使 50pt 按钮有更充分的
    //   居中余量,避免小屏(iPhone SE 等)上按钮边缘被菜单卡圆角 + masksToBounds 裁切。
    CGFloat inset = compact ? 4 : 8;
    self.stackTopInsetConstraint.constant    = inset;
    self.stackBottomInsetConstraint.constant = -inset;

    // ★ 关键修复(竖屏错位根因):按钮的 titleEdgeInsets/imageEdgeInsets 是按【竖排】
    //   "图标在上、文字在下"手调的(见 createMenuButtonWithItem:)。横排时必须把它们清零,
    //   否则图标与文字会各自偏到角落 —— 这就是竖屏下菜单看着"错位/歪"的原因。
    for (UIView *v in self.menuStackView.arrangedSubviews) {
        if (![v isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)v;
        if (compact) {
            b.titleEdgeInsets = UIEdgeInsetsZero;
            b.imageEdgeInsets = UIEdgeInsetsZero;
            b.contentEdgeInsets = UIEdgeInsetsMake(2, 0, 2, 0);
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        } else {
            b.titleEdgeInsets = UIEdgeInsetsMake(30, -30, 0, 0);   // 与原始实现一致
            b.imageEdgeInsets = UIEdgeInsetsMake(-10, 0, 0, 0);
            b.contentEdgeInsets = UIEdgeInsetsZero;
        }
    }
    [self.menuStackView setNeedsLayout];
    [self.view setNeedsLayout];
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

    // 菜单项配置
    // 联机相关入口暂不显示（需进一步完善）
    // case 3 为"联机"（陶瓦联机 Terracotta，与 HMCL/FCL/ZL2 互通）
    // case 4 为"ZeroTier 联机"（独立入口，与陶瓦联机并列，便于用户直接进入 ZeroTier 界面）
    // case 5 为"设置"
    // 键位调整界面已移到设置页面中
    self.menuItems = @[
        @{@"icon": @"house.fill", @"title": @" ", @"index": @0},
        @{@"icon": @"arrow.down.circle.fill", @"title": @" ", @"index": @1},
        // ★ AI 入口从侧栏移出(横屏时灵动岛正好压在这一格上 ⇒ 5 格均分的正中)
        //   这里保留【同尺寸占位】而不是删除:删掉会让 UIStackView(EqualSpacing) 重新均分,
        //   其余 4 个按钮的位置会整体位移。占位尺寸与按钮一致 ⇒ 几何完全不变,只是不显示。
        @{@"icon": @"", @"title": @" ", @"index": @2, @"placeholder": @YES},
        @{@"icon": @"puzzlepiece.fill", @"title": @" ", @"index": @3},
        // 暂时移除两个联机图标，恢复时取消下方两行注释并将设置项 index 改回 @6
        // @{@"icon": @"antenna.radiowaves.left.and.right", @"title": @" ", @"index": @4},
        // @{@"icon": @"network", @"title": @" ", @"index": @5},
        @{@"icon": @"gearshape.fill", @"title": @" ", @"index": @4}
    ];
    
    self.selectedIndex = 0;
    
    [self setupSidebar];
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

    // 创建垂直均分的 UIStackView，替代固定偏移布局。
    // 之前用 startY=60 + 固定间距 15，5 个按钮总高 370pt，在 iPhone 横屏（卡片高度不足）
    // 时第 5 个按钮（设置）被卡片 masksToBounds 裁剪，且按钮只锚定 top 无 bottom 约束，
    // 下方留出大块空白加剧"下面空隙大"的观感。
    // 改用 UIStackView EqualSpacing 让按钮在可用空间内垂直均匀分布，上下留白相同，
    // 无论卡片高度如何都能完整显示所有按钮，且消除固定 startY 导致的下方空白。
    self.menuStackView = [[UIStackView alloc] init];
    self.menuStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.menuStackView.axis = UILayoutConstraintAxisVertical;
    [self beginMenuIconSelfHeal];   // ★ [UI-C]
    self.menuStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.menuStackView.alignment = UIStackViewAlignmentCenter;
    self.menuStackView.spacing = 8;
    [self.sidebarView addSubview:self.menuStackView];

    CGFloat buttonSize = 50;
    for (NSInteger i = 0; i < self.menuItems.count; i++) {
        NSDictionary *item = self.menuItems[i];
        UIButton *btn = [self createMenuButtonWithItem:item index:i];
        [self.menuStackView addArrangedSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:buttonSize],
            [btn.heightAnchor constraintEqualToConstant:buttonSize]
        ]];
    }

    // ★ [UI-A] 单独持有上下内边距约束,竖屏横排时收紧(见 setCompactHorizontalLayout:)
    self.stackTopInsetConstraint    = [self.menuStackView.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor constant:8];
    self.stackBottomInsetConstraint = [self.menuStackView.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [self.menuStackView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
        [self.menuStackView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
        self.stackTopInsetConstraint,
        self.stackBottomInsetConstraint,
        [self.menuStackView.centerXAnchor constraintEqualToAnchor:self.sidebarView.centerXAnchor]
    ]];
}

- (UIButton *)createMenuButtonWithItem:(NSDictionary *)item index:(NSInteger)index {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tag = index;

    // ★ 占位项(原 AI 位置):尺寸与普通按钮一致,但不可见、不可点 ⇒ 保持间距几何不变
    if ([item[@"placeholder"] boolValue]) {
        btn.userInteractionEnabled = NO;
        btn.backgroundColor = [UIColor clearColor];
        btn.tintColor = [UIColor clearColor];
        btn.titleLabel.text = @"";
        return btn;
    }

    // 设置图标
    UIImage *icon = [UIImage systemImageNamed:item[@"icon"]];
    [btn setImage:icon forState:UIControlStateNormal];

    // 设置颜色 - 选中项高亮
    // 支持自定义字体颜色：用户在设置中配置 general.text_color 后，
    // 未选中项使用自定义颜色，选中项保持高亮蓝色
    UIColor *normalColor = [self menuNormalColor];
    UIColor *accent = accentColor();
    if (index == self.selectedIndex) {
        btn.tintColor = accent;
    } else {
        btn.tintColor = normalColor;
    }

    // 设置标题（在图标下方）
    btn.titleLabel.font = [UIFont systemFontOfSize:10];
    [btn setTitle:item[@"title"] forState:UIControlStateNormal];
    [btn setTitleColor:(index == self.selectedIndex) ? accent : normalColor forState:UIControlStateNormal];
    
    // 垂直布局：图标在上，文字在下
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    btn.titleEdgeInsets = UIEdgeInsetsMake(30, -30, 0, 0);
    btn.imageEdgeInsets = UIEdgeInsetsMake(-10, 0, 0, 0);
    
    [btn addTarget:self action:@selector(menuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // 统一圆角：防御性设置 10pt，避免后续给选中态加背景高亮时出现直角方块
    btn.layer.cornerRadius = 10;
    btn.layer.masksToBounds = YES;

    return btn;
}

#pragma mark - Actions

- (void)menuButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;

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
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];

    // 更新选中状态
    self.selectedIndex = index;
    [self updateButtonColors];

    // 回调
    NSString *title = self.menuItems[index][@"title"];
    if (self.onMenuItemSelected) {
        self.onMenuItemSelected(index, title);
    }

    // 处理导航
    [self handleMenuSelection:index];
}

- (void)updateButtonColors {
    UIColor *normalColor = [self menuNormalColor];
    UIColor *accent = accentColor();
    // 按钮现在在 menuStackView.arrangedSubviews 中（UIStackView 重构后）
    for (UIView *view in self.menuStackView.arrangedSubviews) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            NSInteger index = btn.tag;

            if (index == self.selectedIndex) {
                btn.tintColor = accent;
                [btn setTitleColor:accent forState:UIControlStateNormal];
                // FCL 风格：选中项添加半透明背景高亮
                btn.backgroundColor = [accent colorWithAlphaComponent:0.15];
            } else {
                btn.tintColor = normalColor;
                [btn setTitleColor:normalColor forState:UIControlStateNormal];
                btn.backgroundColor = [UIColor clearColor];
            }
        }
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 未选中菜单项的颜色：优先使用用户自定义的 general.text_color，否则默认 systemGray
- (UIColor *)menuNormalColor {
    NSString *hex = getPrefObject(@"general.text_color");
    if (hex.length > 0) {
        UIColor *custom = [self colorFromHexString:hex];
        if (custom) return custom;
    }
    return [UIColor systemGrayColor];
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

- (void)handleMenuSelection:(NSInteger)index {
    switch (index) {
        case 0: // 主页
            // 通知父控制器切换到新闻页
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];
            break;

        case 1: // 下载
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowDownloadPage" object:nil];
            break;

        case 2: // AI 助手
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAIPage" object:nil];
            break;

        case 3: // 版本管理（合并了原"当前版本设置"功能）
            [self showVersionManager];
            break;

        case 4: // 设置（联机入口暂时移除，恢复时顺延 index）
            [self showSettings];
            break;
    }
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


#pragma mark - ★ [UI-C] 菜单图标自愈

// 根因(上游 Task102/111):主界面按钮是循环里第一个调用 systemImageNamed: 的控件,
// 进程冷启动首调用存在 CoreUI 符号注册竞态 —— 首调用偶尔拿到 nil,后续调用全部正常,
// 症状固定为"只有主界面图标消失,其他按钮都在"。这里用 0.25s×40 的有界重试 + 强制重设兜底。
- (void)refreshMenuIconImages {
    [self refreshMenuIconImagesForced:NO];
}

- (void)refreshMenuIconImagesForced:(BOOL)forced {
    for (UIView *view in self.menuStackView.arrangedSubviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)view;
        NSInteger idx = btn.tag;
        if (idx < 0 || idx >= (NSInteger)self.menuItems.count) continue;
        UIImage *current = [btn imageForState:UIControlStateNormal];
        if (!forced && current) continue;
        NSString *iconName = self.menuItems[idx][@"icon"];
        if (iconName.length == 0) continue;              // 占位项没有图标
        UIImage *icon = [UIImage systemImageNamed:iconName];
        if (!icon) continue;
        [btn setImage:icon forState:UIControlStateNormal];
        UIView *iconView = btn.imageView;
        if (iconView && iconView.superview == btn) { [btn bringSubviewToFront:iconView]; }
    }
}

- (BOOL)allMenuIconsLoaded {
    for (UIView *view in self.menuStackView.arrangedSubviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)view;
        NSInteger idx = btn.tag;
        if (idx < 0 || idx >= (NSInteger)self.menuItems.count) continue;
        NSString *iconName = self.menuItems[idx][@"icon"];
        if (iconName.length == 0) continue;              // 占位项不计
        if (![btn imageForState:UIControlStateNormal]) return NO;
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
