#include "share.h"
#include "input_focus.h"
#include <assert.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
static int call(const char *socket_path,const char *method,const char *path,const char *body,char response[4096]) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0); assert(fd>=0);
    struct sockaddr_un a={.sun_family=AF_UNIX}; snprintf(a.sun_path,sizeof a.sun_path,"%s",socket_path);
    assert(!connect(fd,(struct sockaddr *)&a,sizeof a));
    char request[512]; int n=snprintf(request,sizeof request,"%s %s HTTP/1.1\r\nHost: 10.0.2.4\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n%s",method,path,strlen(body),body);
    assert(send(fd,request,n,0)==n); shutdown(fd,SHUT_WR);
    size_t have=0; ssize_t got;
    while(have<4095 && (got=recv(fd,response+have,4095-have,0))>0) have+=got;
    close(fd); response[have]=0; int code=0; assert(sscanf(response,"HTTP/1.1 %d",&code)==1); return code;
}
typedef struct { const char *socket,*path; char response[4096]; int code; } TargetClient;
static void *follow_target(void *arg) {
    TargetClient *client=arg;
    // Instant Resume may restore an agent with a larger ID from another host
    // process. A current request must still wake it, not wait for that counter.
    client->code=call(client->socket,"GET",client->path ? client->path : "/.henge/touch-target?since=18446744073709551615","",client->response);
    return NULL;
}
int main(void) {
    alarm(10); HvInputFocus f;
    const char *bad[]={"", "2 0 0 0 0", "1 nan 0 0 0", "1 0 0 inf 0", "1 -1 0 0 0", "1 .8 0 .5 0", "1 0 0 0 0 secret", "1 0 0"};
    for(unsigned i=0;i<sizeof bad/sizeof *bad;i++) assert(!hv_input_focus_parse(bad[i],strlen(bad[i]),&f));
    assert(hv_input_focus_parse("1 .1 .2 .3 .4",strlen("1 .1 .2 .3 .4"),&f) && f.editable==1);
    char dir[]="/tmp/henge-focus-XXXXXX",sock[100],response[4096]; assert(mkdtemp(dir));
    snprintf(sock,sizeof sock,"%s/s",dir); assert(!hv_share_start(dir,sock,NULL));
    assert(call(sock,"GET","/.henge/input-settings","",response)==200 && strstr(response,"enabled=0"));
    assert(call(sock,"PUT","/.henge/focus","1 0 0 .2 .1",response)==403);
    double bounds[4],age; assert(hv_share_focus(bounds,&age)==-2);
    hv_share_set_focus_enabled(1);
    assert(call(sock,"GET","/.henge/input-settings","",response)==200 && strstr(response,"enabled=1"));
    assert(call(sock,"PUT","/.henge/focus","1 nan 0 0 0",response)==400);
    assert(call(sock,"PUT","/.henge/focus","1 .1 .2 .3 .4",response)==204);
    assert(hv_share_focus(bounds,&age)==1 && bounds[0]==.1 && bounds[2]==.3 && age<1);
    hv_share_set_focus_enabled(0); hv_share_set_focus_enabled(1);
    assert(hv_share_focus(bounds,&age)==-2); // old focus cannot trigger a new mode
    assert(call(sock,"PUT","/.henge/focus","-1 0 0 0 0",response)==204 && hv_share_focus(bounds,&age)==-1);
    hv_share_set_focus_enabled(0);
    assert(call(sock,"GET","/.henge/touch-target","",response)==403);
    assert(call(sock,"GET","/.henge/touch-target?since=-1","",response)==400);
    hv_share_set_target_enabled(1);
    assert(!hv_share_target_request(.2,.3)); // old or absent helper: no gesture delay
    TargetClient client={.socket=sock}; pthread_t worker;
    assert(!pthread_create(&worker,NULL,follow_target,&client));
    uint64_t id=0;
    for(int tries=0;tries<100 && !id;tries++) { id=hv_share_target_request(.2,.3); if(!id) usleep(1000); }
    assert(id); pthread_join(worker,NULL);
    assert(client.code==200);
    unsigned long long received=0; double x,y;
    assert(sscanf(strstr(client.response,"\r\n\r\n")+4,"%llu %lf %lf",&received,&x,&y)==3);
    assert(received==id && x==.2 && y==.3);
    char answer[80]; snprintf(answer,sizeof answer,"%llu 1",(unsigned long long)id);
    assert(call(sock,"PUT","/.henge/touch-target","1 1 private-content",response)==400);
    assert(call(sock,"PUT","/.henge/touch-target",answer,response)==204);
    assert(hv_share_target_result(id)==1);
    assert(call(sock,"PUT","/.henge/touch-target",answer,response)==409); // duplicate cannot change intent
    hv_share_target_cancel(id);
    assert(hv_share_target_result(id)==-2);
    TargetClient semantic={.socket=sock,.path="/.henge/touch-target-v2?since=18446744073709551615"};
    assert(!pthread_create(&worker,NULL,follow_target,&semantic));
    uint64_t newer=hv_share_target_request(.4,.5); assert(newer && newer!=id);
    pthread_join(worker,NULL); assert(semantic.code==200);
    char detail[180]; snprintf(detail,sizeof detail,"%llu 1 4 65 .1 .2 .3 .4",(unsigned long long)newer);
    assert(call(sock,"PUT","/.henge/touch-target",detail,response)==400); // V1 stays strict
    assert(call(sock,"PUT","/.henge/touch-target-v2",answer,response)==400); // V2 requires an object
    assert(call(sock,"PUT","/.henge/touch-target-v2",detail,response)==204);
    int kind=0; uint32_t caps=0; double geometry[4];
    assert(hv_share_target_object(newer,&kind,&caps,geometry)==1 && kind==4 && caps==65 && geometry[0]==.1 && geometry[3]==.4);
    assert(hv_share_target_result(newer)==1); // scalar API remains compatible
    assert(hv_share_target_object(id,&kind,&caps,geometry)==-2 && kind==0 && caps==0 && geometry[0]==0);
    hv_share_target_cancel(newer);
    assert(hv_share_target_object(newer,&kind,&caps,geometry)==-2 && kind==0 && caps==0);
    hv_share_set_target_enabled(0);
    assert(call(sock,"PUT","/.henge/touch-target",answer,response)==403);
    hv_share_set_target_enabled(1);
    assert(!hv_share_target_request(.2,.3)); // previous session's helper freshness is invalid
    hv_share_set_target_enabled(0);
    // Exercise the actual HTTP server and native bridge, not a mock endpoint.
    assert(call(sock,"GET","/.henge/device-status","",response)==403);
    uint64_t device=hv_share_device_begin(1),version=0; int field; double level;
    assert(device && call(sock,"GET","/.henge/device-status","",response)==503);
    HvHostDeviceStatus status={.battery=57,.power=2,.host_kind=1,.audio_route=16,.peripherals=3,
        .system_volume=.8,.brightness=.4,.vm_gain=1};
    assert(hv_share_device_publish(device,&status));
    assert(call(sock,"GET","/.henge/device-status","",response)==200 && strstr(response,"Cache-Control: no-store") && strstr(response,"\"battery\":57"));
    char command[128]; snprintf(command,sizeof command,"%llu 0 1 .5",(unsigned long long)device);
    assert(call(sock,"PUT","/.henge/device-control","1 0 1 nan",response)==400);
    assert(call(sock,"PUT","/.henge/device-control",command,response)==202);
    assert(call(sock,"PUT","/.henge/device-control",command,response)==409);
    assert(hv_share_device_take(device,&field,&version,&level) && field==0 && version==2 && level==.5);
    assert(hv_share_device_ack(device,field,version,.5));
    assert(call(sock,"GET","/.henge/device-status","",response)==200 && strstr(response,"\"vm_gain\":0.500000") && strstr(response,"\"pending\":0"));
    snprintf(command,sizeof command,"%llu 1 1 0",(unsigned long long)device);
    assert(call(sock,"PUT","/.henge/device-control",command,response)==202);
    assert(hv_share_device_take(device,&field,&version,&level) && field==1 && level==0);
    assert(hv_share_device_ack(device,field,version,0));
    uint64_t read_only=hv_share_device_begin(0); assert(read_only && read_only!=device);
    hv_share_device_stop(device); assert(hv_share_device_publish(read_only,&status));
    snprintf(command,sizeof command,"%llu 0 1 .2",(unsigned long long)read_only);
    assert(call(sock,"GET","/.henge/device-status","",response)==200);
    assert(call(sock,"PUT","/.henge/device-control",command,response)==403);
    assert(!hv_share_device_publish(device,&status));
    hv_share_device_stop(read_only);
    assert(call(sock,"GET","/.henge/device-status","",response)==403);
    unlink(sock); rmdir(dir);
    puts("PASS: real focus/target and host-device HTTP endpoints, long-poll, validation, controls and session ownership");
}
