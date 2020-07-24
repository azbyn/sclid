import std.stdio;
import std.format;
import messageManager;
import misc;
import database.messageHistory, contactsList;
import std.experimental.logger;
import config;
import graphics.graphics;
import std.exception;


import std.process, std.conv;
__gshared Pid fehPid;
void generateQR(const(wchar)[] linkUri) {
    writefln!"Code:\n%s"(linkUri);
    enum path = "/tmp/sclidqr.png";
    execute(["qrencode", "-o", path, linkUri.to!string]);
    fehPid = spawnProcess(["feh",
                           "--force-aliasing",//no antialiasing
                           "--auto-zoom",
                           path]);
}
void stopGenerate() {
    fehPid.kill();
}

__gshared {
Graphics g;
DbusManager dbus;
MessageManager man;
MessageHistory history;
ContactsList contacts;
string user;
}
version(Exec) {
    bool running = true;
    void stopLoop() { running = false; }
    void main() {
        sharedLog = new FileLogger("/tmp/sclid_log");

        config.init();

        //i'm the only one using this, so it doesn't have to have error handling
        import std.file, std.algorithm, std.path;
        .user = dirEntries(home~"/.local/share/signal-cli/data",
                           SpanMode.shallow)
             .filter!(f => !f.name.endsWith(".d")).front.name.baseName;

        dbus = new DbusManager();
        contacts = new ContactsList(user);
        history = new MessageHistory(dbus, contacts);
        man = new MessageManager(history, contacts);

        scope(exit)
            man.destroy;
        g = new Graphics(contacts, history, man);


        scope(exit)
            g.end();

        g.loopInit();
        while (running) {
            g.loopImpl();
        }
    }
} else {
    version = Lib;
}


enum JNI_VERSION_1_8 = 0x00010008;
import jni;
import std.conv : to;
import core.runtime;

const(wchar)[] getTmpString(JNIEnv* e, jstring str) {
    if (str == null) return null;
    size_t len = (*e).GetStringLength(e, str);
    wchar* ptr = cast(wchar*) (*e).GetStringChars(e, str, null);

    return ptr[0..len];
}
void releaseTmpStr(JNIEnv* e, jstring o, const(wchar)[] val) {
    (*e).ReleaseStringChars(e, o, cast(const(jchar)*) val.ptr);
}
jstring mkJstring(JNIEnv* e, const(wchar)[] val) {
    // if (val.length == 0) return null;
    return (*e).NewString(e, cast(const(jchar)*) val.ptr, val.length.to!jsize);
    //todo should we free later?
}
jobjectArray mkStrArray(S)(JNIEnv* e, jclass clazz, S /*const(wstring)[]*/ val) {
    if (val.length == 0)
        return null;

    jobjectArray arr = (*e).NewObjectArray(e, val.length.to!jsize, clazz, null);

    enforce(arr != null, "out or memory or something");

    jsize i = 0;
    foreach (/*i, */el; val)
        (*e).SetObjectArrayElement(e, arr, i++ /*i.to!jsize*/, mkJstring(e, el));

    //TODO should we free after?
    return arr;
}
jbyteArray mkByteArray(JNIEnv* e, const(byte)[] val) {
    if (val.length == 0)
        return null;

    jobjectArray arr = (*e).NewByteArray(e, val.length.to!jsize);
    enforce(arr != null, "out or memory or something");

    (*e).SetByteArrayRegion(e, arr, 0, val.length.to!jsize, val.ptr);

    //TODO should we free after?
    return arr;
}
import result;
alias ResultLong = Result!(long, wstring);

struct JNIMisc {
    JavaVM* vm;
    jclass nativeThreadClass, resultLongClass, stringClass;

    struct R {
        string name;
        string sig;
    }
    enum resultLong = "Lorg/asamk/signal/ResultLong;";
    enum string_ = "Ljava/lang/String;";

    enum resultLongMethods = [
        R("getRes", "()J"),
        R("isSuccess", "()Z"),
        R("getError", "()"~string_),
        ];

