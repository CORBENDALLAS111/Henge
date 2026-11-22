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
typedef struct { const char *socket; char response[4096]; int code; } TargetClient;
static void *follow_target(void *arg) {
    TargetClient *client=arg;
    client->code=call(client->socket,"GET","/.henge/touch-target?since=0","",client->response);
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
    hv_share_set_target_enabled(0);
    assert(call(sock,"PUT","/.henge/touch-target",answer,response)==403);
    hv_share_set_target_enabled(1);
    assert(!hv_share_target_request(.2,.3)); // previous session's helper freshness is invalid
    hv_share_set_target_enabled(0);
    unlink(sock); rmdir(dir);
    puts("PASS: opt-in focus/target endpoints, long-poll delivery, metadata validation, no-helper fallback, cancellation and mode reset");
}
