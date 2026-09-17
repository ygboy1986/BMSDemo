#import "SceneDelegate.h"
#import "UI/ViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) { return; }
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    ViewController *root = [[ViewController alloc] init];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:root];
    [self.window makeKeyAndVisible];
}

@end
