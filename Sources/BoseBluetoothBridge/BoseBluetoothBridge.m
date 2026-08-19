#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#include "BoseBluetoothBridge.h"
#include <string.h>

@interface BoseRFCOMMDelegate : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic) BOOL closed;
@property(nonatomic) BOOL sdpDone;
@property(nonatomic) IOReturn sdpStatus;
@property(nonatomic) BOOL openDone;
@property(nonatomic) IOReturn openStatus;
@end

@implementation BoseRFCOMMDelegate
- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [NSMutableData data];
        _closed = NO;
        _sdpDone = NO;
        _sdpStatus = kIOReturnError;
        _openDone = NO;
        _openStatus = kIOReturnError;
    }
    return self;
}
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)channel
                     data:(void *)pointer
                   length:(size_t)length {
    (void)channel;
    if (pointer != NULL && length > 0) {
        [self.data appendBytes:pointer length:length];
    }
}
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)channel {
    (void)channel;
    self.closed = YES;
}
- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)channel
                            status:(IOReturn)status {
    (void)channel;
    self.openStatus = status;
    self.openDone = YES;
}
- (void)sdpQueryComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    (void)device;
    self.sdpStatus = status;
    self.sdpDone = YES;
}
@end

static void bose_set_error(char *error, uint16_t cap, NSString *message) {
    if (error == NULL || cap == 0) return;
    const char *text = message.UTF8String ?: "unknown error";
    size_t length = MIN(strlen(text), cap - 1);
    memcpy(error, text, length);
    error[length] = '\0';
}

static IOBluetoothDevice *bose_device(NSString *address) {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    if (device != nil) return device;
    NSString *hyphenated = [address stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    return [IOBluetoothDevice deviceWithAddressString:hyphenated];
}

static BOOL bose_has_complete_frames(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger position = 0;
    BOOL sawFrame = NO;
    while (position < data.length) {
        if (data.length - position < 4) return NO;
        NSUInteger frameLength = 4 + bytes[position + 3];
        if (data.length - position < frameLength) return NO;
        position += frameLength;
        sawFrame = YES;
    }
    return sawFrame;
}

static NSDate *bose_last_channel_close = nil;
static IOBluetoothRFCOMMChannel *bose_session_channel = nil;
static BoseRFCOMMDelegate *bose_session_delegate = nil;
static NSString *bose_session_address = nil;
static uint8_t bose_session_channel_id = 0;

static void bose_wait_for_channel_release(void) {
    if (bose_last_channel_close == nil) return;
    NSTimeInterval elapsed = -[bose_last_channel_close timeIntervalSinceNow];
    NSTimeInterval remaining = 0.65 - elapsed;
    if (remaining > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:remaining]];
    }
}

static void bose_close_channel(IOBluetoothRFCOMMChannel *channel,
                               BoseRFCOMMDelegate *delegate) {
    if (channel == nil) return;
    [channel closeChannel];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.35];
    while (!delegate.closed && channel.isOpen && [NSDate.date compare:deadline] == NSOrderedAscending) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    }
    bose_last_channel_close = NSDate.date;
}

static void bose_reset_session(void) {
    if (bose_session_channel != nil) {
        bose_close_channel(bose_session_channel, bose_session_delegate);
    }
    bose_session_channel = nil;
    bose_session_delegate = nil;
    bose_session_address = nil;
    bose_session_channel_id = 0;
}

static IOReturn bose_open_session(IOBluetoothDevice *device, NSString *address,
                                  uint8_t channel_id,
                                  IOBluetoothRFCOMMChannel **channel,
                                  BoseRFCOMMDelegate **delegate) {
    BOOL sameSession = bose_session_channel != nil && bose_session_channel.isOpen &&
        [bose_session_address caseInsensitiveCompare:address] == NSOrderedSame &&
        bose_session_channel_id == channel_id;
    if (sameSession) {
        [bose_session_delegate.data setLength:0];
        bose_session_delegate.closed = NO;
        *channel = bose_session_channel;
        *delegate = bose_session_delegate;
        return kIOReturnSuccess;
    }

    bose_reset_session();
    bose_wait_for_channel_release();
    if (!device.isConnected) {
        // On recent macOS versions the legacy IOBluetooth API may report
        // isConnected=NO while A2DP audio is actively playing. openConnection
        // can then return "connection exists" as a generic error. Treat this
        // only as a best-effort wake-up and always attempt RFCOMM afterwards.
        (void)[device openConnection];
    }
    BoseRFCOMMDelegate *newDelegate = [[BoseRFCOMMDelegate alloc] init];
    IOBluetoothRFCOMMChannel *newChannel = nil;
    IOReturn result = [device openRFCOMMChannelAsync:&newChannel
                                       withChannelID:channel_id
                                            delegate:newDelegate];
    if (result != kIOReturnSuccess) return result;

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
    while (!newDelegate.openDone && [NSDate.date compare:deadline] == NSOrderedAscending) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    }
    if (!newDelegate.openDone) return kIOReturnTimeout;
    if (newDelegate.openStatus != kIOReturnSuccess) return newDelegate.openStatus;
    if (newChannel == nil || !newChannel.isOpen) return kIOReturnNotOpen;
    [newChannel setDelegate:newDelegate];
    bose_session_channel = newChannel;
    bose_session_delegate = newDelegate;
    bose_session_address = [address copy];
    bose_session_channel_id = channel_id;
    *channel = newChannel;
    *delegate = newDelegate;
    return kIOReturnSuccess;
}

