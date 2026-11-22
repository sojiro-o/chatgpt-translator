//
//  EZLinkParser.h
//  Easydict
//
//  Created by tisfeng on 2023/2/25.
//  Copyright © 2023 izual. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// QuickTranslate Scheme: quicktranslate://
static NSString *const EZAppScheme = @"quicktranslate";
static NSString *const EZAppDebugScheme = @"quicktranslate-debug";

static NSString *const EZWriteKeyValueKey = @"writeKeyValue";
static NSString *const EZReadValueOfKeyKey = @"readValueOfKey";
static NSString *const EZSaveUserDefaultsDataToDownloadFolderKey = @"saveUserDefaultsDataToDownloadFolder";
static NSString *const EZResetUserDefaultsDataKey = @"resetUserDefaultsData";

static NSString *const EZQueryKey = @"query";

@interface EZSchemeParser : NSObject

// Check if text started with easydict://
- (BOOL)isEasydictScheme:(NSString *)text;

/// Open Easydict URL Schema.
- (void)openURLScheme:(NSString *)URLScheme completion:(void (^)(BOOL isSuccess, NSString *_Nullable returnValue, NSString *_Nullable actionKey))completion;

- (BOOL)isWriteActionKey:(NSString *)actionKey;

@end

NS_ASSUME_NONNULL_END