    enum nativeThreadStaticMethods = [
        R("stopLoop", "()V"),
        R("requestSyncAll", "()"~resultLong),
        R("sendMessage", "("~string_~ "["~string_~string_ ~")" ~ resultLong),
        R("sendGroupMessage", "("~string_ ~ "["~string_~"[B"~")"~resultLong),
        R("sendGroupMessageWithQuote",
          "("~string_~
          "["~string_~
          "[B"~
          "J"~/*long*/
          string_~
          string_~
          ")"~resultLong
            ),
        R("sendMessageWithQuote",
          "("~string_~
          "["~string_~
          string_~
          "J"~/*long*/
          string_~
          string_~
          ")"~resultLong
            ),
        R("sendGroupMessageReaction",
          "("~string_~
          "Z"~/*bool*/
          string_~
          "J"~
          "[B"~
          ")"~resultLong),

        R("sendMessageReaction",
          "("~string_~
          "Z"~/*bool*/
          string_~
          "J"~
          string_~
          ")"~resultLong),
        ];

    static foreach (m; resultLongMethods~nativeThreadStaticMethods) {
        mixin("jmethodID "~m.name~"_;");
    }

    public this(JavaVM* vm) {
        JNIEnv* e = getEnv(vm);
        this.vm = vm;
        nativeThreadClass = getClass!"org/asamk/signal/NativeThread"(e);
        resultLongClass = getClass!"org/asamk/signal/ResultLong"(e);
        stringClass = getClass!"java/lang/String"(e);

        static foreach (p; resultLongMethods)
            mixin(format!"%s_ = getMethod!(`%s`, `%s`)(resultLongClass, e);"(
                      p.name, p.name, p.sig));
        static foreach (p; nativeThreadStaticMethods)
            mixin(format!"%s_ = getStaticFun!(`%s`,`%s`)(nativeThreadClass,e);"(
                      p.name, p.name, p.sig));
    }
    void end(JNIEnv* env) {
        (*env).DeleteGlobalRef(env, nativeThreadClass);
        (*env).DeleteGlobalRef(env, resultLongClass);
        (*env).DeleteGlobalRef(env, stringClass);
    }
    JNIEnv* getEnv(JavaVM* vm) {
        JNIEnv* env;
        if ((*vm).GetEnv(vm, cast(void**) &env, JNI_VERSION_1_6) == JNI_OK) {
            return env;
        }
        throw new Exception("GetEnv failed");
    }
    JNIEnv* attachCurrentThread(JavaVM* vm) {
        JNIEnv* env;
        if ((*vm).AttachCurrentThread(vm, &env, null) == JNI_OK) {
            return env;
        }
        throw new Exception("AttachCurrentThread failed");
    }
    void stopLoop(JNIEnv* e) {
        (*e).CallStaticVoidMethod(e, nativeThreadClass, stopLoop_);
    }
    ResultLong requestSyncAll(JNIEnv* e) {
        return callStaticResultFun!"requestSyncAll"(e);
    }
    ResultLong sendMessage(A)(JNIEnv* e, wstring message,
                              A /*wstring[]*/ attachments,
                              wstring destination) {
        return callStaticResultFun!"sendMessage"(
            e,
            mkJstring(e, message),
            mkStrArray(e, stringClass, attachments),
            mkJstring(e, destination));
    }
    ResultLong sendGroupMessage(A)(JNIEnv* e, wstring message,
                                A/* wstring[]*/ attachments,
                                byte[] groupId) {
        return callStaticResultFun!"sendGroupMessage"(
            e,
            mkJstring(e, message),
            mkStrArray(e, stringClass, attachments),
            mkByteArray(e, groupId));
    }
    static jlong    mkJlong(long l) {return l;}
    static jboolean mkJbool(bool b) {return b;}

    //TODO TEST for attachments
    ResultLong sendMessageWithQuote(A)(JNIEnv* e,
        wstring message, A attachments, wstring destination,
        long qid, wstring qauthorNum, wstring qtext) {

        return callStaticResultFun!"sendMessageWithQuote"(
            e,
            mkJstring(e, message),
            mkStrArray(e, stringClass, attachments),
            mkJstring(e, destination),
            mkJlong(qid),
            mkJstring(e, qauthorNum),
            mkJstring(e, qtext));
    }

