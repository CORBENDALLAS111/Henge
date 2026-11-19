// Adapted from liukaixiang817/Henge 7fbc8651e8bc (GPL-2.0-or-later).
#include "legacy_vmm.h"
#include "vm.h"
#include "mmu.h"
#include "legacy_dtree.h"
#include <stdio.h>
#include <string.h>
#include <pthread.h>

static int read_virtual(HvCpu *c,uint64_t va,void *out,size_t n,int el) {
    for (size_t i=0;i<n;) {
        HvWalk w; hv_mmu_walk(c,va+i,HV_ACC_READ,el,&w);
        if (w.fsc) return 0;
        size_t part=0x4000-((va+i)&0x3fff);
        if (part>n-i) part=n-i;
        const void *p=hv_phys_ptr(c->m,w.pa,part);
        if (!p) return 0;
        memcpy((uint8_t *)out+i,p,part);i+=part;
    }
    return 1;
}
static int read_kernel(HvCpu *c,uint64_t va,void *out,size_t n) {
    return va>>40==0xfffffe && read_virtual(c,va,out,n,1);
}
typedef struct {
    const char *release, *version;
    uint64_t version_delta;
    uint32_t proc_comm;
} LegacyKernel;

/* Measured from each Apple vma2 restore kernel, including proc_name and the
   adjacent full-name accessor. Matching a common handler alone is insufficient. */
static const LegacyKernel kernels[]={
    {"macOS Ventura 13.6 (22G120)",
     "Darwin Kernel Version 22.6.0: Fri Sep 15 13:39:33 PDT 2023; root:xnu-8796.141.3.700.8~1/RELEASE_ARM64_VMAPPLE",
     0x10a69cf,0x5b8}
};

static const LegacyKernel *verified_kernel(HvCpu *c,uint64_t va) {
    char observed[128];
    for(size_t i=0;i<sizeof kernels/sizeof *kernels;i++) {
        const LegacyKernel *k=&kernels[i];size_t n=strlen(k->version)+1;
        if(va>=k->version_delta && n<=sizeof observed &&
           read_kernel(c,va-k->version_delta,observed,n) && !memcmp(observed,k->version,n))
            return k;
    }
    return NULL;
}
static pthread_mutex_t scope_lock=PTHREAD_MUTEX_INITIALIZER;
static char scope_names[128][33];
static unsigned scope_count;
static void legacy_apply(HvCpu *c) {
    /* Original CSET w8,ne after CMP w8,#0. Preserve all other registers,
       flags, memory and SYSCTL_OUT behavior, including kernel callers. */
    unsigned result=(c->nzcv&(1u<<30))==0;
    uint64_t proc=0;
    uint8_t fields[HV_LEGACY_PROC_COMM+17+33];
    size_t comm=__atomic_load_n(&c->m->compat_proc_comm,__ATOMIC_ACQUIRE);
    const char *name=NULL;
    if (c->el==1 && read_kernel(c,c->x[19],&proc,sizeof proc) && proc &&
        read_kernel(c,proc,fields,sizeof fields)) {
        if(hv_legacy_vmm_process_at(fields,sizeof fields,comm,&name)) result=0;
        if (name) {
            const char *caller = name;
            pthread_mutex_lock(&scope_lock);
            unsigned i=0;for(;i<scope_count;i++) if(!strcmp(caller,scope_names[i])) break;
            if(i==scope_count && i<sizeof scope_names/sizeof *scope_names) {
                memcpy(scope_names[scope_count++],caller,strlen(caller)+1);
                fprintf(stderr,"hengevm: legacy identity: %s reads VMM=%u\n",caller,result);
            }
            pthread_mutex_unlock(&scope_lock);
        }
    }
    c->x[8]=result;
}

