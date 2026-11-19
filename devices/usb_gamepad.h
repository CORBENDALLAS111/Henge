/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HENGE_USB_GAMEPAD_H
#define HENGE_USB_GAMEPAD_H
#include <stdint.h>
#include <string.h>

#define HV_GP_REPORT_LEN 15
#define HV_GP_REPORTS 64
#define HV_GP_INTERVAL_MS 4
/* Generic USB HID: 16 buttons, eight-way hat with neutral, two sticks and
   two unipolar triggers. This is an input bridge, not a Bluetooth adapter. */
static const uint8_t hv_gp_descriptor[] = {
    0x05,0x01,0x09,0x05,0xa1,0x01,
    0x05,0x09,0x19,0x01,0x29,0x10,0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x10,0x81,0x02,
    0x05,0x01,0x09,0x39,0x15,0x00,0x25,0x07,0x35,0x00,0x46,0x3b,0x01,0x65,0x14,
    0x75,0x04,0x95,0x01,0x81,0x42,0x75,0x04,0x95,0x01,0x81,0x03,
    0x65,0x00,0x09,0x30,0x09,0x31,0x09,0x33,0x09,0x34,
    0x16,0x01,0x80,0x26,0xff,0x7f,0x36,0x01,0x80,0x46,0xff,0x7f,0x75,0x10,0x95,0x04,0x81,0x02,
    0x09,0x32,0x09,0x35,0x15,0x00,0x26,0xff,0x7f,0x35,0x00,0x46,0xff,0x7f,
    0x95,0x02,0x81,0x02,0xc0
};

static inline void hv_gp_word(uint8_t *out, int value, int low) {
    value = value < low ? low : value > 32767 ? 32767 : value;
    out[0] = (uint8_t)value; out[1] = (uint8_t)((uint16_t)value >> 8);
}
static inline void hv_gp_report(uint8_t *out, unsigned buttons, int hat, const int axes[6]) {
    out[0] = (uint8_t)buttons; out[1] = (uint8_t)(buttons >> 8);
    out[2] = hat >= 0 && hat < 8 ? (uint8_t)hat : 8;
    for (int i = 0; i < 6; i++) hv_gp_word(out + 3 + 2 * i, axes[i], i < 4 ? -32767 : 0);
}

typedef struct HvGamepadQueue {
    uint8_t reports[HV_GP_REPORTS][HV_GP_REPORT_LEN], state[HV_GP_REPORT_LEN];
    uint32_t head, tail;
    uint64_t delivered, overflows, last_report_ns;
    int blocked;
} HvGamepadQueue;

static inline void hv_gp_cancel(HvGamepadQueue *q) {
    memset(q->state, 0, sizeof q->state); q->state[2] = 8;
    q->head = 0; q->tail = 1; q->blocked = 0;
    memcpy(q->reports[0], q->state, HV_GP_REPORT_LEN);
}
static inline void hv_gp_reset(HvGamepadQueue *q) { memset(q, 0, sizeof *q); hv_gp_cancel(q); }

/* Button/hat transitions and each axis entering/leaving neutral or changing
   sign remain ordered. Motion within the same state may coalesce. */
static inline uint64_t hv_gp_edges(const uint8_t *s) {
    uint64_t key = s[0] | (uint64_t)s[1] << 8 | (uint64_t)s[2] << 16;
    for (int i = 0; i < 6; i++) {
        int value = s[3 + 2*i] | (int)s[4 + 2*i] << 8;
        if (i < 4) value = (int16_t)value;
        key |= (uint64_t)(value < 0 ? 1 : value > 0 ? 2 : 0) << (20 + 2*i);
    }
    return key;
}
static inline int hv_gp_enqueue(HvGamepadQueue *q, const uint8_t *sample) {
    uint64_t edge = hv_gp_edges(sample);
    if (q->blocked && edge != (8ull << 16)) return -1;
    q->blocked = 0;
    if (!memcmp(q->state, sample, HV_GP_REPORT_LEN)) return 0;
    uint32_t count = q->tail - q->head;
    if (count >= 2 && edge == hv_gp_edges(q->reports[(q->tail - 1) % HV_GP_REPORTS]) &&
        edge == hv_gp_edges(q->reports[(q->tail - 2) % HV_GP_REPORTS])) {
        memcpy(q->reports[(q->tail - 1) % HV_GP_REPORTS], sample, HV_GP_REPORT_LEN);
    } else if (count == HV_GP_REPORTS) {
        hv_gp_cancel(q); q->blocked = 1; q->overflows++;
        return -1;
    } else memcpy(q->reports[q->tail++ % HV_GP_REPORTS], sample, HV_GP_REPORT_LEN);
    memcpy(q->state, sample, HV_GP_REPORT_LEN);
    return 0;
}
#endif
