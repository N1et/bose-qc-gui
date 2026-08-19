#ifndef BoseBluetoothBridge_h
#define BoseBluetoothBridge_h

#include <stdint.h>

int bose_list_paired_devices_json(char *output, uint32_t output_cap,
                                  char *error, uint16_t error_cap);

int bose_resolve_rfcomm_channel(const char *address, uint8_t fallback_channel,
                                char *error, uint16_t error_cap);

int bose_rfcomm_send_recv(const char *address, uint8_t channel_id,
                          const uint8_t *request, uint16_t request_len,
                          uint8_t *response, uint16_t response_cap,
                          uint16_t *response_len, uint32_t timeout_ms,
                          char *error, uint16_t error_cap);

int bose_rfcomm_multi_send_recv(const char *address, uint8_t channel_id,
                                const uint8_t *frames, const uint16_t *frame_lengths,
                                const uint32_t *delay_after_ms, int num_frames,
                                uint8_t *response, uint16_t response_cap,
                                uint16_t *response_len, uint32_t per_frame_timeout_ms,
                                char *error, uint16_t error_cap);

#endif
