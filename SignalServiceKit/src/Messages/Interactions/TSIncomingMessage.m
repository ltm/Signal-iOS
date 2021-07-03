//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"
#import "NSNotificationCenter+OWS.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSIncomingMessage ()

@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, getter=wasViewed) BOOL viewed;

@property (nonatomic, nullable) NSNumber *serverTimestamp;
@property (nonatomic, readonly) NSUInteger incomingMessageSchemaVersion;

@end

#pragma mark -

const NSUInteger TSIncomingMessageSchemaVersion = 1;

@implementation TSIncomingMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_incomingMessageSchemaVersion < 1) {
        _authorPhoneNumber = [coder decodeObjectForKey:@"authorId"];
        if (_authorPhoneNumber == nil) {
            _authorPhoneNumber = [TSContactThread legacyContactPhoneNumberFromThreadId:self.uniqueThreadId];
        }
    }

    _incomingMessageSchemaVersion = TSIncomingMessageSchemaVersion;

    return self;
}

- (instancetype)initIncomingMessageWithBuilder:(TSIncomingMessageBuilder *)incomingMessageBuilder
{
    self = [super initMessageWithBuilder:incomingMessageBuilder];

    if (!self) {
        return self;
    }

    _authorPhoneNumber = incomingMessageBuilder.authorAddress.phoneNumber;
    _authorUUID = incomingMessageBuilder.authorAddress.uuidString;

    _sourceDeviceId = incomingMessageBuilder.sourceDeviceId;
    _read = NO;
    _serverTimestamp = incomingMessageBuilder.serverTimestamp;
    _serverDeliveryTimestamp = incomingMessageBuilder.serverDeliveryTimestamp;
    _serverGuid = incomingMessageBuilder.serverGuid;
    _wasReceivedByUD = incomingMessageBuilder.wasReceivedByUD;

    _incomingMessageSchemaVersion = TSIncomingMessageSchemaVersion;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
               authorPhoneNumber:(nullable NSString *)authorPhoneNumber
                      authorUUID:(nullable NSString *)authorUUID
                            read:(BOOL)read
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                      serverGuid:(nullable NSString *)serverGuid
                 serverTimestamp:(nullable NSNumber *)serverTimestamp
                  sourceDeviceId:(unsigned int)sourceDeviceId
                          viewed:(BOOL)viewed
                 wasReceivedByUD:(BOOL)wasReceivedByUD
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId
                     attachmentIds:attachmentIds
                              body:body
                        bodyRanges:bodyRanges
                      contactShare:contactShare
                   expireStartedAt:expireStartedAt
                         expiresAt:expiresAt
                  expiresInSeconds:expiresInSeconds
                isViewOnceComplete:isViewOnceComplete
                 isViewOnceMessage:isViewOnceMessage
                       linkPreview:linkPreview
                    messageSticker:messageSticker
                     quotedMessage:quotedMessage
      storedShouldStartExpireTimer:storedShouldStartExpireTimer
                wasRemotelyDeleted:wasRemotelyDeleted];

    if (!self) {
        return self;
    }

    _authorPhoneNumber = authorPhoneNumber;
    _authorUUID = authorUUID;
    _read = read;
    _serverDeliveryTimestamp = serverDeliveryTimestamp;
    _serverGuid = serverGuid;
    _serverTimestamp = serverTimestamp;
    _sourceDeviceId = sourceDeviceId;
    _viewed = viewed;
    _wasReceivedByUD = wasReceivedByUD;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_IncomingMessage;
}

#pragma mark - OWSReadTracking

// This method will be called after every insert and update, so it needs
// to be cheap.
- (BOOL)shouldStartExpireTimer
{
    if (self.hasPerConversationExpirationStarted) {
        // Expiration already started.
        return YES;
    } else if (!self.hasPerConversationExpiration) {
        return NO;
    } else {
        return self.wasRead && [super shouldStartExpireTimer];
    }
}

- (BOOL)shouldAffectUnreadCounts
{
    return YES;
}

- (void)debugonly_markAsReadNowWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // In various tests and debug UI we often want to make messages as already read.
    // We want to do this without triggering sending read receipts, so we pretend it was
    // read on a linked device.
    [self markAsReadAtTimestamp:[NSDate ows_millisecondTimeStamp]
                         thread:[self threadWithTransaction:transaction]
                   circumstance:OWSReceiptCircumstanceOnLinkedDevice
                    transaction:transaction];
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
                       thread:(TSThread *)thread
                 circumstance:(OWSReceiptCircumstance)circumstance
                  transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.read && readTimestamp >= self.expireStartedAt) {
        return;
    }

    NSTimeInterval secondsAgoRead = ((NSTimeInterval)[NSDate ows_millisecondTimeStamp] - (NSTimeInterval)readTimestamp) / 1000;
    if (!SSKDebugFlags.reduceLogChatter) {
        OWSLogDebug(@"marking uniqueId: %@  which has timestamp: %llu as read: %f seconds ago",
            self.uniqueId,
            self.timestamp,
            secondsAgoRead);
    }

    [self anyUpdateIncomingMessageWithTransaction:transaction
                                            block:^(TSIncomingMessage *message) {
                                                message.read = YES;
                                            }];

    // readTimestamp may be earlier than now, so backdate the expiration if necessary.
    [[OWSDisappearingMessagesJob shared] startAnyExpirationForMessage:self
                                                  expirationStartedAt:readTimestamp
                                                          transaction:transaction];

    [OWSReceiptManager.shared messageWasRead:self thread:thread circumstance:circumstance transaction:transaction];

    // We don't want to wait until the transaction finishes to cancel the notification,
    // because it's important it happens as part of "message processing" in the NSE.
    // Since we wait for message processing to finish with a promise on the main
    // queue, dispatching to main here *before* it's finished ensures that it always
    // happens before the processing promise completes.
    dispatch_async(dispatch_get_main_queue(),
        ^{ [SSKEnvironment.shared.notificationPresenter cancelNotificationsForMessageId:self.uniqueId]; });
}

- (void)markAsViewedAtTimestamp:(uint64_t)viewedTimestamp
                         thread:(TSThread *)thread
                   circumstance:(OWSReceiptCircumstance)circumstance
                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.viewed) {
        return;
    }

    NSTimeInterval secondsAgoViewed
        = ((NSTimeInterval)[NSDate ows_millisecondTimeStamp] - (NSTimeInterval)viewedTimestamp) / 1000;
    if (!SSKDebugFlags.reduceLogChatter) {
        OWSLogDebug(@"marking uniqueId: %@  which has timestamp: %llu as viewed: %f seconds ago",
            self.uniqueId,
            self.timestamp,
            secondsAgoViewed);
    }

    [self anyUpdateIncomingMessageWithTransaction:transaction
                                            block:^(TSIncomingMessage *message) { message.viewed = YES; }];

    [OWSReceiptManager.shared messageWasViewed:self thread:thread circumstance:circumstance transaction:transaction];
}

- (SignalServiceAddress *)authorAddress
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.authorUUID phoneNumber:self.authorPhoneNumber];
}

@end

NS_ASSUME_NONNULL_END
