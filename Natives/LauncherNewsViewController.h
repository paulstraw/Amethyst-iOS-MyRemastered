#import <UIKit/UIKit.h>

// MARK: - Tile Type & Size Enums

typedef NS_ENUM(NSInteger, HomeTileType) {
    HomeTileTypeProfile = 0,
    HomeTileTypeAnnouncement,
    HomeTileTypeVersionRelease,
    HomeTileTypeVersionSnapshot,
    HomeTileTypeNews,
    HomeTileTypeShortcut,
};

// ★ [SIZE4] 卡片尺寸从两档扩到四档,语义改为“小组件跨度”(列 × 行):
//   Small 1×1 · Wide 2×1 · Tall 1×2 · Large 2×2。
//   数值分配:Small=0 / Wide=1 沿用旧 Compact=0 / Full=1 ⇒ 旧 NSCoding / 字典 / NSUserDefaults 数据原样可用;
//   旧符号 HomeTileSizeCompact / HomeTileSizeFull 保留为同值别名,旧代码零改动。
typedef NS_ENUM(NSInteger, HomeTileSize) {
    HomeTileSizeSmall   = 0,   // 1×1(旧 HomeTileSizeCompact)
    HomeTileSizeWide    = 1,   // 2×1(旧 HomeTileSizeFull)
    HomeTileSizeTall    = 2,   // 1×2
    HomeTileSizeLarge   = 3,   // 2×2

    HomeTileSizeCompact = HomeTileSizeSmall,  // ★ [SIZE4] 旧符号别名(同值)
    HomeTileSizeFull    = HomeTileSizeWide,   // ★ [SIZE4] 旧符号别名(同值)
};

// ★ [SIZE4] 跨度 / 名称 helper(实现见 LauncherNewsViewController.m)。
NSInteger AmeTileSpanColumns(HomeTileSize size);    // 列跨度:Small/Tall⇒1,Wide/Large⇒2
NSInteger AmeTileSpanRows(HomeTileSize size);       // 行跨度:Small/Wide⇒1,Tall/Large⇒2
NSString *AmeTileSizeShortName(HomeTileSize size);  // "1×1"/"2×1"/"1×2"/"2×2"(几何,无需本地化)
NSString *AmeTileSizeDisplayName(HomeTileSize size);// 本地化名称(Half Width / Full Width / Tall / Large)

// MARK: - HomeTileConfig

@interface HomeTileConfig : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *tileId;
@property (nonatomic, assign) HomeTileType tileType;
@property (nonatomic, assign) HomeTileSize tileSize;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, copy) NSString *customTitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy) NSString *accentColorHex;
@property (nonatomic, copy) NSString *shortcutAction;  // For HomeTileTypeShortcut

+ (NSArray<HomeTileConfig *> *)defaultTileConfigs;
+ (NSArray<HomeTileConfig *> *)loadSavedConfigs;
+ (void)saveConfigs:(NSArray<HomeTileConfig *> *)configs;
- (UIColor *)accentColor;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

// MARK: - Shortcut Action Constants

extern NSString * const kShortcutActionMods;
extern NSString * const kShortcutActionShaders;
extern NSString * const kShortcutActionModpack;
extern NSString * const kShortcutActionBackground;
extern NSString * const kShortcutActionVersions;

// MARK: - LauncherNewsViewController

@interface LauncherNewsViewController : UIViewController

@end