static IOBluetoothSDPUUID *bose_bmap_uuid(void) {
    static const uint8_t bytes[16] = {
        0x00, 0x00, 0x00, 0x00, 0xde, 0xca, 0xfa, 0xde,
        0xde, 0xca, 0xde, 0xaf, 0xde, 0xca, 0xca, 0xff
    };
    return [IOBluetoothSDPUUID uuidWithBytes:bytes length:sizeof(bytes)];
}

static int bose_channel_from_cached_services(IOBluetoothDevice *device) {
    IOBluetoothSDPServiceRecord *record = [device getServiceRecordForUUID:bose_bmap_uuid()];
    if (record == nil) return -1;
    BluetoothRFCOMMChannelID channel = 0;
    if ([record getRFCOMMChannelID:&channel] != kIOReturnSuccess || channel == 0) return -1;
    return channel;
}

int bose_resolve_rfcomm_channel(const char *address, uint8_t fallback_channel,
                                char *error, uint16_t error_cap) {
    @autoreleasepool {
        if (address == NULL) {
            bose_set_error(error, error_cap, @"invalid Bluetooth address");
            return -1;
        }
        IOBluetoothDevice *device = bose_device([NSString stringWithUTF8String:address]);
        if (device == nil) {
            bose_set_error(error, error_cap, @"Bluetooth device not found");
            return -2;
        }

        int cached = bose_channel_from_cached_services(device);
        if (cached > 0) return cached;

        BoseRFCOMMDelegate *delegate = [[BoseRFCOMMDelegate alloc] init];
        IOReturn started = [device performSDPQuery:delegate uuids:@[bose_bmap_uuid()]];
        if (started == kIOReturnSuccess) {
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
            while (!delegate.sdpDone && [NSDate.date compare:deadline] == NSOrderedAscending) {
                @autoreleasepool {
                    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                           beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                }
            }
            int discovered = bose_channel_from_cached_services(device);
            if (discovered > 0) return discovered;
        }

        // Some Bose firmware does not publish the vendor service while asleep.
        // Preserve the verified model fallback so a connected headset can still work.
        if (fallback_channel > 0) return fallback_channel;
        bose_set_error(error, error_cap, @"BMAP/RFCOMM service not found on the headset");
        return -3;
    }
}

int bose_list_paired_devices_json(char *output, uint32_t output_cap,
                                  char *error, uint16_t error_cap) {
    @autoreleasepool {
        if (output == NULL || output_cap == 0) {
            bose_set_error(error, error_cap, @"invalid output buffer");
            return -1;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) {
            NSString *name = device.name ?: @"Dispositivo sem nome";
            NSString *address = device.addressString ?: @"";
            if (address.length == 0) continue;
            [items addObject:@{
                @"name": name,
                @"address": address,
                @"connected": @(device.isConnected)
            }];
        }
        NSError *jsonError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:items options:0 error:&jsonError];
        if (json == nil) {
            bose_set_error(error, error_cap, jsonError.localizedDescription);
            return -2;
        }
        if (json.length + 1 > output_cap) {
            bose_set_error(error, error_cap, @"paired-device list exceeds output buffer");
            return -3;
        }
        memcpy(output, json.bytes, json.length);
        output[json.length] = '\0';
        return (int)json.length;
    }
}

