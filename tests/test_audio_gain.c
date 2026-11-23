#include "audio_gain.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
int main(void) {
    int16_t a[]={INT16_MIN,-1,0,1,INT16_MAX};
    hv_audio_scale_pcm(a,sizeof a,HV_AUDIO_PCM_S16,500);
    assert(a[0]==-16384 && a[1]==0 && a[2]==0 && a[3]==0 && a[4]==16383);
    int32_t b[]={INT32_MIN,-1,0,1,INT32_MAX};
    hv_audio_scale_pcm(b,sizeof b,HV_AUDIO_PCM_S32,999);
    assert(b[0]==(int32_t)((int64_t)INT32_MIN*999/1000) && b[4]==(int32_t)((int64_t)INT32_MAX*999/1000));
    assert(b[1]==0 && b[2]==0 && b[3]==0);
    float c[]={-1,.5f,1,NAN,INFINITY};
    hv_audio_scale_pcm(c,sizeof c,HV_AUDIO_PCM_FLOAT,250);
    assert(c[0]==-.25f && c[1]==.125f && c[2]==.25f && c[3]==0 && c[4]==0);
    unsigned char untouched[]={0,1,2,3,0xff,0xfe,0xaa}; unsigned char copy[sizeof untouched];
    memcpy(copy,untouched,sizeof copy);
    hv_audio_scale_pcm(copy,sizeof copy,HV_AUDIO_PCM_FLOAT,1000);
    assert(!memcmp(copy,untouched,sizeof copy)); // Unity preserves every bit (including nonfinite PCM).
    hv_audio_scale_pcm(copy,sizeof copy,99,400); assert(!memcmp(copy,untouched,sizeof copy));
    hv_audio_scale_pcm(copy,sizeof copy,99,0);
    for(size_t i=0;i<sizeof copy;i++) assert(copy[i]==0);
    // Real AudioUnit data can be unaligned. Never touch canaries or incomplete samples.
    unsigned char unaligned[12]; memset(unaligned,0xa5,sizeof unaligned);
    int32_t max=INT32_MAX,scaled; memcpy(unaligned+1,&max,4);
    hv_audio_scale_pcm(unaligned+1,7,HV_AUDIO_PCM_S32,500); memcpy(&scaled,unaligned+1,4);
    assert(scaled==1073741823 && unaligned[0]==0xa5);
    for(size_t i=5;i<sizeof unaligned;i++) assert(unaligned[i]==0xa5);
    hv_audio_scale_pcm(unaligned+1,7,HV_AUDIO_PCM_S32,0);
    for(size_t i=1;i<8;i++) assert(unaligned[i]==0);
    assert(unaligned[0]==0xa5 && unaligned[8]==0xa5);
    hv_audio_scale_pcm(NULL,1,HV_AUDIO_PCM_S16,0);
    puts("PASS: S16/S32/float attenuation, extremes, unity, mute, alignment and boundaries");
}