    ResultLong sendGroupMessageWithQuote(A)(JNIEnv* e,
                                            wstring message, A attachments,
                                            byte[] groupId,
                                            long qid, wstring qauthorNum,
                                            wstring qtext) {

        return callStaticResultFun!"sendGroupMessageWithQuote"(
            e,
            mkJstring(e, message),
            mkStrArray(e, stringClass, attachments),
            mkByteArray(e, groupId),
            mkJlong(qid),
            mkJstring(e, qauthorNum),
            mkJstring(e, qtext));
    }
    ResultLong sendGroupMessageReaction(JNIEnv* e,
                                        wstring emoji,
                                        bool remove,
                                        wstring targetAuthor,
                                        long targetSentTimestamp,
                                        byte[] groupId) {
        return callStaticResultFun!"sendGroupMessageReaction"(
            e,
            mkJstring(e, emoji),
            mkJbool(remove),
            mkJstring(e, targetAuthor),
            mkJlong(targetSentTimestamp),
            mkByteArray(e, groupId));
    }

    ResultLong sendMessageReaction(JNIEnv* e,
                                   wstring emoji,
                                   bool remove,
                                   wstring targetAuthor,
                                   long targetSentTimestamp,
                                   wstring destination) {
        return callStaticResultFun!"sendMessageReaction"(
            e,
            mkJstring(e, emoji),
            mkJbool(remove),
            mkJstring(e, targetAuthor),
            mkJlong(targetSentTimestamp),
            mkJstring(e, destination));
    }

private:
    ResultLong callStaticResultFun(string name, Args...)(JNIEnv* e, Args args) {
        mixin("jmethodID met = "~name~"_;");
        jobject res = (*e).CallStaticObjectMethod(
            e, nativeThreadClass, met, args);

        return getResult(e, res);
    }
    ResultLong getResult(JNIEnv* env, jobject obj) {
        bool isSuccess = (*env).CallNonvirtualBooleanMethod(
            env, obj, resultLongClass, isSuccess_) != 0;

        if (isSuccess) {
            return ResultLong.Ok((*env).CallNonvirtualLongMethod(
                                     env, obj, resultLongClass, getRes_));
        }
        else {
            auto jstr = cast(jstring) (*env).CallNonvirtualObjectMethod(
                env, obj, resultLongClass, getError_);

            auto tmp = getTmpString(env, jstr);

            wstring error = tmp.idup;
            releaseTmpStr(env, jstr, tmp);
            return ResultLong.Err(error);
        }
    }

    jclass getClass(string name)(JNIEnv* env) {
        auto local = (*env).FindClass(env, name);
        if (local == null)
            throw new Exception("local == null");

        auto clazz = cast(jclass) (*env).NewGlobalRef(env, local);

        checkException(env);
        (*env).DeleteLocalRef(env, local);

        return clazz;
    }
    void checkException(JNIEnv* env) {
        if (!(*env).ExceptionCheck(env)) return;

        (*env).ExceptionDescribe(env);
        (*env).ExceptionClear(env);
        throw new Exception("method not found not found?");
    }
    /*
      z - boolean
      B - byte
      C - char
      S - short
      I - int
      J - long
      F - float
      D - double
      L fully-qualified-class ;
      [ type - type[]
      ( arg-types ) ret-type
      * */
    jmethodID getStaticFun(string name, string sig)(jclass clazz, JNIEnv* e) {
        auto local = (*e).GetStaticMethodID(e, clazz, name, sig);
        checkException(e);
        return local;
    }
    jmethodID getMethod(string name, string sig)(jclass clazz, JNIEnv* env) {
        auto local = (*env).GetMethodID(env, clazz, name, sig);
        checkException(env);
        return local;
    }
}

__gshared JNIMisc jniMisc;

