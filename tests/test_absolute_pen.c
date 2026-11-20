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
static const uint8_t *received(unsigned index) { return guest + 0x4000 + 16 * index + 1; }
static void deliver_pending(HvXhci *x) {
    unsigned guard = HV_PEN_REPORTS * (HV_PEN_EDGE_DWELL_MS + 2);
    while (x->pen_head != x->pen_tail && guard--) {
        input_time_ns += 1000000;
        run_ep_in(x, 3);
    }
    assert(x->pen_head == x->pen_tail);
}

static void test_stationary_clicks(void) {
    memset(guest, 0, sizeof guest);
    HvXhci *x = hv_xhci_create(NULL, NULL); assert(x);
    x->slots[3].dev = 2; x->slots[3].configured = 1;
    x->slots[3].ep_running[3] = 1; x->slots[3].ep[3] = (HvXhciRing){0x1000, 1};
    for (unsigned i = 0; i < 32; i++) {
        uint32_t t[] = {0x4000+i*16, 0, HV_PEN_REPORT_LEN, TRB_NORMAL<<10|1};
        memcpy(guest+0x1000+i*16,t,sizeof t);
    }
    run_ep_in(x,3); assert(hv_xhci_pen_idle(x));
    for (int i=0;i<2;i++) {
        assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,4));
        assert(!hv_xhci_pen(x,12000,8000,4095,0,0,0,5));
        assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,4));
        assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,0));
    }
    assert(!hv_xhci_pen_idle(x));
    unsigned downs=0, ups=0; int was_down=0;
    // The former 1-ms-only transport loses every stationary edge before
    // this deliberately slower consumer's first 16-ms sample.
    for (int ms=1;ms<=300;ms++) {
        input_time_ns+=1000000; run_ep_in(x,3);
        if (ms%16==0) {
            int down=(x->pen_delivered_state[1]&HV_PEN_TIP)!=0;
            if(down && !was_down) downs++;
            if(!down && was_down) ups++;
            was_down=down;
        }
    }
    assert(downs==2 && ups==2 && hv_xhci_pen_idle(x));
    pthread_mutex_destroy(&x->mu); free(x);
}

