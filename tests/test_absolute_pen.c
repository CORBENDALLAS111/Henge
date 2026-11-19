/* Real USB controller/report code; only guest RAM and PCI interrupt wiring are
   substituted. Portable so transport/cancellation tests also run under ASan. */
#include "../devices/xhci.c"
#include <assert.h>

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

int main(void) {
    HvXhci *x = hv_xhci_create(NULL, NULL); assert(x);
    assert(!hv_xhci_pen_ready(x) && hv_xhci_pen(x, 1, 1, 1, 0, 0, 0, 5) == -1);
    assert(HV_XHCI_PORTS == 3 && ((bar_read(&x->pci, 0, XECP + 8, 4) >> 8) & 255) == 3);
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
    assert(x->pen_delivered == 4 && received(0)[0] == 5 && u16(received(0) + 1) == 100);
    assert(u16(received(0) + 5) == 1000 && (int16_t)u16(received(0) + 7) == -3000 && u16(received(0) + 11) == 12345);
    assert(u16(received(1) + 1) == 1500 && received(2)[0] == 4 && received(3)[0] == 0);
    assert(u16(received(2) + 5) == 0);

    assert(!hv_xhci_pen(x, 1000, 2000, 500, 0, 0, 0, 5)); run_ep_in(x, 3);
    assert(!hv_xhci_pen(x, 30000, 30000, 800, 0, 0, 0, 5));
    hv_xhci_pen_cancel(x); run_ep_in(x, 3);
    assert(received(5)[0] == 4 && u16(received(5) + 1) == 1000 && received(6)[0] == 0);

    assert(!hv_xhci_pen(x, 123, 456, 1000, 0, 0, 0, 5)); run_ep_in(x, 3);
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
    run_ep_in(x, 3);
    assert(hv_xhci_pen_ready(x) && received(resume_at)[0] == 4 && received(resume_at + 1)[0] == 0);

    assert(!hv_xhci_pen(x, 6, 7, 1, 0, 0, 0, 5));
    uint8_t unconfigure[] = {0, 9, 0, 0, 0, 0, 0, 0};
    assert(control(x, 3, unconfigure, out, sizeof out) == 0);
    assert(!hv_xhci_pen_ready(x) && !x->pen_state[0] && x->pen_head == x->pen_tail);
    run_ep_in(x, 3); assert(!hv_xhci_pen_ready(x));
    unconfigure[2] = 1;
    assert(control(x, 3, unconfigure, out, sizeof out) == 0);
    run_ep_in(x, 3); assert(hv_xhci_pen_ready(x));
    port_write(x, 2, PORT_PR | PORT_PP);
    assert(!hv_xhci_pen_ready(x));

    uint8_t sample[13]; hv_pen_report(sample, 40000, -10, 9000, -10000, 10000, 40000, 15);
    assert(u16(sample + 1) == 32767 && u16(sample + 3) == 0 && u16(sample + 5) == 4095);
    assert((int16_t)u16(sample + 7) == -9000 && (int16_t)u16(sample + 9) == 9000 && u16(sample + 11) == 35999);
    reset(x); assert(!hv_xhci_pen_ready(x) && !x->pen_state[0] && x->pen_head == x->pen_tail);
    pthread_mutex_destroy(&x->mu); free(x);
    puts("PASS: USB pen descriptors/readiness, absolute reports, pressure/tilt/roll, motion coalescing, contact edges, cancellation and overflow release");
    return 0;
}
