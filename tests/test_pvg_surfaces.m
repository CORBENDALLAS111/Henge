/* Compile the production replay in this test so its private surface/object
   paths are exercised. Only guest memory transport is substituted; Metal and
   IOSurface allocations, texture views and command completion are real. */
#import "../devices/pvg_metal.m"
#include <assert.h>

static uint8_t guest[65536];
int hv_pvg_lite_task_read(HvPvgLite *p, uint32_t task, uint64_t at, void *out, uint32_t n) {
    (void)p; (void)task;
    if (at > sizeof guest || n > sizeof guest - at) return -1;
    memcpy(out, guest + at, n); return 0;
}
uint64_t hv_pvg_lite_task_objects(HvPvgLite *p, uint32_t task) { (void)p; (void)task; return 0x100; }
void hv_pvg_lite_task_pages(HvPvgLite *p, uint32_t t, uint64_t f, uint64_t n, uint32_t *out) {
    (void)p; (void)t; (void)f; memset(out, 0, n * 4);
}
int hv_pvg_lite_old_driver(HvPvgLite *p) { (void)p; return 0; }
uint8_t *hv_pvg_lite_page(HvPvgLite *p, uint32_t page) { (void)p; (void)page; return NULL; }
void *hv_pvg_lite_phys(HvPvgLite *p, uint64_t pa, uint64_t n) { (void)p; (void)pa; (void)n; return NULL; }
const uint8_t *hv_pvg_lite_surface(HvPvgLite *p, uint32_t m) { (void)p; (void)m; return NULL; }
uint8_t *hv_pvg_lite_display_page(HvPvgLite *p) { (void)p; return NULL; }
void hv_pvg_lite_command(HvPvgLite *p, const uint32_t *c, uint32_t n) { (void)p; (void)c; (void)n; }
void hv_pvg_lite_complete(HvPvgLite *p, uint32_t ch, uint32_t stamp) { (void)p; (void)ch; (void)stamp; }
int hv_pvg_trace_on(void) { return 0; }

@interface SurfaceReplay : HvReplay {
@public
    HvObject *test_surface;
}
@end
@implementation SurfaceReplay
- (HvObject *)currentSurface:(uint64_t)mapping { (void)mapping; return test_surface; }
@end

static void texture_record(uint32_t at, uint32_t width) {
    uint32_t header[] = {1, 36, 1};
    memcpy(guest + at, header, sizeof header);
    uint8_t *d = guest + at + 12;
    d[0] = MTLTextureType2D; d[1] = MTLTextureUsageShaderRead;
    uint16_t format = MTLPixelFormatRGBA8Unorm, one = 1;
    memcpy(d + 2, &format, 2);
    memcpy(d + 4, &width, 4); memcpy(d + 8, &width, 4);
    uint32_t depth = 1; memcpy(d + 12, &depth, 4);
    memcpy(d + 16, &one, 2); memcpy(d + 18, &one, 2); memcpy(d + 20, &one, 2);
}

static void test_view_reuse(id<MTLDevice> device) {
    HvReplay *r = [HvReplay new];
    r->device = device; r->tasks = [NSMutableDictionary new]; r->complaints = [NSMutableSet new];
    texture_record(0x1000, 4); texture_record(0x1200, 8);
    uint32_t *entries = (uint32_t *)(guest + 0x100);
    entries[3] = (36 << 8) | OBJ_LINEAR_TEXTURE; entries[4] = 0x1000;
    entries[6] = (52 << 8) | OBJ_LINEAR_TEXTURE; entries[7] = 0x1100;
    uint32_t view[] = {7, 52, 2, 1}; memcpy(guest + 0x1100, view, sizeof view);
    uint16_t fmt = MTLPixelFormatRGBA8Unorm; memcpy(guest + 0x1110, &fmt, 2);
    HvObject *before = [r object:2 task:0];
    assert(before && before->object && [(id<MTLTexture>)before->object width] == 4);
    entries[4] = 0x1200; /* same child entry, new parent under the same ref */
    HvObject *after = [r object:2 task:0];
    assert(after != before && after->parent != before->parent);
    assert([(id<MTLTexture>)after->object width] == 8);
    assert([(id<MTLTexture>)before->object width] == 4); /* in-flight old view lives */
}

