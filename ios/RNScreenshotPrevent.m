#import "RNScreenshotPrevent.h"
#import "UIImage+ImageEffects.h"

@implementation RNScreenshotPrevent {
    BOOL hasListeners;
    BOOL enabled;
    UIImageView *obfuscatingView;
    UITextField *secureField;

}

RCT_EXPORT_MODULE();
- (NSArray<NSString *> *)supportedEvents {
    return @[@"userDidTakeScreenshot"];
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

#pragma mark - Lifecycle

- (void) startObserving {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    // handle inactive event
    [center addObserver:self selector:@selector(handleAppStateResignActive)
                            name:UIApplicationWillResignActiveNotification
                            object:nil];
    // handle active event
    [center addObserver:self selector:@selector(handleAppStateActive)
                            name:UIApplicationDidBecomeActiveNotification
                            object:nil];
    // handle screenshot taken event
    [center addObserver:self selector:@selector(handleAppScreenshotNotification)
                            name:UIApplicationUserDidTakeScreenshotNotification
                            object:nil];

    hasListeners = TRUE;
}

- (void) stopObserving {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    hasListeners = FALSE;
}

#pragma mark - App Notification Methods

/** displays blurry view when app becomes inactive */
- (void)handleAppStateResignActive {
    if (self->enabled) {
        UIWindow    *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIImageView *blurredScreenImageView = [[UIImageView alloc] initWithFrame:keyWindow.bounds];

        UIGraphicsBeginImageContext(keyWindow.bounds.size);
        [keyWindow drawViewHierarchyInRect:keyWindow.frame afterScreenUpdates:NO];
        UIImage *viewImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        blurredScreenImageView.image = [viewImage applyLightEffect];

        self->obfuscatingView = blurredScreenImageView;
        [keyWindow addSubview:self->obfuscatingView];
    }
}

/** removes blurry view when app becomes active */
- (void)handleAppStateActive {
    if  (self->obfuscatingView) {
        [UIView animateWithDuration: 0.3
                         animations: ^ {
                             self->obfuscatingView.alpha = 0;
                         }
                         completion: ^(BOOL finished) {
                             [self->obfuscatingView removeFromSuperview];
                             self->obfuscatingView = nil;
                         }
         ];
    }
}

/** sends screenshot taken event into app */
- (void) handleAppScreenshotNotification {
    // only send events when we have some listeners
    if(hasListeners) {
        [self sendEventWithName:@"userDidTakeScreenshot" body:nil];
    }
}

+(BOOL) requiresMainQueueSetup
{
  return YES;
}

CGSize CGSizeAspectFit(const CGSize aspectRatio, const CGSize boundingSize)
{
    CGSize aspectFitSize = CGSizeMake(boundingSize.width, boundingSize.height);
    float mW = boundingSize.width / aspectRatio.width;
    float mH = boundingSize.height / aspectRatio.height;
    if( mH < mW )
        aspectFitSize.width = mH * aspectRatio.width;
    else if( mW < mH )
        aspectFitSize.height = mW * aspectRatio.height;
    return aspectFitSize;
}

CGSize CGSizeAspectFill(const CGSize aspectRatio, const CGSize minimumSize)
{
    CGSize aspectFillSize = CGSizeMake(minimumSize.width, minimumSize.height);
    float mW = minimumSize.width / aspectRatio.width;
    float mH = minimumSize.height / aspectRatio.height;
    if( mH > mW )
        aspectFillSize.width = mH * aspectRatio.width;
    else if( mW > mH )
        aspectFillSize.height = mW * aspectRatio.height;
    return aspectFillSize;
}


/**
 * creates secure text field inside rootView of the app
 * taken from https://stackoverflow.com/questions/18680028/prevent-screen-capture-in-an-ios-app
 * 
 * converted to ObjC and modified to get it working with RCT
 */
-(void) addSecureTextFieldToView:(UIView *) view :(NSString *) imagePath {
    
    UIView *rootView = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    
    
    // fixes safe-area
    secureField = [[UITextField alloc] initWithFrame:rootView.frame];
    secureField.secureTextEntry = TRUE;
    secureField.userInteractionEnabled = FALSE;

    if (imagePath && ![imagePath isEqualToString:@""]) {
        UIView * imgView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, rootView.frame.size.width, rootView.frame.size.height)];
        NSURL *url = [NSURL URLWithString:imagePath];
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = [[UIImage alloc] initWithData:data];
        
        CGSize sizeBeingScaledTo = CGSizeAspectFill(img.size, imgView.frame.size);
        
        // redraw the image to fit the screen size
        UIGraphicsBeginImageContextWithOptions(imgView.frame.size, NO, 0.f);
        
        float offsetX = (imgView.frame.size.width - sizeBeingScaledTo.width) / 2;
        float offsety = (imgView.frame.size.height - sizeBeingScaledTo.height) / 2;
        
        
        [img drawInRect:CGRectMake(offsetX, offsety, sizeBeingScaledTo.width, sizeBeingScaledTo.height)];
        UIImage * resultImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        secureField.backgroundColor = [UIColor colorWithPatternImage:resultImage];
    }

    [view sendSubviewToBack:secureField];
    [view addSubview:secureField];
    [view.layer.superlayer addSublayer:secureField.layer];
    [[secureField.layer.sublayers lastObject] addSublayer:view.layer];
}

