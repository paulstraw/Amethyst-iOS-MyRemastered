//
//  UIKit+GlassSurface.h —— 液态玻璃外观助手(纯头文件,不新增 .m ⇒ 不改 CMake 源列表)
//
//  ★ 关键:CI 用的是 Xcode 15.4(iOS 17 SDK)⇒ UIGlassEffect(iOS 26)在该 SDK 里【没有声明】。
//    因此这里【不用编译期符号】,改用 NSClassFromString + objc_msgSend 的运行时调用:
//      · 用旧 SDK 也能编译通过;
//      · 真机是 iOS 26/27 ⇒ 运行时能找到 UIGlassEffect ⇒ 玻璃真实生效;
//      · 系统更旧/类不存在 ⇒ 回退到原来的系统材质,行为不变。
//  颜色/材质全走系统语义 ⇒ 深浅色自动正确,不写死任何颜色。
//
#import <UIKit/UIKit.h>
#import <objc/message.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AmeGlassRadius) {
    AmeGlassRadiusSmall = 13,
    AmeGlassRadiusCard  = 22,
    AmeGlassRadiusPanel = 26,
};

/// 统一材质:iOS 26+ = 液态玻璃;旧系统 = fallbackStyle 对应的系统材质。
static inline UIVisualEffect *AmeGlassEffect(UIBlurEffectStyle fallbackStyle) {
    static Class glassCls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        glassCls = NSClassFromString(@"UIGlassEffect");   // iOS 26 才有;旧系统为 Nil
    });
    if (glassCls != Nil && [glassCls respondsToSelector:@selector(effectWithStyle:)]) {
        // UIGlassEffectStyleRegular == 0;用 objc_msgSend 调用以避免编译期依赖该符号
        id glass = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 0);
        if (glass != nil && [glass isKindOfClass:[UIVisualEffect class]]) {
            return (UIVisualEffect *)glass;
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

/// 灵动岛/刘海安全区:横屏有岛那侧 ≈59pt、另一侧 0;竖屏顶部由系统 top 决定。
static inline UIEdgeInsets AmeSafeInsets(UIView *view) {
    if (@available(iOS 11.0, *)) { return view.safeAreaInsets; }
    return UIEdgeInsetsZero;
}

NS_ASSUME_NONNULL_END