version(Lib)//TODO move this higher
extern(C)
export {
    jint JNI_OnLoad(JavaVM* vm, void* reserved) {
        try {
            // note this is OK if it is already initialized
            // since it refcounts
            Runtime.initialize();

            jniMisc = JNIMisc(vm);
        } catch (Throwable e) {
            derr!"error: %s "(e.message);
            return JNI_ERR;
        }
        return JNI_VERSION_1_6;
    }
    void JNI_OnUnload(JavaVM* vm, void* reserved) {
        JNIEnv* env;
        try {
            Runtime.terminate();
        } catch (Throwable e) {}
        if ((*vm).GetEnv(vm, cast(void**) &env, JNI_VERSION_1_6) != JNI_OK) {
            import core.stdc.stdlib;
            abort();
            // Something is wrong but nothing we can do about this :(
            return;
        } else {
            jniMisc.end(env);
        }
    }
    void Java_org_asamk_signal_Main_init(JNIEnv* e, jclass clazz, jstring user_) {
        auto str = e.getTmpString(user_);
        scope(exit) e.releaseTmpStr(user_, str);

        .user = str.to!string;
    }
    void Java_org_asamk_signal_Main_onSigint(JNIEnv* e, jclass clazz) {
        // g.end();
        // dlog("reee- sigint");
    }

    void Java_org_asamk_signal_Main_onMessageReceived(JNIEnv* e, jclass clazz,
                                                      jstring json) {
        if (man) {
            auto str = e.getTmpString(json);
            scope(exit) e.releaseTmpStr(json, str);
            man.evalLine(str);
        }
        else derr!"MAN IS NULL";
    }

    void Java_org_asamk_signal_Main_log(JNIEnv* e, jclass clazz, jstring msg) {
        auto str = e.getTmpString(msg);
        scope(exit) e.releaseTmpStr(msg, str);
        dlog!"JAVA: %s"(str);
    }
    void Java_org_asamk_signal_Main_err(JNIEnv* e, jclass clazz, jstring msg) {
        auto str = e.getTmpString(msg);
        scope(exit) e.releaseTmpStr(msg, str);
        derr!"JAVA ERR: %s"(str);
    }

    void Java_org_asamk_signal_Main_stopGenerate(JNIEnv* e, jclass clazz) {
        stopGenerate();
    }
    void Java_org_asamk_signal_Main_generateQR(JNIEnv* e, jclass clazz,
                                               jstring code) {
        auto str = e.getTmpString(code);
        scope(exit) e.releaseTmpStr(code, str);
        generateQR(str);
    }

    //NativeThread
    void Java_org_asamk_signal_NativeThread_onStart(JNIEnv* e, jobject thiz) {
        config.init();
        sharedLog = new FileLogger("/tmp/sclid_log");
        // // import core.stdc.signal;
        // // import core.stdc.stdlib : exit;
        // // signal(SIGINT, (_) { exit(0); });
        // // signal(SIGTERM, (_) { exit(0); });

        dbus = new DbusManager();
        contacts = new ContactsList(user);
        history = new MessageHistory(dbus, contacts);
        man = new MessageManager(history, contacts);

        dbus.barConnect();

        g = new Graphics(contacts, history, man);
        g.loopInit();
    }

    void Java_org_asamk_signal_NativeThread_loopImpl(JNIEnv* e, jobject thiz) {
        nativeThreadEnv = e;
        g.loopImpl();
        // stopLoop();
    }

    void Java_org_asamk_signal_NativeThread_onStop(JNIEnv* e, jobject thiz) {
        if (g)
            g.destroy;
        if (history)
            history.destroy;
    }
}
JNIEnv* nativeThreadEnv = null;

struct NativeThread {
    static foreach (p; JNIMisc.nativeThreadStaticMethods) {
        mixin(format!"static auto %s(Args...)(Args args) {
                  assert(nativeThreadEnv != null);
                  return jniMisc.%s(nativeThreadEnv, args);
                }"(p.name, p.name));
    }
}
JNIEnv* attachCurrentThread() {
    //todo - don't set the global thing, pass it as an argument
    return nativeThreadEnv = jniMisc.attachCurrentThread(jniMisc.vm);
}