int bose_rfcomm_send_recv(const char *address, uint8_t channel_id,
                          const uint8_t *request, uint16_t request_len,
                          uint8_t *response, uint16_t response_cap,
                          uint16_t *response_len, uint32_t timeout_ms,
                          char *error, uint16_t error_cap) {
    @autoreleasepool {
      @synchronized([BoseRFCOMMDelegate class]) {
        if (response_len != NULL) *response_len = 0;
        if (address == NULL || request == NULL || request_len == 0 ||
            response == NULL || response_len == NULL) {
            bose_set_error(error, error_cap, @"invalid RFCOMM arguments");
            return -1;
        }

        NSString *addressString = [NSString stringWithUTF8String:address];
        IOBluetoothDevice *device = bose_device(addressString);
        if (device == nil) {
            bose_set_error(error, error_cap,
                [NSString stringWithFormat:@"Bluetooth device not found: %@", addressString]);
            return -2;
        }

        BoseRFCOMMDelegate *delegate = nil;
        IOBluetoothRFCOMMChannel *channel = nil;
        IOReturn result = bose_open_session(device, addressString, channel_id, &channel, &delegate);
        if (result != kIOReturnSuccess || channel == nil) {
            NSString *message = [NSString stringWithFormat:
                @"macOS refused RFCOMM control channel %u (0x%08x); the audio connection may remain active",
                channel_id, result];
            bose_set_error(error, error_cap, message);
            return -3;
        }

        result = [channel writeSync:(void *)request length:request_len];
        if (result != kIOReturnSuccess) {
            bose_reset_session();
            bose_set_error(error, error_cap,
                [NSString stringWithFormat:@"falha ao escrever no RFCOMM (0x%08x)", result]);
            return -4;
        }

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout_ms / 1000.0];
        NSDate *idleDeadline = nil;
        NSUInteger previousLength = 0;
        while (!delegate.closed && [NSDate.date compare:deadline] == NSOrderedAscending) {
            @autoreleasepool {
                [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                       beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            NSUInteger length = delegate.data.length;
            if (length != previousLength) {
                previousLength = length;
                idleDeadline = [NSDate dateWithTimeIntervalSinceNow:0.15];
            }
            if (bose_has_complete_frames(delegate.data) && idleDeadline != nil &&
                [NSDate.date compare:idleDeadline] != NSOrderedAscending) break;
        }

        if (!bose_has_complete_frames(delegate.data)) {
            bose_reset_session();
            bose_set_error(error, error_cap, @"the headset did not respond before the timeout");
            return -5;
        }
        NSUInteger length = MIN(delegate.data.length, response_cap);
        memcpy(response, delegate.data.bytes, length);
        *response_len = (uint16_t)length;
        return 0;
      }
    }
}

int bose_rfcomm_multi_send_recv(const char *address, uint8_t channel_id,
                                const uint8_t *frames, const uint16_t *frame_lengths,
                                const uint32_t *delay_after_ms, int num_frames,
                                uint8_t *response, uint16_t response_cap,
                                uint16_t *response_len, uint32_t per_frame_timeout_ms,
                                char *error, uint16_t error_cap) {
    @autoreleasepool {
      @synchronized([BoseRFCOMMDelegate class]) {
        if (response_len != NULL) *response_len = 0;
        if (address == NULL || frames == NULL || frame_lengths == NULL ||
            delay_after_ms == NULL || num_frames <= 0 || response == NULL || response_len == NULL) {
            bose_set_error(error, error_cap, @"invalid RFCOMM batch arguments");
            return -1;
        }

        IOBluetoothDevice *device = bose_device([NSString stringWithUTF8String:address]);
        if (device == nil) {
            bose_set_error(error, error_cap, @"Bluetooth device not found");
            return -2;
        }
        BoseRFCOMMDelegate *delegate = nil;
        IOBluetoothRFCOMMChannel *channel = nil;
        NSString *addressString = [NSString stringWithUTF8String:address];
        IOReturn result = bose_open_session(device, addressString, channel_id, &channel, &delegate);
        if (result != kIOReturnSuccess || channel == nil) {
            NSString *message = [NSString stringWithFormat:
                @"macOS refused RFCOMM control channel %u (0x%08x); the audio connection may remain active",
                channel_id, result];
            bose_set_error(error, error_cap, message);
            return -3;
        }
        const uint8_t *frame = frames;
        for (int index = 0; index < num_frames; index++) {
            NSUInteger dataBefore = delegate.data.length;
            result = [channel writeSync:(void *)frame length:frame_lengths[index]];
            if (result != kIOReturnSuccess) {
                bose_reset_session();
                bose_set_error(error, error_cap,
                    [NSString stringWithFormat:@"failed to send command %d (0x%08x)", index + 1, result]);
                return -4;
            }
            frame += frame_lengths[index];

            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:per_frame_timeout_ms / 1000.0];
            NSDate *idleDeadline = nil;
            NSUInteger previousLength = dataBefore;
            BOOL complete = NO;
            while (!delegate.closed && [NSDate.date compare:deadline] == NSOrderedAscending) {
                [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                       beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                NSUInteger currentLength = delegate.data.length;
                if (currentLength != previousLength) {
                    previousLength = currentLength;
                    idleDeadline = [NSDate dateWithTimeIntervalSinceNow:0.15];
                }
                if (currentLength > dataBefore && idleDeadline != nil &&
                    [NSDate.date compare:idleDeadline] != NSOrderedAscending) {
                    NSData *newData = [delegate.data subdataWithRange:
                        NSMakeRange(dataBefore, currentLength - dataBefore)];
                    if (bose_has_complete_frames(newData)) { complete = YES; break; }
                }
            }
            if (!complete) {
                bose_reset_session();
                bose_set_error(error, error_cap,
                    [NSString stringWithFormat:@"the headset did not respond to command %d", index + 1]);
                return -5;
            }
            uint32_t delay = delay_after_ms[index];
            if (delay > 0) {
                [NSRunLoop.currentRunLoop runUntilDate:
                    [NSDate dateWithTimeIntervalSinceNow:delay / 1000.0]];
            }
        }

        NSUInteger length = MIN(delegate.data.length, response_cap);
        memcpy(response, delegate.data.bytes, length);
        *response_len = (uint16_t)length;
        return 0;
      }
    }
}
