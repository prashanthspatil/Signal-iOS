//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *OWSVerificationStateToString(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return @"OWSVerificationStateDefault";
        case OWSVerificationStateVerified:
            return @"OWSVerificationStateVerified";
        case OWSVerificationStateNoLongerVerified:
            return @"OWSVerificationStateNoLongerVerified";
    }
}

OWSSignalServiceProtosVerifiedState OWSVerificationStateToProtoState(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return OWSSignalServiceProtosVerifiedStateDefault;
        case OWSVerificationStateVerified:
            return OWSSignalServiceProtosVerifiedStateVerified;
        case OWSVerificationStateNoLongerVerified:
            return OWSSignalServiceProtosVerifiedStateUnverified;
    }
}

@interface OWSRecipientIdentity ()

@property (atomic) OWSVerificationState verificationState;

@end

/**
 * Record for a recipients identity key and some meta data around it used to make trust decisions.
 *
 * NOTE: Instances of this class MUST only be retrieved/persisted via it's internal `dbConnection`,
 *       which makes some special accomodations to enforce consistency.
 */
@implementation OWSRecipientIdentity

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        if (![coder decodeObjectForKey:@"verificationState"]) {
            _verificationState = OWSVerificationStateDefault;
        }
    }

    return self;
}

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
                  verificationState:(OWSVerificationState)verificationState
{
    self = [super initWithUniqueId:recipientId];
    if (!self) {
        return self;
    }
    
    _recipientId = recipientId;
    _identityKey = identityKey;
    _isFirstKnownKey = isFirstKnownKey;
    _createdAt = createdAt;
    _verificationState = verificationState;

    return self;
}

- (void)updateWithVerificationState:(OWSVerificationState)verificationState
{
    // Ensure changes are persisted without clobbering any work done on another thread or instance.
    [self updateWithChangeBlock:^(OWSRecipientIdentity *_Nonnull obj) {
        obj.verificationState = verificationState;
    }];
}

- (void)updateWithChangeBlock:(void (^)(OWSRecipientIdentity *obj))changeBlock
{
    changeBlock(self);

    [[self class].dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
        if (latest == nil) {
            [self saveWithTransaction:transaction];
            return;
        }

        changeBlock(latest);
        [latest saveWithTransaction:transaction];
    }];
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return self.dbReadWriteConnection;
}

/**
 * Override to disable the object cache to better enforce transaction semantics on the store.
 * Note that it's still technically possible to access this collection from a different collection,
 * but that should be considered a bug.
 */
+ (YapDatabaseConnection *)dbReadWriteConnection
{
    static dispatch_once_t onceToken;
    static YapDatabaseConnection *sharedDBConnection;
    dispatch_once(&onceToken, ^{
        sharedDBConnection = [TSStorageManager sharedManager].newDatabaseConnection;
        sharedDBConnection.objectCacheEnabled = NO;
#if DEBUG
        sharedDBConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
    });

    return sharedDBConnection;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction.connection == [OWSRecipientIdentity dbReadWriteConnection]);

    [super saveWithTransaction:transaction];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction.connection == [OWSRecipientIdentity dbReadWriteConnection]);

    [super removeWithTransaction:transaction];
}

- (void)touchWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction.connection == [OWSRecipientIdentity dbReadWriteConnection]);

    [super touchWithTransaction:transaction];
}

+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction.connection == [OWSRecipientIdentity dbReadConnection]);

    return [super fetchObjectWithUniqueID:uniqueID transaction:transaction];
}

#pragma mark - debug

+ (void)printAllIdentities
{
    DDLogInfo(@"%@ ### All Recipient Identities ###", self.logTag);
    __block int count = 0;
    [self enumerateCollectionObjectsUsingBlock:^(id obj, BOOL *stop) {
        count++;
        if (![obj isKindOfClass:[self class]]) {
            OWSFail(@"%@ unexpected object in collection: %@", self.logTag, obj);
            return;
        }
        OWSRecipientIdentity *recipientIdentity = (OWSRecipientIdentity *)obj;

        DDLogInfo(@"%@ Identity %d: %@", self.logTag, count, recipientIdentity.debugDescription);
    }];
}

@end

NS_ASSUME_NONNULL_END
