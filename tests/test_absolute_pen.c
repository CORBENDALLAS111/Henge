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
static void deliver_pending(HvXhci *x) {
    unsigned guard = HV_PEN_REPORTS + 1;
    while (x->pen_head != x->pen_tail && guard--) {
        input_time_ns += 1000000;
        run_ep_in(x, 3);
    }
    assert(x->pen_head == x->pen_tail);
}

int main(void) {
    HvXhci *x = hv_xhci_create(NULL, NULL); assert(x);
    assert(!hv_xhci_pen_ready(x) && hv_xhci_pen(x, 1, 1, 1, 0, 0, 0, 5) == -1);
    assert(HV_XHCI_PORTS == 4 && ((bar_read(&x->pci, 0, XECP + 8, 4) >> 8) & 255) == 4);
    x->slots[3].dev = 2; x->slots[3].configured = 1;
    x->slots[3].ep_running[3] = 1;
    x->slots[3].ep[3] = (HvXhciRing){0x1000, 1};
    for (unsigned i = 0; i < 128; i++) {
        uint32_t trb[] = {0x4000 + i * 16, 0, HV_PEN_REPORT_LEN, TRB_NORMAL << 10 | 1};
        memcpy(guest + 0x1000 + i * 16, trb, sizeof trb);
    }
    run_ep_in(x, 3); assert(hv_xhci_pen_ready(x));
    uint8_t setup[] = {0x81, 6, 0, 0x22, 0, 0, 255, 0}, out[256];
    int n = control(x, 3, setup, out, sizeof out);
    assert(n == sizeof hv_pen_descriptor && !memcmp(out, hv_pen_descriptor, n));

    assert(!hv_xhci_pen(x, 100, 200, 1000, -3000, 4500, 12345, 5));
    for (int i = 500; i <= 1500; i++) assert(!hv_xhci_pen(x, i, i, 2000, 0, 0, 0, 5));
    assert(x->pen_tail - x->pen_head == 2); /* preserve initial down, coalesce motion */
    assert(!hv_xhci_pen(x, 1500, 1500, 0, 0, 0, 0, 4));
    assert(!hv_xhci_pen(x, 1500, 1500, 0, 0, 0, 0, 0));
    run_ep_in(x, 3);
    /* A 1 ms interrupt endpoint must not collapse contact edges into a single
       controller tick, even when the guest posts many receive buffers. */
    assert(x->pen_delivered == 1);
    run_ep_in(x, 3); assert(x->pen_delivered == 1);
    input_time_ns += 999999;
    run_ep_in(x, 3); assert(x->pen_delivered == 1);
    input_time_ns++;
    run_ep_in(x, 3); assert(x->pen_delivered == 2);
    deliver_pending(x);
    assert(x->pen_delivered == 4 && received(0)[0] == (5 | HV_PEN_PRIMARY) && u16(received(0) + 1) == 100);
    assert(u16(received(0) + 5) == 1000 && (int16_t)u16(received(0) + 7) == -3000 && u16(received(0) + 11) == 12345);
    assert(u16(received(1) + 1) == 1500 && received(2)[0] == 4 && received(3)[0] == 0);
    assert(u16(received(2) + 5) == 0);

    assert(!hv_xhci_pen(x, 1000, 2000, 500, 0, 0, 0, 5)); deliver_pending(x);
    assert(!hv_xhci_pen(x, 30000, 30000, 800, 0, 0, 0, 5));
    hv_xhci_pen_cancel(x); deliver_pending(x);
    assert(received(5)[0] == 4 && u16(received(5) + 1) == 1000 && received(6)[0] == 0);

    assert(!hv_xhci_pen(x, 123, 456, 1000, 0, 0, 0, 5)); deliver_pending(x);
    for (int i = 0; i < HV_PEN_REPORTS; i++) assert(!hv_xhci_pen(x, i, i, 100, 0, 0, 0, i % 2 ? 5 : 4));
    assert(hv_xhci_pen(x, 100, 100, 100, 0, 0, 0, 4) == -1);
    assert(x->pen_overflows == 1 && x->pen_tail - x->pen_head == 2);
    assert(x->pen_reports[0][0] == 4 && x->pen_reports[1][0] == 0);
    assert(hv_xhci_pen(x, 1, 1, 1, 0, 0, 0, 5) == -1);
    hv_xhci_pen_cancel(x);
    assert(!hv_xhci_pen(x, 1, 1, 1, 0, 0, 0, 5));

    /* An endpoint stop rejects new input and releases the last delivered
       contact when the guest resumes posting transfers. */
    pen_pause(x);
    assert(!hv_xhci_pen_ready(x) && hv_xhci_pen(x, 5, 5, 1, 0, 0, 0, 5) == -1);
    unsigned resume_at = (unsigned)x->pen_delivered;
    input_time_ns += 1000000;
    run_ep_in(x, 3); deliver_pending(x);
    assert(hv_xhci_pen_ready(x) && received(resume_at)[0] == 4 && received(resume_at + 1)[0] == 0);

    /* Short taps remain separate clicks after the guest stalls, including
       repeated taps at different targets. No sleeps or real-clock flakes. */
    unsigned clicks_at = (unsigned)x->pen_delivered;
    for (int i = 0; i < 8; i++) {
        assert(!hv_xhci_pen(x, 1000 + i, 2000, 0, 0, 0, 0, 4));
        assert(!hv_xhci_pen(x, 1000 + i, 2000, 4095, 0, 0, 0, 5));
        assert(!hv_xhci_pen(x, 1000 + i, 2000, 0, 0, 0, 0, 4));
        assert(!hv_xhci_pen(x, 1000 + i, 2000, 0, 0, 0, 0, 0));
    }
    for (int i = 0; i < 8; i++) {
        for (int phase = 0; phase < 4; phase++) {
            unsigned before = (unsigned)x->pen_delivered;
            input_time_ns += 1000000;
            run_ep_in(x, 3);
            assert(x->pen_delivered == before + 1);
            const uint8_t *r = received(clicks_at + 4 * i + phase);
            assert(r[0] == (phase == 1 ? (5 | HV_PEN_PRIMARY) : phase == 3 ? 0 : 4));
            assert(u16(r + 1) == (unsigned)(1000 + i));
            run_ep_in(x, 3); assert(x->pen_delivered == before + 1);
        }
    }

    /* A restored snapshot may have a last-delivery time from another host
       uptime. A backwards host clock must not strand a held button. */
    assert(!hv_xhci_pen(x, 10, 20, 4095, 0, 0, 0, 5));
    input_time_ns = 1000000;
    unsigned before_clock_change = (unsigned)x->pen_delivered;
    run_ep_in(x, 3); assert(x->pen_delivered == before_clock_change + 1);
    hv_xhci_pen_cancel(x); deliver_pending(x);

    assert(!hv_xhci_pen(x, 6, 7, 1, 0, 0, 0, 5));
    uint8_t unconfigure[] = {0, 9, 0, 0, 0, 0, 0, 0};
    assert(control(x, 3, unconfigure, out, sizeof out) == 0);
    assert(!hv_xhci_pen_ready(x) && !x->pen_state[0] && x->pen_head == x->pen_tail);
    run_ep_in(x, 3); assert(!hv_xhci_pen_ready(x));
    unconfigure[2] = 1;
    assert(control(x, 3, unconfigure, out, sizeof out) == 0);
    run_ep_in(x, 3); assert(hv_xhci_pen_ready(x));
    port_write(x, 2, PORT_PR | PORT_PP);
    run_ep_in(x, 3);
    assert(!hv_xhci_pen_ready(x) && !x->slots[3].configured && !x->slots[3].ep_running[3]);

    uint8_t sample[13]; hv_pen_report(sample, 40000, -10, 9000, -10000, 10000, 40000, 15);
    assert(u16(sample + 1) == 32767 && u16(sample + 3) == 0 && u16(sample + 5) == 4095);
    assert((int16_t)u16(sample + 7) == -9000 && (int16_t)u16(sample + 9) == 9000 && u16(sample + 11) == 35999);
    reset(x); assert(!hv_xhci_pen_ready(x) && !x->pen_state[0] && x->pen_head == x->pen_tail);
    pthread_mutex_destroy(&x->mu); free(x);
    puts("PASS: USB pen readiness/reports, 1 ms interrupt service, short taps after guest stall, backwards host clock, motion coalescing, cancellation and overflow release");
    return 0;
}