static void test_planes(id<MTLDevice> device) {
    HvObject *s = [HvObject new];
    vm_address_t base = 0;
    assert(vm_allocate(mach_task_self(), &base, 0x4000, VM_FLAGS_ANYWHERE) == KERN_SUCCESS);
    s->mapped = (uint8_t *)base; s->length = 0x4000; s->alloc = 384;
    uint8_t desc[0x400] = {0}; uint32_t fourcc = '420v'; memcpy(desc + 4, &fourcc, 4);
    uint64_t w = 64, h = 4; memcpy(desc + 0x20, &w, 8); memcpy(desc + 0x28, &h, 8); desc[0x3e] = 2;
    for (int i = 0; i < 2; i++) {
        uint8_t *p = desc + 0x80 + i * 0x80;
        uint64_t off = i ? 256 : 0, size = i ? 128 : 256, pw = i ? 32 : 64, ph = i ? 2 : 4, row = 64;
        uint16_t bpe = i ? 2 : 1;
        memcpy(p + 8, &off, 8); memcpy(p + 0x18, &size, 8); memcpy(p + 0x20, &pw, 8);
        memcpy(p + 0x28, &ph, 8); memcpy(p + 0x30, &row, 8); memcpy(p + 0x38, &bpe, 2);
    }
    s->iosurface = make_iosurface(s, desc, s->alloc, NO); assert(s->iosurface);
    memset(s->mapped, 0x80, s->alloc); sync_iosurface(s);
    IOSurfaceLock(s->iosurface, 0, NULL);
    uint8_t *chroma = IOSurfaceGetBaseAddressOfPlane(s->iosurface, 1);
    chroma[0] = 0xcc; /* stand in for GPU-only content in an unchanged plane */
    IOSurfaceUnlock(s->iosurface, 0, NULL);
    s->mapped[16] = 0x79; /* outside every old 8-of-64-byte sample */
    sync_iosurface(s);
    IOSurfaceLock(s->iosurface, 0, NULL);
    assert(((uint8_t *)IOSurfaceGetBaseAddressOfPlane(s->iosurface, 0))[16] == 0x79);
    assert(chroma[0] == 0xcc);
    IOSurfaceUnlock(s->iosurface, 0, NULL);

    id<MTLCommandQueue> q = [device newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer]; [cb commit];
    s->surface_sync->last_use = cb;
    s->mapped[17] ^= 1; sync_iosurface(s);
    assert(cb.status == MTLCommandBufferStatusCompleted);
    s->plane_from[0] = UINT64_MAX; /* rejected before source pointer arithmetic */
    sync_iosurface(s);
}

static void test_invalid_mapping(id<MTLDevice> device) {
    SurfaceReplay *r = [SurfaceReplay new];
    r->device = device; r->tasks = [NSMutableDictionary new]; r->complaints = [NSMutableSet new];
    r->test_surface = [HvObject new];
    r->test_surface->object = [device newBufferWithLength:0x4000 options:MTLResourceStorageModeShared];
    r->test_surface->length = 0x4000; r->test_surface->row = 4; /* cannot hold a 64-pixel row */
    uint32_t *entries = (uint32_t *)(guest + 0x100);
    entries[9] = (56 << 8) | OBJ_MAPPED_TEXTURE; entries[10] = 0x2000;
    uint64_t mapping = 1; memcpy(guest + 0x2000, &mapping, 8);
    texture_record(0x2008, 64); /* mapped header + descriptor, v1 */
    HvObject *o = [r object:3 task:0];
    assert(o && !o->object); /* never replace failed mapping with undefined pixels */
    uint32_t args[] = {0, 1, 0, 3, 0};
    assert(![r exec:args length:sizeof args channel:0 stamp:1]);
}

static void test_surface_identity(void) {
    HvObject *s = [HvObject new];
    s->fourcc = '420v'; s->surface_w = 64; s->surface_h = 4; s->alloc = 384;
    uint32_t pages[] = {0x10001, 0x10005}, other_pages[] = {0x10001, 0x10009};
    NSData *key = surface_key(s, pages, 2);
    assert([key isEqual:surface_key(s, pages, 2)]);
    assert(![key isEqual:surface_key(s, other_pages, 2)]);
    s->first = 256;
    assert(![key isEqual:surface_key(s, pages, 2)]);
    s->first = 0; s->plane_row[1] = 64;
    assert(![key isEqual:surface_key(s, pages, 2)]);
}

int main(void) {
    alarm(30);
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice(); assert(device);
        uint8_t bytes[73] = {0}; uint64_t initial = hash_bytes(bytes, sizeof bytes);
        for (unsigned i = 0; i < sizeof bytes; i++) {
            bytes[i] = 1; assert(hash_bytes(bytes, sizeof bytes) != initial); bytes[i] = 0;
        }
        test_view_reuse(device); test_planes(device); test_invalid_mapping(device); test_surface_identity();
        puts("PASS: every-byte updates, dirty-plane preservation, upload fence, invalid plane, reused parent views, invalid mapping rejection, complete backing identity");
    }
    return 0;
}
