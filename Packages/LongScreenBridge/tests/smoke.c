#include "LongScreenBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static unsigned char pixels[128*128*4];
static int index_;
static int reset(void *c){index_=0;return 0;}
static int next(void *c, LSFrame *frame, const uint8_t **data, size_t *length){
 if(index_==12)return 0;
 for(int y=0;y<128;y++)for(int x=0;x<128;x++){unsigned int v=(x*713+y*991+(x*y)*13);int p=(y*128+x)*4;pixels[p]=v;pixels[p+1]=v>>3;pixels[p+2]=v>>5;pixels[p+3]=255;}
 *frame=(LSFrame){index_/30.0,1.0/30,128,128};*data=pixels;*length=sizeof pixels;index_++;return 1;
}
static int progress(void*c,double fraction,const char*message){return 0;}
int main(int argc,char**argv){assert(argc==2);char *result=ls_run(128,128,0.4,reset,next,argv[1],1000000,128*1024*1024,progress,NULL);assert(result);puts(result);assert(!strstr(result,"\"error\":"));assert(strstr(result,"long-screen-"));ls_string_free(result);return 0;}
