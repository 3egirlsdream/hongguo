#include <jni.h>
#include <dlfcn.h>
JNIEXPORT jstring JNICALL Java_com_duanju_historyprobe_Probe_nativeCall(JNIEnv *env,jclass type,jstring library,jstring input) {
 const char *path=(*env)->GetStringUTFChars(env,library,0);
 void *handle=dlopen(path,RTLD_NOW|RTLD_LOCAL);
 (*env)->ReleaseStringUTFChars(env,library,path);
 if(!handle)return (*env)->NewStringUTF(env,"{\"ok\":false,\"error\":\"probe_library_unavailable\"}");
 char *(*request)(const char *)=dlsym(handle,"DuanjuRequest");
 void (*release)(char *)=dlsym(handle,"DuanjuFree");
 if(!request||!release)return (*env)->NewStringUTF(env,"{\"ok\":false,\"error\":\"probe_symbols_unavailable\"}");
 const char *body=(*env)->GetStringUTFChars(env,input,0);
 char *result=request(body);
 (*env)->ReleaseStringUTFChars(env,input,body);
 jstring out=(*env)->NewStringUTF(env,result?result:"{}");
 if(result)release(result);
 return out;
}
