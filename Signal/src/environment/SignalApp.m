//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalApp.h"
#import "ConversationViewController.h"
#import "HomeViewController.h"
#import "Signal-Swift.h"
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/Threading.h>

@interface SignalApp ()

@property (nonatomic) OWSWebRTCCallMessageHandler *callMessageHandler;
@property (nonatomic) CallService *callService;
@property (nonatomic) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic) OWSMessageFetcherJob *messageFetcherJob;
@property (nonatomic) NotificationsManager *notificationsManager;
@property (nonatomic) AccountManager *accountManager;

@end

#pragma mark -

@implementation SignalApp

+ (instancetype)sharedApp
{
    static SignalApp *sharedApp = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedApp = [[self alloc] initDefault];
    });
    return sharedApp;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark - Singletons

- (OWSWebRTCCallMessageHandler *)callMessageHandler
{
    @synchronized(self)
    {
        if (!_callMessageHandler) {
            _callMessageHandler =
                [[OWSWebRTCCallMessageHandler alloc] initWithAccountManager:self.accountManager
                                                                callService:self.callService
                                                              messageSender:Environment.current.messageSender];
        }
    }

    return _callMessageHandler;
}

- (CallService *)callService
{
    @synchronized(self)
    {
        if (!_callService) {
            OWSAssert(self.accountManager);
            OWSAssert(Environment.current.contactsManager);
            OWSAssert(Environment.current.messageSender);
            _callService = [[CallService alloc] initWithAccountManager:self.accountManager
                                                       contactsManager:Environment.current.contactsManager
                                                         messageSender:Environment.current.messageSender
                                                  notificationsAdapter:[OWSCallNotificationsAdapter new]];
        }
    }

    return _callService;
}

- (CallUIAdapter *)callUIAdapter
{
    return self.callService.callUIAdapter;
}

- (OutboundCallInitiator *)outboundCallInitiator
{
    @synchronized(self)
    {
        if (!_outboundCallInitiator) {
            OWSAssert(Environment.current.contactsManager);
            OWSAssert(Environment.current.contactsUpdater);
            _outboundCallInitiator =
                [[OutboundCallInitiator alloc] initWithContactsManager:Environment.current.contactsManager
                                                       contactsUpdater:Environment.current.contactsUpdater];
        }
    }

    return _outboundCallInitiator;
}

- (OWSMessageFetcherJob *)messageFetcherJob
{
    @synchronized(self)
    {
        if (!_messageFetcherJob) {
            _messageFetcherJob =
                [[OWSMessageFetcherJob alloc] initWithMessageReceiver:[OWSMessageReceiver sharedInstance]
                                                       networkManager:Environment.current.networkManager
                                                        signalService:[OWSSignalService sharedInstance]];
        }
    }
    return _messageFetcherJob;
}

- (NotificationsManager *)notificationsManager
{
    @synchronized(self)
    {
        if (!_notificationsManager) {
            _notificationsManager = [NotificationsManager new];
        }
    }

    return _notificationsManager;
}

- (AccountManager *)accountManager
{
    @synchronized(self)
    {
        if (!_accountManager) {
            _accountManager = [[AccountManager alloc] initWithTextSecureAccountManager:[TSAccountManager sharedInstance]
                                                                           preferences:Environment.current.preferences];
        }
    }

    return _accountManager;
}

#pragma mark - View Convenience Methods

- (void)presentConversationForRecipientId:(NSString *)recipientId
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:YES callOnViewAppearing:NO];
}

- (void)presentConversationForRecipientId:(NSString *)recipientId withCompose:(BOOL)compose
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:compose callOnViewAppearing:NO];
}

- (void)callRecipientId:(NSString *)recipientId
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:NO callOnViewAppearing:YES];
}

- (void)presentConversationForRecipientId:(NSString *)recipientId
                  keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
                      callOnViewAppearing:(BOOL)callOnViewAppearing
{
    // At most one.
    OWSAssert(!keyboardOnViewAppearing || !callOnViewAppearing);

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        [[TSStorageManager sharedManager].dbReadWriteConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
            }];
        [self presentConversationForThread:thread
                   keyboardOnViewAppearing:keyboardOnViewAppearing
                       callOnViewAppearing:callOnViewAppearing];
    });
}

- (void)presentConversationForThreadId:(NSString *)threadId
{
    OWSAssert(threadId.length > 0);

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    if (thread == nil) {
        OWSFail(@"%@ unable to find thread with id: %@", self.logTag, threadId);
        return;
    }

    [self presentConversationForThread:thread];
}

- (void)presentConversationForThread:(TSThread *)thread
{
    [self presentConversationForThread:thread withCompose:YES];
}

- (void)presentConversationForThread:(TSThread *)thread withCompose:(BOOL)compose
{
    [self presentConversationForThread:thread keyboardOnViewAppearing:compose callOnViewAppearing:NO];
}

- (void)presentConversationForThread:(TSThread *)thread
             keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
                 callOnViewAppearing:(BOOL)callOnViewAppearing
{
    // At most one.
    OWSAssert(!keyboardOnViewAppearing || !callOnViewAppearing);

    if (!thread) {
        OWSFail(@"%@ Can't present nil thread.", self.logTag);
        return;
    }

    DispatchMainThreadSafe(^{
        UIViewController *frontmostVC = [[UIApplication sharedApplication] frontmostViewController];

        if ([frontmostVC isKindOfClass:[ConversationViewController class]]) {
            ConversationViewController *conversationVC = (ConversationViewController *)frontmostVC;
            if ([conversationVC.thread.uniqueId isEqualToString:thread.uniqueId]) {
                [conversationVC popKeyBoard];
                return;
            }
        }

        [self.homeViewController presentThread:thread
                       keyboardOnViewAppearing:keyboardOnViewAppearing
                           callOnViewAppearing:callOnViewAppearing];
    });
}

#pragma mark - Methods

+ (void)resetAppData
{
    // This _should_ be wiped out below.
    DDLogError(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [OWSStorage resetAllStorage];
    [[OWSProfileManager sharedManager] resetProfileStorage];
    [Environment.preferences clear];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

    [DebugLogger.sharedLogger wipeLogs];
    exit(0);
}

@end
