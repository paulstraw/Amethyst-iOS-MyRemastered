//
//  UIKit+GlassSurface.h —— 液态玻璃外观助手(纯头文件,不新增 .m ⇒ 不改 CMake 源列表)
//
//  背景:本仓库 Info.plist 里 UIDesignRequiresCompatibility = true,App 沿用旧外观,
//  系统不会自动把材质换成 iOS 26 的 Liquid Glass ⇒ 这里手动提供一层极薄封装:
//  iOS 26+ 用 UIGlassEffect,旧系统回退到原有系统材质。颜色/材质全走系统语义 ⇒ 深浅色自动。
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AmeGlassRadius) {
    AmeGlassRadiusSmall = 13,
    AmeGlassRadiusCard  = 22,
    AmeGlassRadiusPanel = 26,
};

/// 统一材质:iOS 26+ = 液态玻璃;旧系统 = 原来的系统材质(fallbackStyle)。
/// 真机上想要"App 整体变液态玻璃"时,把各处 effectWithStyle: 换成它即可。
static inline UIVisualEffect *AmeGlassEffect(UIBlurEffectStyle fallbackStyle) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.tintColor = nil;      // 跟随系统,不写死颜色
        return glass;
    }
    return [UIBlurEffect effectWithStyle:fallbackStyle];
}

/// 给 view 贴一层玻璃并设圆角(用于卡片/面板/列表行)。返回承载视图,插在最底层。
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

/// 灵动岛/刘海安全区:横屏时有岛那侧 ≈59pt、另一侧 0;竖屏顶部由系统给的 top 决定。
/// 布局请锚到 safeAreaLayoutGuide,并在 viewSafeAreaInsetsDidChange 里重排(岛会随转屏换边)。
static inline UIEdgeInsets AmeSafeInsets(UIView *view) {
    if (@available(iOS 11.0, *)) { return view.safeAreaInsets; }
    return UIEdgeInsetsZero;
}

NS_ASSUME_NONNULL_END
