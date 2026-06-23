#import <React/RCTBridgeModule.h>

// Exposes the Swift @objc(LuxSession) module + its methods to the RN bridge.
@interface RCT_EXTERN_MODULE (LuxSession, NSObject)

RCT_EXTERN_METHOD(setSession
                  : (NSString *)token refreshToken
                  : (NSString *)refreshToken expiresAt
                  : (double)expiresAt address
                  : (NSString *)address chain
                  : (NSString *)chain)

RCT_EXTERN_METHOD(getSession
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(close)

@end