static void test_desktop_clicks(void) {
    memset(guest, 0, sizeof guest);
    HvXhci *x = hv_xhci_create(NULL, NULL); assert(x);
    x->slots[3].dev = 2; x->slots[3].configured = 1;
    x->slots[3].ep_running[3] = 1; x->slots[3].ep[3] = (HvXhciRing){0x1000, 1};
    for (unsigned i = 0; i < 128; i++) {
        uint32_t t[] = {0x4000+i*16, 0, HV_PEN_REPORT_LEN, TRB_NORMAL<<10|1};
        memcpy(guest+0x1000+i*16,t,sizeof t);
    }
    run_ep_in(x,3); assert(hv_xhci_pen_idle(x));
    assert(hv_xhci_pen(x,12000,8000,0,0,0,0,HV_PEN_DESKTOP_LEFT) == -1);
    for (int i=0; i<3; i++) {
        int button = i==2 ? HV_PEN_DESKTOP_RIGHT : HV_PEN_DESKTOP_LEFT;
        assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,4|button));
        assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,4|HV_PEN_DESKTOP_UP));
    }
    assert(!hv_xhci_pen(x,12000,8000,0,0,0,0,0));
    unsigned delivered=0, lefts=0, rights=0, releases=0;
    unsigned previous_buttons=0;
    uint64_t position_at=0, edge_at=0;
    for (int ms=0; ms<500; ms++) {
        input_time_ns+=1000000; run_ep_in(x,3);
        if (x->pen_delivered==delivered) continue;
        assert(x->pen_delivered == delivered+1);
        const uint8_t *r=guest+0x4000+16*delivered++;
        if (r[0]==HV_PEN_REPORT_ID) {
            // No accidental contact/pressure can create a second tablet click.
            assert(!(r[1] & (HV_PEN_TIP|HV_PEN_BARREL|HV_PEN_PRIMARY)));
            assert(!u16(r+6));
            assert(u16(r+2)==12000 && u16(r+4)==8000);
            position_at=input_time_ns;
        } else {
            assert(r[0]==HV_PEN_MOUSE_REPORT_ID && r[2]==0 && r[3]==0);
            unsigned buttons=r[1];
            if(buttons) assert(position_at && input_time_ns-position_at>=HV_PEN_POSITION_DWELL_MS*1000000ull);
            if(edge_at) assert(input_time_ns-edge_at>=HV_PEN_EDGE_DWELL_MS*1000000ull);
            assert(buttons != previous_buttons);
            if(buttons==1) lefts++;
            else if(buttons==2) rights++;
            else { assert(buttons==0); releases++; }
            previous_buttons=buttons; edge_at=input_time_ns;
        }
    }
    assert(lefts==2 && rights==1 && releases==3 && hv_xhci_pen_idle(x));
    uint8_t out[32];
    uint8_t get_pen[] = {0xa1,1,HV_PEN_REPORT_ID,1,0,0,32,0};
    uint8_t get_mouse[] = {0xa1,1,HV_PEN_MOUSE_REPORT_ID,1,0,0,32,0};
    assert(control(x,3,get_pen,out,sizeof out)==HV_PEN_REPORT_LEN && out[0]==HV_PEN_REPORT_ID);
    assert(control(x,3,get_mouse,out,sizeof out)==HV_PEN_MOUSE_REPORT_LEN && out[0]==HV_PEN_MOUSE_REPORT_ID && out[1]==0);
    // Trackpad clicks must not move the pointer to the call's unused XY.
    unsigned cursor_at=(unsigned)x->pen_delivered;
    assert(!hv_xhci_pen(x,0,0,0,0,0,0,4|HV_PEN_DESKTOP_LEFT|HV_PEN_DESKTOP_AT_CURSOR));
    assert(!hv_xhci_pen(x,0,0,0,0,0,0,4|HV_PEN_DESKTOP_UP));
    deliver_pending(x);
    assert(x->pen_delivered==cursor_at+2);
    const uint8_t *cursor_down=guest+0x4000+16*cursor_at;
    const uint8_t *cursor_up=guest+0x4000+16*(cursor_at+1);
    assert(cursor_down[0]==HV_PEN_MOUSE_REPORT_ID && cursor_down[1]==1);
    assert(cursor_up[0]==HV_PEN_MOUSE_REPORT_ID && cursor_up[1]==0);
    // Cancel after an actual delivered down, before any future target can move.
    assert(!hv_xhci_pen(x,2000,3000,0,0,0,0,4|HV_PEN_DESKTOP_LEFT));
    for(int ms=0;ms<100 && !x->pen_mouse_delivered;ms++) {input_time_ns+=1000000;run_ep_in(x,3);}
    assert(x->pen_mouse_delivered==1 && !hv_xhci_pen_idle(x));
    assert(!hv_xhci_pen(x,30000,30000,0,0,0,0,4));
    unsigned at=(unsigned)x->pen_delivered;
    hv_xhci_pen_cancel(x); deliver_pending(x);
    const uint8_t *up=guest+0x4000+16*at;
    assert(up[0]==HV_PEN_MOUSE_REPORT_ID && up[1]==0);
    assert(u16(received(at+1)+1)==2000 && u16(received(at+1)+3)==3000);
    assert(hv_xhci_pen_idle(x));
    // A desktop queue overflow must release rather than strand a mouse button.
    assert(!hv_xhci_pen(x,2000,3000,0,0,0,0,4|HV_PEN_DESKTOP_LEFT));
    for(int ms=0;ms<100 && !x->pen_mouse_delivered;ms++) {input_time_ns+=1000000;run_ep_in(x,3);}
    assert(x->pen_mouse_delivered==1);
    int overflow=0;
    for(int i=0;i<HV_PEN_REPORTS;i++) {
        if(hv_xhci_pen(x,2000,3000,0,0,0,0,4|(i%2?HV_PEN_DESKTOP_LEFT:HV_PEN_DESKTOP_UP))) {overflow=1;break;}
    }
    assert(overflow && x->pen_blocked);
    deliver_pending(x); assert(!x->pen_mouse_delivered && hv_xhci_pen_idle(x));
    reset(x); assert(!x->pen_mouse_delivered && !x->pen_mouse_state);
    pthread_mutex_destroy(&x->mu); free(x);
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
    assert(x->pen_reports[0][1] == 4 && x->pen_reports[1][1] == 0);
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
            uint64_t began = input_time_ns;
            do { input_time_ns += 1000000; run_ep_in(x, 3); }
            while (x->pen_delivered == before && input_time_ns - began < (HV_PEN_EDGE_DWELL_MS + 2ull) * 1000000);
            assert(x->pen_delivered == before + 1);
            if (phase == 2) assert(input_time_ns - began >= HV_PEN_EDGE_DWELL_MS * 1000000ull);
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
    assert(!hv_xhci_pen_ready(x) && !x->pen_state[1] && x->pen_head == x->pen_tail);
    run_ep_in(x, 3); assert(!hv_xhci_pen_ready(x));
    unconfigure[2] = 1;
    assert(control(x, 3, unconfigure, out, sizeof out) == 0);
    run_ep_in(x, 3); assert(hv_xhci_pen_ready(x));
    port_write(x, 2, PORT_PR | PORT_PP);
    run_ep_in(x, 3);
    assert(!hv_xhci_pen_ready(x) && !x->slots[3].configured && !x->slots[3].ep_running[3]);

    uint8_t encoded[HV_PEN_REPORT_LEN]; uint8_t *sample = encoded + 1; hv_pen_report(encoded, 40000, -10, 9000, -10000, 10000, 40000, 15);
    assert(u16(sample + 1) == 32767 && u16(sample + 3) == 0 && u16(sample + 5) == 4095);
    assert((int16_t)u16(sample + 7) == -9000 && (int16_t)u16(sample + 9) == 9000 && u16(sample + 11) == 35999);
    reset(x); assert(!hv_xhci_pen_ready(x) && !x->pen_state[1] && x->pen_head == x->pen_tail);
    pthread_mutex_destroy(&x->mu); free(x);
    test_stationary_clicks();
    test_desktop_clicks();
    puts("PASS: independent USB mouse clicks at fixed XY, left double-click/right hold reports, hover-before-click, mouse cancellation/overflow, pen pressure/tilt, interrupt service and reset");
    return 0;
}