// TODO: not working now, fix crash on _UITextFieldCanvasView contenttViewInvalidated: unrecognized selector sent to instance
-(void) removeSecureTextFieldFromView:(UIView *) view {
    for(UITextField *subview in view.subviews){
        if([subview isMemberOfClass:[UITextField class]]) {
            if(subview.secureTextEntry == TRUE) {
                [subview removeFromSuperview];
                subview.secureTextEntry = FALSE;
                secureField.userInteractionEnabled = TRUE;
            }
        }
    }
}

#pragma mark - Public API

RCT_EXPORT_METHOD(enabled:(BOOL) _enable) {
    self->enabled = _enable;
}

/** adds secure textfield view */
RCT_EXPORT_METHOD(enableSecureView: (NSString *)imagePath) {
    [self enabled:YES];
    if(secureField.secureTextEntry == false) {
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        for(UIView *subview in view.subviews) {
            [self addSecureTextFieldToView:subview :imagePath];
        }
    }
}


/** removes secure textfield from the view */
RCT_EXPORT_METHOD(disableSecureView) {
    NSLog(@"[RNScreenshotPrevent] disableSecureView called.");

    if (secureField != nil) {
        NSLog(@"[RNScreenshotPrevent] Found secureField, disabling secure entry.");
        secureField.secureTextEntry = NO;

        if (secureField.superview) {
            NSLog(@"[RNScreenshotPrevent] Removing secureField from its superview.");
            [secureField removeFromSuperview];
        } else {
            NSLog(@"[RNScreenshotPrevent] secureField has no superview.");
        }

        secureField = nil;
        NSLog(@"[RNScreenshotPrevent] secureField reference cleared.");
    } else {
        NSLog(@"[RNScreenshotPrevent] No secureField found, nothing to disable.");
    }

    UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    if (view == nil) {
        NSLog(@"[RNScreenshotPrevent] Root view is nil, cannot remove secure text fields.");
        return;
    }

    NSLog(@"[RNScreenshotPrevent] Checking subviews for secure fields to remove.");
    int removedFields = 0;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UITextField class]]) {
            NSLog(@"[RNScreenshotPrevent] Removing a UITextField from subviews.");
            [self removeSecureTextFieldFromView:subview];
            removedFields++;
        }
    }
    
    NSLog(@"[RNScreenshotPrevent] Secure view disabled and removed. Total fields removed: %d", removedFields);
}



@end
