//
//  UIKit+GlassSurface.h —— 液态玻璃外观助手(纯头文件,不新增 .m ⇒ 不改 CMake 源列表)
//
//  ★ CI 用 Xcode 15.4(iOS 17 SDK)⇒ UIGlassEffect(iOS 26)在 SDK 里无声明,
//    所以这里【不用编译期符号】,走 NSClassFromString + objc_msgSend 的运行时调用。
//  ★ 带探针:每次第一次解析材质时打一行日志,明确告知"玻璃生效"还是"回退常规材质",
//    免得再靠肉眼猜。日志 tag:[glass]
//
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AmeGlassRadius) {
    AmeGlassRadiusSmall = 13,
    AmeGlassRadiusCard  = 22,
    AmeGlassRadiusPanel = 26,
};

/// 统一材质:iOS 26+ 尝试液态玻璃;失败/旧系统回退 fallbackStyle。
static inline UIVisualEffect *AmeGlassEffect(UIBlurEffectStyle fallbackStyle) {
    static Class glassCls = Nil;
    static BOOL probed = NO;
    static BOOL glassOK = NO;
    static NSString *probeWhy = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        glassCls = NSClassFromString(@"UIGlassEffect");
        if (glassCls == Nil) {
            probeWhy = @"UIGlassEffect 类不存在(系统 < iOS 26 或未链接)";
        } else {
            SEL sel = @selector(effectWithStyle:);
            if ([glassCls respondsToSelector:sel]) {
                id g = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, sel, 0);
                if (g != nil && [g isKindOfClass:[UIVisualEffect class]]) {
                    glassOK = YES;
                    probeWhy = [NSString stringWithFormat:@"UIGlassEffect 生效(sdk=%s)", __VERSION__];
                } else {
                    probeWhy = @"UIGlassEffect.effectWithStyle: 返回空/类型不符 ⇒ 回退";
                }
            } else {
                probeWhy = @"UIGlassEffect 无 effectWithStyle: 方法 ⇒ 回退";
            }
        }
        NSLog(@"[glass] 材质解析:%@ ⇒ %@", glassOK ? @"玻璃" : @"常规材质(回退)", probeWhy ?: @"?");
        probed = YES;
    });
    (void)probed;

    if (glassOK && glassCls != Nil) {
        id g = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 0);
        if (g != nil && [g isKindOfClass:[UIVisualEffect class]]) {
            return (UIVisualEffect *)g;
        }
    }
    return [UIBlurEffect effectWithStyle:fallbackStyle];
}

/// 给 view 贴一层玻璃并设圆角(卡片/面板/列表行用)。返回承载视图,插在最底层。
static inline UIVisualEffectView * _Nullable AmeApplyGlassSurface(UIView *view, AmeGlassRadius radius) {
    if (view == nil) { return nil; }
    UIVisualEffect *effect = AmeGlassEffect(UIBlurEffectStyleSystemMaterial);
    if (effect == nil) { return nil; }
    view.backgroundColor = [UIColor clearColor];
    view.layer.cornerRadius = (CGFloat)radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.masksToBounds = YES;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:effect];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.userInteractionEnabled = NO;
    blur.layer.cornerRadius = (CGFloat)radius;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.layer.masksToBounds = YES;
    [view insertSubview:blur atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [blur.leadingAnchor  constraintEqualToAnchor:view.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [blur.topAnchor      constraintEqualToAnchor:view.topAnchor],
        [blur.bottomAnchor   constraintEqualToAnchor:view.bottomAnchor],
    ]];
    return blur;
}

/// 灵动岛/刘海安全区(横屏有岛那侧 ≈59pt、另一侧 0;iPad 两者皆 0)
static inline UIEdgeInsets AmeSafeInsets(UIView *view) {
    if (@available(iOS 11.0, *)) { return view.safeAreaInsets; }
    return UIEdgeInsetsZero;
}


/// ★ 玻璃质感(不依赖 iOS 26 SDK):给载体加"高光描边 + 上缘内高光"。
/// 为什么要它:真系统液态玻璃需要 iOS 26 SDK 构建(CI 现已换到 Xcode 26.3/iOS 26.2 SDK,
/// 那时系统会自动接管;此外这里作叠层仍然成立)。旧 SDK 下它是主要观感来源。
/// 幂等:用一个 tag 去重,重复调用不会叠加。
static inline void AmeAttachGlassRim(UIView *host, CGFloat radius) {
    if (host == nil) return;
    static const NSInteger kAmeRimTag = 0x4D52494D;   // 'MRIM'
    for (UIView *sub in host.subviews) {
        if (sub.tag == kAmeRimTag) { return; }        // 已加过 ⇒ 幂等
    }
    host.layer.cornerRadius = radius;
    host.layer.cornerCurve = kCACornerCurveContinuous;
    host.layer.masksToBounds = YES;

    // 玻璃描边:深浅色都给亮边
    UIColor *rim = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleDark)
            ? [UIColor colorWithWhite:1.0 alpha:0.22]
            : [UIColor colorWithWhite:1.0 alpha:0.75];
    }];
    host.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    host.layer.borderColor = rim.CGColor;

    // 上缘内高光:上亮下透的渐变(玻璃反光)
    UIView *shine = [[UIView alloc] initWithFrame:CGRectZero];
    shine.tag = kAmeRimTag;
    shine.userInteractionEnabled = NO;
    shine.translatesAutoresizingMaskIntoConstraints = NO;
    shine.backgroundColor = [UIColor clearColor];
    CAGradientLayer *g = [CAGradientLayer layer];
    g.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.20].CGColor,
                 (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
                 (id)[UIColor clearColor].CGColor];
    g.locations = @[@0.0, @0.28, @0.62];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint   = CGPointMake(0.5, 1.0);
    g.cornerRadius = radius;
    if (@available(iOS 13.0, *)) { g.cornerCurve = kCACornerCurveContinuous; }
    [shine.layer addSublayer:g];
    shine.clipsToBounds = YES;
    shine.layer.cornerRadius = radius;
    [host addSubview:shine];
    [NSLayoutConstraint activateConstraints:@[
        [shine.leadingAnchor  constraintEqualToAnchor:host.leadingAnchor],
        [shine.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [shine.topAnchor      constraintEqualToAnchor:host.topAnchor],
        [shine.bottomAnchor   constraintEqualToAnchor:host.bottomAnchor],
    ]];
    objc_setAssociatedObject(shine, "ameRimGradient", g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// 载体尺寸变化时刷新高光渐变(布局后调用;找不到就什么也不做)
static inline void AmeRefreshGlassRim(UIView *host) {
    if (host == nil) return;
    for (UIView *sub in host.subviews) {
        CAGradientLayer *g = (CAGradientLayer *)objc_getAssociatedObject(sub, "ameRimGradient");
        if (g != nil) { g.frame = sub.bounds; }
    }
}

NS_ASSUME_NONNULL_END
