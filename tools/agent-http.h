#ifndef HENGE_AGENT_HTTP_H
#define HENGE_AGENT_HTTP_H
#import <Foundation/Foundation.h>
NSData *HengeAgentRequest(NSString *method,NSString *path,NSData *body,int *status,unsigned long *seq,double timeoutSeconds);
void HengeStartDeviceMenu(void);
#endif
