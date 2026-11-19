/* Real USB controller/report code; only guest RAM and PCI interrupt wiring are
   substituted. Portable so transport/cancellation tests also run under ASan. */
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <stdint.h>
#include <assert.h>
static uint64_t input_time_ns = 1000000000;
static int input_test_clock(clockid_t clock, struct timespec *ts) {
    assert(clock == CLOCK_MONOTONIC);
    ts->tv_sec = (time_t)(input_time_ns / 1000000000);
    ts->tv_nsec = (long)(input_time_ns % 1000000000);
    return 0;
}
#define clock_gettime input_test_clock
#include "../devices/xhci.c"
#undef clock_gettime

static _Alignas(16) uint8_t guest[65536];
void *hv_phys_ptr(HvMachine *m, uint64_t pa, uint64_t n) { (void)m; return pa <= sizeof guest && n <= sizeof guest - pa ? guest + pa : NULL; }
int hv_phys_read(HvMachine *m, uint64_t pa, void *out, unsigned n) { void *p = hv_phys_ptr(m, pa, n); if (!p) return -1; memcpy(out, p, n); return 0; }
int hv_phys_write(HvMachine *m, uint64_t pa, const void *in, unsigned n) { void *p = hv_phys_ptr(m, pa, n); if (!p) return -1; memcpy(p, in, n); return 0; }
void hv_machine_wake(HvMachine *m) { (void)m; }
void hv_pci_set_intx(HvPciDev *d, int level) { (void)d; (void)level; }
void hv_pci_init(HvPciDev *d, uint16_t v, uint16_t p, uint32_t c, uint16_t sv, uint16_t sp) { (void)d; (void)v; (void)p; (void)c; (void)sv; (void)sp; }
void hv_pci_add_bar(HvPciDev *d, int b, uint64_t n, int wide) { (void)d; (void)b; (void)n; (void)wide; }
int hv_pcie_attach(HvPcie *p, HvPciDev *d) { (void)p; (void)d; return 0; }
static unsigned u16(const uint8_t *p) { return p[0] | (unsigned)p[1] << 8; }
static const uint8_t *received(unsigned index) { return guest + 0x4000 + 16 * index; }
static void drain_gamepad(HvXhci *x) {
    unsigned guard = HV_GP_REPORTS + 1;
    while (x->gamepad.head != x->gamepad.tail && guard--) {
        input_time_ns += HV_GP_INTERVAL_MS * 1000000ull;
        run_ep_in(x, 4);
    }
    assert(x->gamepad.head == x->gamepad.tail);
}
int main(void) {
    HvXhci *x = hv_xhci_create(NULL, NULL); assert(x);
    int axes[6] = {0};
    assert(!hv_xhci_gamepad_ready(x) && hv_xhci_gamepad(x, 1, 8, axes) == -1);
    assert(HV_XHCI_PORTS == 4 && ((bar_read(&x->pci, 0, XECP + 8, 4) >> 8) & 255) == 4);
    x->slots[4].dev = 3; x->slots[4].configured = 1;
    x->slots[4].ep_running[3] = 1;
    x->slots[4].ep[3] = (HvXhciRing){0x1000, 1};
    for (unsigned i = 0; i < 128; i++) {
        uint32_t trb[] = {0x4000 + i * 16, 0, HV_GP_REPORT_LEN, TRB_NORMAL << 10 | 1};
        memcpy(guest + 0x1000 + i * 16, trb, sizeof trb);
    }
    run_ep_in(x, 4);
    assert(hv_xhci_gamepad_ready(x) && x->gamepad.delivered == 1 && received(0)[2] == 8);
    uint8_t setup[] = {0x81, 6, 0, 0x22, 0, 0, 255, 0}, out[256];
    assert(control(x, 4, setup, out, sizeof out) == sizeof hv_gp_descriptor);
    assert(!memcmp(out, hv_gp_descriptor, sizeof hv_gp_descriptor));
    assert(!hv_xhci_gamepad(x, 1, 8, axes));
    for (int i = 1; i <= 1000; i++) { axes[0] = i; assert(!hv_xhci_gamepad(x, 1, 8, axes)); }
    axes[0] = 0; assert(!hv_xhci_gamepad(x, 0, 8, axes));
    assert(x->gamepad.tail - x->gamepad.head == 4);
    run_ep_in(x, 4); assert(x->gamepad.delivered == 1);
    input_time_ns += HV_GP_INTERVAL_MS * 1000000ull - 1;
    run_ep_in(x, 4); assert(x->gamepad.delivered == 1);
    input_time_ns++; run_ep_in(x, 4); assert(x->gamepad.delivered == 2);
    drain_gamepad(x);
    assert(x->gamepad.delivered == 5);
    assert(received(1)[0] == 1 && u16(received(1)+3) == 0);
    assert(u16(received(2)+3) == 1 && u16(received(3)+3) == 1000 && received(4)[0] == 0);
    int large[6] = {50000, -50000, 1, -1, -4, 50000};
    assert(!hv_xhci_gamepad(x, 0xffff, 50, large));
    uint8_t get[] = {0xa1, 1, 0, 1, 0, 0, HV_GP_REPORT_LEN, 0};
    assert(control(x, 4, get, out, sizeof out) == HV_GP_REPORT_LEN);
    assert(u16(out) == 65535 && out[2] == 8 && u16(out+3) == 32767 && (int16_t)u16(out+5) == -32767);
    assert(u16(out+11) == 0 && u16(out+13) == 32767);
    hv_xhci_gamepad_cancel(x); drain_gamepad(x);
    const uint8_t *neutral = received((unsigned)x->gamepad.delivered-1);
    assert(!u16(neutral) && neutral[2] == 8 && !u16(neutral+3));
    for (int i = 0; i < HV_GP_REPORTS; i++) assert(!hv_xhci_gamepad(x, i%2 ? 2 : 1, 8, axes));
    assert(hv_xhci_gamepad(x, 4, 8, axes) == -1 && x->gamepad.overflows == 1);
    assert(x->gamepad.tail - x->gamepad.head == 1 && x->gamepad.reports[0][0] == 0);
    assert(hv_xhci_gamepad(x, 1, 8, axes) == -1);
    assert(!hv_xhci_gamepad(x, 0, 8, axes));
    drain_gamepad(x);
    gamepad_pause(x); assert(!hv_xhci_gamepad_ready(x));
    assert(hv_xhci_gamepad(x, 1, 8, axes) == -1);
    uint64_t at = x->slots[4].ep[3].dequeue;
    uint32_t short_trb[] = {0x6000, 0, HV_GP_REPORT_LEN-1, TRB_NORMAL << 10 | 1};
    memcpy(guest + at, short_trb, sizeof short_trb);
    memset(guest + at + 16, 0, 16);
    uint64_t delivered = x->gamepad.delivered;
    run_ep_in(x, 4);
    assert(!hv_xhci_gamepad_ready(x) && x->gamepad.delivered == delivered && x->gamepad.tail-x->gamepad.head == 1);
    uint32_t full_trb[] = {0x6010, 0, HV_GP_REPORT_LEN, TRB_NORMAL << 10 | 1};
    memcpy(guest + at + 16, full_trb, sizeof full_trb);
    run_ep_in(x, 4); assert(hv_xhci_gamepad_ready(x));
    drain_gamepad(x);
    hv_xhci_gamepad_active(x, 0);
    run_ep_in(x, 4);
    assert(!hv_xhci_gamepad_ready(x) && hv_xhci_gamepad(x, 1, 8, axes) == -1);
    assert(x->gamepad.state[0] == 0 && x->gamepad.state[2] == 8);
    hv_xhci_gamepad_active(x, 1);
    assert(hv_xhci_gamepad_ready(x));
    uint8_t unconfigure[] = {0,9,0,0,0,0,0,0};
    assert(control(x, 4, unconfigure, out, sizeof out) == 0);
    run_ep_in(x, 4); assert(!hv_xhci_gamepad_ready(x));
    port_write(x, 3, PORT_PR);
    assert(!x->slots[4].configured && !x->slots[4].ep_running[3]);
    pthread_mutex_destroy(&x->mu); free(x);
    puts("PASS: USB gamepad descriptors, mapping, edge/coalescing order, 4 ms pacing, overflow release and USB reset");
    return 0;
}
