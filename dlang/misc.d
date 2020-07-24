import std.stdio;
import std.format;
import std.array;
public import std.experimental.logger;

void logToFile(int line = __LINE__,
               string file = __FILE__,
               T)(T s) {
    sharedLog.log(format!"$%s@%s: %s"(line, file, s));
}



void dlogImpl(string level, bool notify = true)(string msg) {
    enum bool toScreen = false;

    logToFile(msg);
    static if (toScreen)
        writeln(msg);

    import std.algorithm;
    static assert(["low", "normal", "critical"].canFind(level));

    import config;
    static if (notify && config.notifyOnLog) {
        import std.process;
        execute(["notify-send", msg, "-t", "5000", "-u", level]);
    }
}
void dlog(string msg) {dlogImpl!("low", true)(msg);}
void dwarn(string msg) {dlogImpl!("normal", true)(msg);}
void derr(string msg) {
    brek();
    dlogImpl!("critical", true)(msg);
}

void dlog(string fmt, A...)(A args) {dlog(format!fmt(args));}
void derr(string name, Exception e) {derr(format!"%s '%s'"(name, e));}
void derr(string fmt, A...)(A args) {derr(format!fmt(args));}
void dwarn(string name, Exception e) {dwarn(format!"%s '%s'"(name, e));}
void dwarn(string fmt, A...)(A args) {dwarn(format!fmt(args));}

import std.json;
import contactsList, database.messageHistory, fullMessage;


T getVal(T)(JSONValue val, ContactsList cl) {
    import std.conv, std.array, std.traits, std.string;
    import std.typecons : nullable;
    enum isNullable = fullyQualifiedName!T.startsWith("std.typecons.Nullable!");
    enum typeName = fullyQualifiedName!T
        .chompPrefix("std.typecons.Nullable!(")
        .chomp(")").split(".")[$-1];
    try {
        static if (is(T  == bool)) return val.boolean;
        else static if (is(T == string)) {
            if (val.isNull) return "";
            return val.str;
        }
        else static if (is(T == const(Contact)[])) {
            if (val.isNull) return [];
            auto jmembers = val.array;
            import std.algorithm;
            T res = jmembers.map!(
                o => cl.getContact(o["number"].str, o["uuid"].str)).array;
            //auto res = uninitializedArray!(immutable(Contact)[])(jmembers.length);
                                  /+
            foreach (i, o; jmembers) {
                /*res[i] =*/
                res ~=
            }+/
            return res;
        }
        else static if (isArray!T) {
            enum T hax = null;
            alias U = typeof(hax[0]);
            if (val.isNull) return [];
            auto jarr = val.array;
            T res = uninitializedArray!T(jarr.length);
            foreach (i, o; jarr) res[i] = o.getVal!U(cl);
            return res;
        }
        else static if (is(T == float)) return val.floating;
        else static if (is(T == const(Contact))) {// || is(T == const Contact)) {
            if (val.isNull) return null;
            return cl.getContact(val.str);
        }
        else static if (is(T == const(Group))) {// || is(T == const Group)) {
            if (val.isNull) return null;
            return cl.getGroup(val.str);
        }
        else static if (isIntegral!T) {
            static if (isUnsigned!T) return val.uinteger.to!T;
            else return val.integer.to!T;
        }
        else static if (is(T==SignalTime)) {
            alias I = typeof(T().val);
            return T(val.integer.to!I);
        }
        else {
            static if (isNullable) {
                if (val.isNull) return T();//nullify
                alias U = TemplateArgsOf!T;
                alias W = U[0];
                return getVal!W(val, cl).nullable; // W(val, cl).nullable;
            } else {
                return T(val, cl);
            }
        }
    } catch (JSONException e) {
        derr!("ERROR %s @'%s'")(val, typeName);
        throw e;
    }
}
string genCtor(T)() {
    import std.traits;
    import std.string;

    alias F = Fields!T;
    enum Tname = fullyQualifiedName!T.split(".")[$-1];
    string res = "this(JSONValue val, ContactsList cl) {";
    static foreach (i, name; FieldNameTuple!T) {{
        res ~= "\n     ";
        enum obj = "val[\""~name~"\"]";
        res ~= "this."~name~"="~ obj ~ ".getVal!(" ~
            fullyQualifiedName!(F[i])~")(cl);";
    }}
    return res ~ "}\n";
}
string genToString(T)() {
    import std.traits;
    import std.string;

    alias F = Fields!T;
    enum Tname = fullyQualifiedName!T.split(".")[$-1];
    string res = format!"string toString() const { import std.string; string res =`%s{` "(Tname) ~";";
    static foreach (i, name; FieldNameTuple!T) {{
        res ~= "\n     ";
        enum isNullable = fullyQualifiedName!(F[i]).startsWith("std.typecons.Nullable!");
        static if (is(F[i] == const(Contact))) {// || is(F[i]==const Contact*)) {
            res ~= "res ~= format!`"~name~": %s, `(this."~name~".toString);";
        } else static if (isNullable) {
            res ~= "if (!this."~name~".isNull) res ~= format!`"~name~": %s, `(this."~name~");";
        } else {
            res ~= "res ~= format!`"~name~": %s, `(this."~name~");";
        }
    }}
    return res ~ "\nreturn res ~ `}`; }\n";
}

T* findPtr(alias Pred, T)(T[] where) {
    foreach (i, ref v; where) {
        if (Pred(v)) return &v;
    }
    return null;
}

auto findIndexAndPtr(alias Pred, T)(T[] where) {
    struct R { long idx; T* ptr; }
    foreach (i, ref v; where) {
        if (Pred(v)) return R(i, &v);
    }
    return R(-1, null);
}
auto findLastIndexAndPtr(alias Pred, T)(T[] where) {
    struct R { long idx; T* ptr;}
    for (long i = where.length-1; i >= 0; --i)
        if (Pred(where[i])) return R(i, &where[i]);
    return R(-1, null);
}

auto findIndex(alias Pred, T)(T[] where) {
    return findIndexAndPtr!(Pred, T)(where).idx;
}
auto findLastIndex(alias Pred, T)(T[] where) {
    return findLastIndexAndPtr!(Pred, T)(where).idx;
}
auto canFindWith(alias Pred, T)(T[] where) {
    return findPtr!(Pred, T)(where) != null;
}

Out[] dumbMap(In, Out)(In[] where, Out delegate(In) f) {
    Out[] res;
    foreach (v; where)
        res ~= f(v);
    return res;
}

auto splitAtFirst(T)(T[] str, T c) {
    struct Res { T[] first, rest; }
    import std.string;
    auto i = str.findIndex!(x=>x==c); //str.indexOf(c);
    if (i < 0) return Res(str, []);

    return Res(str[0..i], str[i+1..$]);
}

extern(C)
void brek() {}
