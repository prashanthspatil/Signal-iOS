//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (Subclass)

- (void)runSyncRegistrations;
- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion;

- (BOOL)areAsyncRegistrationsComplete;
- (BOOL)areSyncRegistrationsComplete;

- (NSString *)dbPath;

- (void)resetStorage;

@end

NS_ASSUME_NONNULL_END
