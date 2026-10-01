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

NS_ASSUME_NONNULL_END
