/* Production parser, resolver lifetime and wire replies with a fake host resolver. */
#include "../host/dns_proxy.c"
#include <assert.h>
#include <unistd.h>
int hv_knob[HV_K_COUNT];
typedef struct { int pipe[2]; DNSServiceQueryRecordReply cb; void *ctx; uint16_t type; char name[1025]; } Fake;
static atomic_int replies, live, deny, callbacks;
static uint8_t capture[4][1600];
static unsigned lengths[4];
DNSServiceErrorType DNSServiceQueryRecord(DNSServiceRef *out, DNSServiceFlags flags, uint32_t iface,
    const char *name, uint16_t type, uint16_t cls, DNSServiceQueryRecordReply cb, void *ctx) {
    (void)flags; (void)iface; assert(cls == 1);
    Fake *f = calloc(1, sizeof *f); assert(f && !pipe(f->pipe));
    f->cb = cb; f->ctx = ctx; f->type = type; snprintf(f->name, sizeof f->name, "%s", name);
    atomic_fetch_add(&live, 1); *out = (DNSServiceRef)f;
    assert(write(f->pipe[1], "x", 1) == 1); return 0;
}
int DNSServiceRefSockFD(DNSServiceRef ref) { return ((Fake *)ref)->pipe[0]; }
void DNSServiceRefDeallocate(DNSServiceRef ref) {
    Fake *f = (Fake *)ref; close(f->pipe[0]); close(f->pipe[1]); free(f); atomic_fetch_sub(&live, 1);
}
DNSServiceErrorType DNSServiceProcessResult(DNSServiceRef ref) {
    Fake *f = (Fake *)ref; char c; assert(read(f->pipe[0], &c, 1) == 1);
    atomic_fetch_add(&callbacks, 1);
    if (atomic_load(&deny)) {
        f->cb(ref, 0, 0, kDNSServiceErr_PolicyDenied, f->name, f->type, 1, 0, NULL, 0, f->ctx);
        return 0;
    }
    const uint8_t ptr[] = {5,'p','h','o','n','e',6,'_','a','p','p','l','e',0};
    const uint8_t addr[] = {192,168,1,23};
    f->cb(ref, kDNSServiceFlagsAdd, 0, 0, f->name, f->type, 1,
          f->type == 12 ? sizeof ptr : sizeof addr, f->type == 12 ? ptr : addr, 60, f->ctx);
    return 0;
}
static void collect(const uint8_t *p, uint32_t len, int to_guest) {
    assert(to_guest && len < sizeof capture[0]);
    /* Callbacks may run concurrently. Serialize capture before publishing count. */
    static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&mu);
    unsigned n = atomic_load(&replies); assert(n < 4);
    memcpy(capture[n], p, len); lengths[n] = len;
    atomic_fetch_add(&replies, 1); pthread_mutex_unlock(&mu);
}
static unsigned question(uint8_t *out, const char *name, unsigned type) {
    unsigned n = 0;
    while (*name) { const char *dot = strchr(name, '.'); assert(dot); unsigned k = dot-name; out[n++] = k; memcpy(out+n, name, k); n += k; name = dot+1; }
    out[n++] = 0; wr16(out+n, type); wr16(out+n+2, 0x8001); return n+4;
}
int main(void) {
    alarm(10);
    assert(local_question_allowed("_apple-mobdev2._tcp.local.", 12));
    assert(local_question_allowed("phone._apple-mobdev2._tcp.local.", 33));
    assert(local_question_allowed("mac.local.", 1));
    assert(!local_question_allowed("_services._dns-sd._udp.local.", 12));
    assert(!local_question_allowed("bad_ssh._tcp.local.", 12));
    uint8_t bad[] = {0xc0,0}; uint8_t wire[256]; unsigned end;
    assert(!mdns_name(bad, sizeof bad, 0, wire, &end));
    uint8_t packet[512] = {0}, *ip = packet+14, *udp = ip+20, *dns = udp+8;
    packet[6] = 0x52; packet[12] = 8; ip[0] = 0x45; ip[8] = 255; ip[9] = 17;
    memcpy(ip+12, "\x0a\0\x02\x0f", 4); memcpy(ip+16, "\xe0\0\0\xfb", 4);
    wr16(udp, 5353); wr16(udp+2, 5353); wr16(dns+4, 2);
    unsigned n = 12 + question(dns+12, "_apple-mobdev2._tcp.local.", 12);
    /* Second question compresses its name against the first. */
    dns[n++] = 0xc0; dns[n++] = 12; wr16(dns+n, 16); wr16(dns+n+2, 1); n += 4;
    wr16(ip+2, 28+n); wr16(udp+4, 8+n);
    hv_dns_proxy_start();
    assert(!hv_dns_proxy_take(packet, 42+n, collect)); // no local-network prompt while off
    hv_dns_proxy_set_local(1);
    /* Discovery is independent of Internet DNS fallback. */
    hv_knob[HV_K_DNSPROXY] = 0;
    assert(hv_dns_proxy_take(packet, 42+n, collect));
    for (unsigned tries = 0; tries < 2000 && atomic_load(&replies) < 2; tries++) usleep(1000);
    hv_dns_proxy_stop(); assert(atomic_load(&replies) == 2 && !atomic_load(&live));
    for (unsigned i = 0; i < 2; i++) {
        uint8_t *p = capture[i], *a = p+14, *u = a+20, *d = u+8;
        assert(!memcmp(p, "\x01\0\x5e\0\0\xfb", 6));
        assert(!memcmp(a+12, "\x0a\0\x02\x02", 4) && !memcmp(a+16, "\xe0\0\0\xfb", 4));
        assert(a[8] == 255 && ip_checksum(a, 20) == 0);
        assert(rd16(u) == 5353 && rd16(u+2) == 5353 && rd16(u+6));
        assert(!rd16(d) && d[2] == 0x84 && !d[3] && rd16(d+4) == 1 && rd16(d+6) == 1);
        int local; char name[1025]; unsigned off = read_name(d, lengths[i]-42, 12, name, sizeof name, &local);
        assert(off && local && rd16(d+off+2) == 1); // stripped QU bit
        unsigned ulen = rd16(u+4); uint8_t pseudo[1700];
        memcpy(pseudo, a+12, 8); pseudo[8] = 0; pseudo[9] = 17; wr16(pseudo+10, ulen); memcpy(pseudo+12, u, ulen);
        assert(ip_checksum(pseudo, 12+ulen) == 0);
    }
    assert(hv_dns_proxy_local_status() == 2);
    Query old = {.local = 1, .local_epoch = atomic_load(&local_epoch)};
    hv_dns_proxy_set_local(0); hv_dns_proxy_set_local(1);
    assert(!local_current(&old)); local_result(&old, 3);
    assert(hv_dns_proxy_local_status() == 1); // old callbacks cannot overwrite a new session
    hv_knob[HV_K_DNSPROXY] = 1; atomic_store(&deny, 1);
    for (unsigned i = 0; i < 9; i++) {
        hv_dns_proxy_start(); unsigned target = atomic_load(&callbacks) + 2;
        assert(hv_dns_proxy_take(packet, 42+n, collect));
        for (unsigned tries = 0; tries < 2000 && atomic_load(&callbacks) < target; tries++) usleep(1000);
        hv_dns_proxy_stop();
        assert(atomic_load(&callbacks) == target && hv_dns_proxy_local_status() == 3);
        assert(hv_dns_proxy_on() && atomic_load(&unanswered_in_a_row) == 0);
    }
    assert(atomic_load(&replies) == 2); // denied mDNS never creates a fake answer
    hv_dns_proxy_start(); hv_dns_proxy_set_local(0);
    assert(!hv_dns_proxy_take(packet, 42+n, collect)); hv_dns_proxy_stop();
    puts("PASS: opt-in Bonjour, declared service policy, compressed multiple questions, multicast wire checksums, teardown and DNS isolation");
}