static int legacy_match(HvCpu *c,uint64_t pc) {
    if(c->el!=1) return 0;
    HvMachine *m=c->m;
    if(pc>>40!=0xfffffe || pc<56) return 0;
    if (m->compat_boot && __atomic_load_n(&m->compat_boot_done, __ATOMIC_ACQUIRE) != 2) return 0;
    uint64_t known = __atomic_load_n(&m->compat_pc, __ATOMIC_ACQUIRE);
    if (known && pc != known) return 0;
    uint8_t code[104];uint64_t va=pc-56;
    if(!read_kernel(c,va,code,sizeof code) || !hv_legacy_vmm_match(code,sizeof code)) return 0;
    const LegacyKernel *kernel=verified_kernel(c,va);
    if(!kernel) return 0;
    uint32_t adrp,add;memcpy(&adrp,code+28,4);memcpy(&add,code+32,4);
    int64_t imm=((adrp>>5&0x7ffff)<<2)|(adrp>>29&3);
    if(imm&(1<<20)) imm-=1<<21;
    uint64_t key=((va+28)&~0xfffull)+imm*4096+(add>>10&0xfff);
    char text[12];
    if(!read_kernel(c,key,text,sizeof text) || memcmp(text,"vmm-present",12)) return 0;
    __atomic_store_n(&m->compat_proc_comm,kernel->proc_comm,__ATOMIC_RELEASE);
    if (__atomic_exchange_n(&m->compat_pc,pc,__ATOMIC_ACQ_REL) != pc)
        fprintf(stderr,"hengevm: software identity compatibility active for %s\n",kernel->release);
    return 1;
}

static char boot_mlb[18];
static int boot_tree(HvVmapple *b,const uint8_t *args,uint8_t **tree,size_t *size) {
    uint64_t pa;HvLegacyDTFields fields;
    if(!hv_legacy_dt_boot_args(args,112,VMAPPLE_MEM,b->ram_size,&pa,size)) return 0;
    uint8_t *p=b->ram+(pa-VMAPPLE_MEM);
    if(!hv_legacy_dt_fields(p,*size,&fields)) return 0;
    *tree=p;return 1;
}
static void legacy_boot_identity(HvCpu *c) {
    unsigned expected=0;
    if(!__atomic_compare_exchange_n(&c->m->compat_boot_done,&expected,1,0,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE)) return;
    HvVmapple *b=hv_vm_board();uint8_t args[112],*tree=NULL;size_t size=0;
    /* Prefer the actual boot-argument pointer carried in the early kernel's
       registers, before falling back to the same page-header search as the
       boot framebuffer. Never scan or change neighboring kernel objects. */
    for(unsigned i=0;i<31 && !tree;i++) {
        uint64_t at=c->x[i];int have=0;
        if(at>=VMAPPLE_MEM && at-VMAPPLE_MEM<=b->ram_size-sizeof args) {
            memcpy(args,b->ram+(at-VMAPPLE_MEM),sizeof args);have=1;
        }else if(at>>40==0xfffffe) have=read_kernel(c,at,args,sizeof args);
        if(have && !boot_tree(b,args,&tree,&size)) tree=NULL;
    }
    if(!tree) {
        uint64_t limit=b->ram_size<(1ull<<30)?b->ram_size:(1ull<<30);
        for(uint64_t at=0;at+sizeof args<=limit;at+=0x4000) {
            uint8_t *candidate=NULL;size_t candidate_size=0;
            if(!boot_tree(b,b->ram+at,&candidate,&candidate_size)) continue;
            if(tree && tree!=candidate) {tree=NULL;break;} /* ambiguous copies */
            tree=candidate;size=candidate_size;
        }
    }
    int applied=tree && hv_legacy_dt_apply(tree,size,boot_mlb,"Macmini8,1");
    __atomic_store_n(&c->m->compat_boot_done,applied?2:3,__ATOMIC_RELEASE);
    fprintf(stderr,"hengevm: experimental board identity: %s at early kernel helper\n",applied?"device-tree fields supplied":"no verified writable device tree");
}

void hv_legacy_vmm_configure(HvMachine *m,const char *mlb) {
    scope_count=0;
    m->compat_proc_comm=0;
    m->compat_match=legacy_match;m->compat_apply=legacy_apply;
    if(mlb && hv_legacy_mlb_valid(mlb)) {
        memcpy(boot_mlb,mlb,18);m->compat_boot=legacy_boot_identity;
    }
}
