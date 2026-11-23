#ifndef HENGE_AUDIO_GAIN_H
#define HENGE_AUDIO_GAIN_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
enum { HV_AUDIO_PCM_S16=5,HV_AUDIO_PCM_S32=17,HV_AUDIO_PCM_FLOAT=19 };
/* The gain is attenuation only. Read/pull timing and guest PCM remain intact. */
static inline void hv_audio_scale_pcm(void *buffer,size_t length,unsigned format,unsigned gain) {
    if(!buffer || !length || gain>=1000) return;
    if(!gain) { memset(buffer,0,length); return; }
    unsigned char *p=buffer;
    if(format==HV_AUDIO_PCM_S16) for(size_t i=0;i+2<=length;i+=2) {
        int16_t v; memcpy(&v,p+i,2); v=(int16_t)((int32_t)v*(int32_t)gain/1000); memcpy(p+i,&v,2);
    }
    else if(format==HV_AUDIO_PCM_S32) for(size_t i=0;i+4<=length;i+=4) {
        int32_t v; memcpy(&v,p+i,4); v=(int32_t)((int64_t)v*gain/1000); memcpy(p+i,&v,4);
    }
    else if(format==HV_AUDIO_PCM_FLOAT) for(size_t i=0;i+4<=length;i+=4) {
        float v; memcpy(&v,p+i,4); v=isfinite(v)?v*((float)gain/1000):0; memcpy(p+i,&v,4);
    }
}
#endif
