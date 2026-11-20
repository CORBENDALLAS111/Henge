/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HENGE_ABSOLUTE_PEN_H
#define HENGE_ABSOLUTE_PEN_H
#include <stdint.h>

/* Standard HID Pen/Stylus, independent of the relative VirtIO mouse. */
#define HV_PEN_REPORT_LEN 14 /* report ID + 13-byte digitizer payload */
#define HV_PEN_MOUSE_REPORT_LEN 4
#define HV_PEN_REPORT_ID 1
#define HV_PEN_MOUSE_REPORT_ID 2
#define HV_PEN_REPORTS 128
#define HV_PEN_INTERVAL_MS 1
#define HV_PEN_EDGE_DWELL_MS 50 /* preserve desktop click edges across guest sampling */
#define HV_PEN_POSITION_DWELL_MS 16 /* let a preceding absolute position reach the guest */
#define HV_PEN_DESKTOP_LEFT 32
#define HV_PEN_DESKTOP_RIGHT 64
#define HV_PEN_DESKTOP_UP 128
#define HV_PEN_DESKTOP_AT_CURSOR 256 /* trackpad click: do not reposition */
#define HV_PEN_DESKTOP_MASK (HV_PEN_DESKTOP_LEFT | HV_PEN_DESKTOP_RIGHT | HV_PEN_DESKTOP_UP)
#define HV_PEN_TIP 1
#define HV_PEN_BARREL 2
#define HV_PEN_RANGE 4
#define HV_PEN_INVERT 8
#define HV_PEN_PRIMARY 16 /* mirror tip into Button 1 for collection-dispatch drivers */
static const uint8_t hv_pen_descriptor[] = {
    0x05,0x0d, 0x09,0x02, 0xa1,0x01, 0x85,HV_PEN_REPORT_ID, 0x09,0x20, 0xa1,0x00,
    0x09,0x42, 0x09,0x44, 0x09,0x32, 0x09,0x3c,
    0x15,0x00, 0x25,0x01, 0x75,0x01, 0x95,0x04, 0x81,0x02,
    /* Tip Switch describes digitizer contact. Collection dispatch keeps it
       separate from ButtonMask, so also advertise the primary desktop button. */
    0x05,0x09, 0x09,0x01, 0x75,0x01, 0x95,0x01, 0x81,0x02,
    0x75,0x03, 0x95,0x01, 0x81,0x03,
    0x05,0x01, 0x09,0x30, 0x09,0x31,
    0x15,0x00, 0x26,0xff,0x7f, 0x35,0x00, 0x46,0xff,0x7f,
    0x75,0x10, 0x95,0x02, 0x81,0x02,
    0x05,0x0d, 0x09,0x30, 0x26,0xff,0x0f, 0x46,0xff,0x0f,
    0x95,0x01, 0x81,0x02,
    0x09,0x3d, 0x09,0x3e, 0x16,0xd8,0xdc, 0x26,0x28,0x23,
    0x36,0xa6,0xff, 0x46,0x5a,0x00, 0x65,0x14, 0x95,0x02, 0x81,0x02,
    0x09,0x41, 0x15,0x00, 0x26,0xa0,0x8c, 0x35,0x00, 0x46,0x68,0x01,
    0x95,0x01, 0x81,0x02, 0xc0,0xc0,
    /* Independent desktop buttons. Zero relative motion leaves the absolute
       position alone. A separate report ID prevents a hover/button=0 tablet
       event from accompanying and undoing a stationary desktop button edge. */
    0x05,0x01, 0x09,0x02, 0xa1,0x01, 0x85,HV_PEN_MOUSE_REPORT_ID,
    0x09,0x01, 0xa1,0x00,
    0x05,0x09, 0x19,0x01, 0x29,0x03,
    0x15,0x00, 0x25,0x01, 0x35,0x00, 0x45,0x01, 0x65,0x00,
    0x75,0x01, 0x95,0x03, 0x81,0x02,
    0x75,0x05, 0x95,0x01, 0x81,0x03,
    0x05,0x01, 0x09,0x30, 0x09,0x31,
    0x15,0x81, 0x25,0x7f, 0x35,0x00, 0x45,0x00,
    0x75,0x08, 0x95,0x02, 0x81,0x06, 0xc0,0xc0
};
static inline int hv_pen_clamp(int v, int low, int high) { return v < low ? low : v > high ? high : v; }
static inline void hv_pen_u16(uint8_t *p, int v) { p[0] = (uint8_t)v; p[1] = (uint8_t)((uint16_t)v >> 8); }
static inline void hv_pen_report(uint8_t *r, int x, int y, int pressure, int tilt_x, int tilt_y, int twist, int flags) {
    r[0] = HV_PEN_REPORT_ID;
    r++;
    flags &= 15;
    if (!(flags & HV_PEN_RANGE)) flags = 0;
    r[0] = (uint8_t)(flags | (flags & HV_PEN_TIP ? HV_PEN_PRIMARY : 0));
    hv_pen_u16(r + 1, hv_pen_clamp(x, 0, 32767));
    hv_pen_u16(r + 3, hv_pen_clamp(y, 0, 32767));
    hv_pen_u16(r + 5, flags & HV_PEN_TIP ? hv_pen_clamp(pressure, 1, 4095) : 0);
    hv_pen_u16(r + 7, hv_pen_clamp(tilt_x, -9000, 9000));
    hv_pen_u16(r + 9, hv_pen_clamp(tilt_y, -9000, 9000));
    hv_pen_u16(r + 11, hv_pen_clamp(twist, 0, 35999));
}
static inline void hv_pen_mouse_report(uint8_t *r, unsigned buttons) {
    for (unsigned i = 0; i < HV_PEN_REPORT_LEN; i++) r[i] = 0;
    r[0] = HV_PEN_MOUSE_REPORT_ID;
    r[1] = (uint8_t)(buttons & 7);
}
static inline unsigned hv_pen_report_length(const uint8_t *r) {
    return r[0] == HV_PEN_MOUSE_REPORT_ID ? HV_PEN_MOUSE_REPORT_LEN : HV_PEN_REPORT_LEN;
}
static inline unsigned hv_pen_report_key(const uint8_t *r) {
    return (unsigned)r[0] << 8 | r[1];
}
#endif
