//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUISyncMessages.h"
#import "DebugUIContacts.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AFNetworking/AFNetworking.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <Curve25519Kit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSSyncConfigurationMessage.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/OWSSyncGroupsMessage.h>
#import <SignalServiceKit/OWSSyncGroupsRequestMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISyncMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Sync Messages";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSArray<OWSTableItem *> *items = @[
        [OWSTableItem itemWithTitle:@"Send Contacts Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendContactsSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Groups Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendGroupSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Blocklist Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendBlockListSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Configuration Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendConfigurationSyncMessage];
                        }],
    ];
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (OWSMessageSender *)messageSender
{
    return [Environment current].messageSender;
}

+ (OWSContactsManager *)contactsManager
{
    return [Environment current].contactsManager;
}

+ (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager sharedManager];
}

+ (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

+ (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

+ (YapDatabaseConnection *)dbConnection
{
    return [TSStorageManager.sharedManager newDatabaseConnection];
}

+ (void)sendContactsSyncMessage
{
    OWSSyncContactsMessage *syncContactsMessage =
        [[OWSSyncContactsMessage alloc] initWithSignalAccounts:self.contactsManager.signalAccounts
                                               identityManager:self.identityManager
                                                profileManager:self.profileManager];
    DataSource *dataSource =
        [DataSourceValue dataSourceWithSyncMessage:[syncContactsMessage buildPlainTextAttachmentData]];
    [self.messageSender enqueueTemporaryAttachment:dataSource
        contentType:OWSMimeTypeApplicationOctetStream
        inMessage:syncContactsMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent Contacts response syncMessage.", self.logTag);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send Contacts response syncMessage with error: %@", self.logTag, error);
        }];
}

+ (void)sendGroupSyncMessage
{
    OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] init];
    __block DataSource *dataSource;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        dataSource = [DataSourceValue
            dataSourceWithSyncMessage:[syncGroupsMessage buildPlainTextAttachmentDataWithTransaction:transaction]];
    }];
    [self.messageSender enqueueTemporaryAttachment:dataSource
        contentType:OWSMimeTypeApplicationOctetStream
        inMessage:syncGroupsMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent Groups response syncMessage.", self.logTag);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send Groups response syncMessage with error: %@", self.logTag, error);
        }];
}

+ (void)sendBlockListSyncMessage
{
    [self.blockingManager syncBlockedPhoneNumbers];
}

+ (void)sendConfigurationSyncMessage
{
    __block BOOL areReadReceiptsEnabled;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        areReadReceiptsEnabled =
            [[OWSReadReceiptManager sharedManager] areReadReceiptsEnabledWithTransaction:transaction];
    }];

    OWSSyncConfigurationMessage *syncConfigurationMessage =
        [[OWSSyncConfigurationMessage alloc] initWithReadReceiptsEnabled:areReadReceiptsEnabled];
    [self.messageSender enqueueMessage:syncConfigurationMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent Configuration response syncMessage.", self.logTag);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send Configuration response syncMessage with error: %@", self.logTag, error);
        }];
}

@end

NS_ASSUME_NONNULL_END
