// Copyright 2018-present 650 Industries. All rights reserved.

#import <ABI45_0_0EXNotifications/ABI45_0_0EXPushTokenModule.h>
#import <ABI45_0_0EXNotifications/ABI45_0_0EXPushTokenManager.h>

#import <ABI45_0_0ExpoModulesCore/ABI45_0_0EXEventEmitterService.h>

static NSString * const onDevicePushTokenEventName = @"onDevicePushToken";

@interface ABI45_0_0EXPushTokenModule ()

@property (nonatomic, weak) id<ABI45_0_0EXPushTokenManager> pushTokenManager;

@property (nonatomic, assign) BOOL isListening;
@property (nonatomic, assign) BOOL isBeingObserved;
@property (nonatomic, assign) BOOL isSettlingPromise;

@property (nonatomic, weak) id<ABI45_0_0EXEventEmitterService> eventEmitter;

@property (nonatomic, strong) ABI45_0_0EXPromiseResolveBlock getDevicePushTokenResolver;
@property (nonatomic, strong) ABI45_0_0EXPromiseRejectBlock getDevicePushTokenRejecter;

@end

@implementation ABI45_0_0EXPushTokenModule

ABI45_0_0EX_EXPORT_MODULE(ExpoPushTokenManager);

# pragma mark - Exported methods

ABI45_0_0EX_EXPORT_METHOD_AS(getDevicePushTokenAsync,
                    getDevicePushTokenResolving:(ABI45_0_0EXPromiseResolveBlock)resolve rejecting:(ABI45_0_0EXPromiseRejectBlock)reject)
{
  if (_getDevicePushTokenRejecter) {
    reject(@"E_AWAIT_PROMISE", @"Another async call to this method is in progress. Await the first Promise.", nil);
    return;
  }

  _getDevicePushTokenResolver = resolve;
  _getDevicePushTokenRejecter = reject;
  [self setIsSettlingPromise:YES];

  dispatch_async(dispatch_get_main_queue(), ^{
    [[UIApplication sharedApplication] registerForRemoteNotifications];
  });
}

# pragma mark - ABI45_0_0EXModuleRegistryConsumer

- (void)setModuleRegistry:(ABI45_0_0EXModuleRegistry *)moduleRegistry
{
  _eventEmitter = [moduleRegistry getModuleImplementingProtocol:@protocol(ABI45_0_0EXEventEmitterService)];
  _pushTokenManager = [moduleRegistry getSingletonModuleForName:@"PushTokenManager"];
}

# pragma mark - ABI45_0_0EXEventEmitter

- (NSArray<NSString *> *)supportedEvents
{
  return @[onDevicePushTokenEventName];
}

- (void)startObserving
{
  [self setIsBeingObserved:YES];
}

- (void)stopObserving
{
  [self setIsBeingObserved:NO];
}

- (BOOL)shouldListen
{
  return _isBeingObserved || _isSettlingPromise;
}

- (void)updateListeningState
{
  if ([self shouldListen] && !_isListening) {
    [_pushTokenManager addListener:self];
    _isListening = YES;
  } else if (![self shouldListen] && _isListening) {
    [_pushTokenManager removeListener:self];
    _isListening = NO;
  }
}

# pragma mark - ABI45_0_0EXPushTokenListener

- (void)onDidRegisterWithDeviceToken:(NSData *)devicePushToken
{
  NSMutableString *stringToken = [NSMutableString string];
  const char *bytes = [devicePushToken bytes];
  for (int i = 0; i < [devicePushToken length]; i++) {
    [stringToken appendFormat:@"%02.2hhx", bytes[i]];
  }

  if (_getDevicePushTokenResolver) {
    _getDevicePushTokenResolver(stringToken);
    [self onGetDevicePushTokenPromiseSettled];
  }

  if (_isBeingObserved) {
    [_eventEmitter sendEventWithName:onDevicePushTokenEventName
                                body:@{ @"devicePushToken": stringToken }];
  }
}

- (void)onDidFailToRegisterWithError:(NSError *)error
{
  if (_getDevicePushTokenRejecter) {
    NSString *message = @"Notification registration failed: ";

    // A common error, localizedDescription may not be helpful.
    if (error.code == 3000 && [NSCocoaErrorDomain isEqualToString:error.domain]) {
      message = [message stringByAppendingString:@"\"Push Notifications\" capability hasn't been added to the app in current environment: "];
    }

    message = [message stringByAppendingFormat:@"%@", error.localizedDescription];
    _getDevicePushTokenRejecter(@"E_REGISTRATION_FAILED", message, error);
    [self onGetDevicePushTokenPromiseSettled];
  }
}

- (void)onGetDevicePushTokenPromiseSettled
{
  _getDevicePushTokenResolver = nil;
  _getDevicePushTokenRejecter = nil;
  [self setIsSettlingPromise:NO];
}

# pragma mark - Internal state

- (void)setIsBeingObserved:(BOOL)isBeingObserved
{
  _isBeingObserved = isBeingObserved;
  [self updateListeningState];
}

- (void)setIsSettlingPromise:(BOOL)isSettlingPromise
{
  _isSettlingPromise = isSettlingPromise;
  [self updateListeningState];
}

@end
