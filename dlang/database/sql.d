module database.sql;

// import std.json;
import std.range, std.algorithm, std.traits, std.format, std.string;
import d2sqlite3.statement;
import d2sqlite3.database;
import d2sqlite3.results;

import std.format;
import fullMessage;

static import database.messageHistory;

enum DbInt;

//Args (and Ts) reffers here to (Type, "name", Type2, "name2", ...);

// bool hasToJSON(T)() {
//     return __traits(compiles, T().toJSON);
// }

// bool hasFromJSON(T)() {
//     return __traits(compiles, fromJSON!T(JSONValue()));
// }
bool isDbInt(T)() {
    static if (isBuiltinType!T || isSomeString!T)
        return false;
    else return hasUDA!(T, DbInt);
}
private string argsToFuncParam(Ts...)() {
    static if (Ts.length == 0) {
        return "";
    }
    else {
        alias T = Ts[0];
        auto name = Ts[1];
        return fullyQualifiedName!T ~ " " ~ name ~ ", " ~
            argsToFuncParam!(Ts[2..$]);
    }
}
private string argsToDFuncCall(Ts...)() {
    static if (Ts.length == 0) {
        return "";
    } else {
        alias T = Ts[0];
        auto name = Ts[1];
        string val = name;
        static if (isDbInt!T) {
            val ~= ".val";
        }
        // static if (is(is()))
        // static if (is(T == JSONValue))
        //     val = name ~".toString";
        // else static if (hasToJSON!T) {
        //     val = name ~ ".toJSON.toString";
        // }
        return val ~ ", " ~argsToDFuncCall!(Ts[2..$]);
    }
    // else static if (Ts.length == 2) {
    //     auto name = Ts[1];
    //     return name;
    // }
    // else {
    //     auto name = Ts[1];
    //     return name ~ ", " ~impl!(Ts[2..$]);
    // }
}
private string[] applyOnArgs(string function(string name) f, Ts...)() {
    static if (Ts.length == 0) {
        return [];
    }
    else {
        auto name = Ts[1];
        return [f(name)] ~ applyOnArgs!(f, Ts[2..$]);
    }
}

struct Stmt {
    private string name;

    private string sqlLeft;
    private string sqlRight;

    string genFunction;
    private string sql(string table) { return sqlLeft ~table~sqlRight; }

    private string stmt() { return stmt(name); }
    static string stmt(string name) { return "this."~name~"Stmt"; }

    string genStatement() { return "Statement "~name~"Stmt;"; }
    string genInitStatement(string table) {
        return stmt ~ " = db.prepare(`" ~ sql(table) ~ "`);";
    }
    static string genBindAllFunc(string returnType, string name, Args...)() {
        auto ret = returnType;// fullyQualifiedName!Ret;
        return ret ~ " "~name~"(" ~ argsToFuncParam!(Args) ~") {\n" ~
            stmt(name)~".bindAll(" ~ argsToDFuncCall!(Args) ~");\n"~
            "scope(exit) "~
            // "auto res = "~ret~"("~stmt(name)~".execute());\n"~
            stmt(name)~".reset();\n"~
            "return " ~ returnType ~ "(" ~ stmt(name) ~ ");"  ~ "}";

            // "return res;\n}";
    }
    // void toString(scope void delegate(const(char)[]) sink) const {
    //     return sink(toString);
    // }
    // string toString() const {
    //     return  "stmt-"~name;
    // }
}
// Args is of form
Stmt SELECT(string name, string sql, Args...)() {
    //we can't do this for some reason
    // (string table) => `SELECT * FROM `~table ~ " " ~ sql ~ ";"
    return Stmt(name,
                `SELECT * FROM `,
                " " ~ sql ~ " ;",
                Stmt.genBindAllFunc!("ResRange", name, Args));
}

Stmt SELECT(string name)() { return SELECT!(name, ""); }

Stmt UPDATE(string name, Args...)() {
    enum sqlAssign = applyOnArgs!(n=> format!"%s = :%s"(n, n), Args).join(", ");
    enum func = format!"void %s(Id id, %s) {"(name, argsToFuncParam!Args) ~
        Stmt.stmt(name) ~ ".inject(" ~ argsToDFuncCall!(Args) ~ " id.val); }";
    // pragma(msg, "f:"~ func);
    // updateBlah(long id, Type type) {}
    return Stmt(
        name,
        "UPDATE ",
        format!" SET %s WHERE id == :id;"(sqlAssign),
        func);
}

//adds for example:
// alias Messages =.....;
// alias MessageId = ....;
// Messages messages;
string genTableId(string name)() {
    enum typename = capitalize(name);
    enum indexType = typename[0..$-1]~"Id";
    return format!"@DbInt struct %s { long val; enum null_ = %s(0); }\n"(
            indexType, indexType);
}
string genTable(string name, Stmt[] statements, Args...)() {
    enum typename = capitalize(name);
    enum indexType = typename[0..$-1]~"Id";
    // alias T = Table!(name, statements, Args);
    string impl(Ts...)() {
        static if (Ts.length == 0) {
            return "";
        }
        else {
            alias T = Ts[0];
            auto name = Ts[1];
            return fullyQualifiedName!T ~ ", `" ~ name ~ "`, " ~
                impl!(Ts[2..$]);
        }
    }
    enum stmt =  statements.map!(x=> format!"%s"(x)).join(",");
    enum table = "Table!(`"~name ~ "`," ~indexType ~ ", \n[" ~ stmt ~ "],\n" ~
        impl!Args ~ ")";
    // fullyQualifiedName!T;

    enum res =
        // "@DbInt struct "~ indexType ~ "{ long val; enum null_ = Id(0); }\n"~
        "alias "~typename ~ "=" ~ table~ ";\n"~
        // "alias "~ indexType ~ "="~ typename ~".Id;\n" ~
        typename ~" "~ name ~";";

    // pragma(msg,         "alias "~ indexType ~ "="~ typename ~".Id;");
    // pragma(msg, res);
    return res;
    // return format!`alias %s = %s; %s %s; `(
    //     typename, fullyQualifiedName!T, typename, name);
    // return  fullyQualifiedName!T ~ " "~ name~ ";";
}

struct Table(string name, IndexType, Stmt[] statements, Args...) {
    enum primaryKeyType = "INTEGER PRIMARY KEY AUTOINCREMENT";

    private Statement insertStmt, insertStmtWithID;
    static foreach (q; statements) {
        mixin(q.genStatement);
        // pragma(msg, q.genFunction);
        mixin(q.genFunction);
    }

    static assert(Args.length % 2 == 0);

    this(Database db) { init(db); }
    void init(Database db) {
        db.run(genCreateSql);
        this.insertStmt = db.prepare(genInsertSqlStmt!false);
        this.insertStmtWithID = db.prepare(genInsertSqlStmt!true);
        static foreach (q; statements) {
            // pragma(msg, q.genInitStatement(name));
            mixin(q.genInitStatement(name));
        }
    }
    alias Id = IndexType;
    // mixin("alias Id = "~IndexType ~";");
    // @DbInt
    // struct Id {
    //     long val;
    //     enum Id null_ = Id(0);
    // }

    struct Res {
        Id id;
        mixin(genStructRows!Args);

        this(ref Row row) {
            this.id = Id(row.peek!long(0));
            // pragma(msg, genStructCtorLines!Args);
            mixin(genStructCtorLines!Args);
        }

        static private string genStructRows(Ts...)() {
            static if (Ts.length == 0) {
                return "";
            }
            else {
                alias T = Ts[0];
                auto name = Ts[1];
                return fullyQualifiedName!T ~ " " ~ name ~ ";\n" ~
                    genStructRows!(Ts[2..$]);
            }
        }
        static private string genStructCtorLines(Ts...)(int i = 1) {
            static if (Ts.length == 0) {
                return "";
            }
            else {
                alias T = Ts[0];
                auto name = Ts[1];
                auto peekRow = format!"row.peek!(%s)(%d)"(fullyQualifiedName!T, i);
                static if (isDbInt!T)
                    peekRow = format!"%s(row.peek!long(%d))"(fullyQualifiedName!T, i);

                // static if (is(T==JSONValue)) {
                //     peekRow = format!"row.peek!string(%d).parseJSON"(i);
                // } else static if (hasFromJSON!T) {
                //     peekRow = format!"row.peek!string(%d).parseJSON.fromJSON!%s"(i, fullyQualifiedName!T);
                // }
                return "this."~name~" = " ~peekRow ~";\n" ~
                    genStructCtorLines!(Ts[2..$])(i+1);
            }
        }
    }
    struct ResRange {
        private Res[] val;
        // private ResultRange val;
        // import misc;

        this(Statement s) {
            foreach (Row r; s.execute()) {
                this.val ~= Res(r);
            }
        }
        /// Range interface.
        bool empty() @property { return val.empty(); }

        /// ditto
        Res front() @property {
            return val.front;// Res(val.front);
        }

        /// ditto
        void popFront() { val.popFront; }
    }
    // pragma(msg, genInsertFunc);
    mixin(genInsertFuncs);
    // pragma(msg, genInsertWithStruct!false);
    mixin(genInsertWithStruct!true);
    mixin(genInsertWithStruct!false);

private static:
    string genInsertWithStruct(bool withID)() {
        enum args = applyOnArgs!(x => "res."~x, Args).join(",");
        return format!"auto insert%s(Database db, Res res) {
                  return this.insert(db, %s%s);
            }"(withID ? "WithID":"WithoutID", withID?"res.id,":"", args);
    }
    string genInsertFuncs() {
        // pragma(msg, argsToDFuncCall!Args);
        return "Id insert(Database db, " ~argsToFuncParam!Args ~ ") {
                insertStmt.inject("~ argsToDFuncCall!Args ~ ");
                return Id(db.lastInsertRowid);
                }
            Id insert(Database db, Id id, " ~argsToFuncParam!Args ~ ") {
                insertStmtWithID.inject(id.val, "~argsToDFuncCall!Args ~");
                return Id(db.lastInsertRowid);
                }";
    }
    string genInsertSqlStmt(bool withID)() {
        string impl(bool addColons, Ts...)() {
            static if (Ts.length == 0) {
                return "";
            } else {
                // alias T = Ts[0];
                auto name = Ts[1];
                if (addColons) name = ":"~name;

                static if (Ts.length == 2) {
                    return name;
                } else {
                    //sql doesn't like extra commas.
                    return name~", "~impl!(addColons, Ts[2..$]);
                }
            }
        }
        return "INSERT INTO "~ name~
            " (" ~ (withID? "id, " : "") ~impl!(false, Args) ~") "~
            "VALUES (" ~ (withID? ":id, " : "") ~impl!(true, Args) ~");";
    }
    string genCreateSql() {
        string impl(Ts...)() {
            static if (Ts.length == 0) {
                return "";
            } else {
                alias T = Ts[0];
                auto name = Ts[1];
                string type;

                static if (isIntegral!T || is(T==bool) || isDbInt!T) {
                    type = "INTEGER";
                } else static if (isSomeString!T) {
                    type = "TEXT";
                } else {
                    static assert(0, "INVALID TYPE");
                }

                static if (Ts.length == 2) {
                    return name~ " " ~type;
                } else {
                    //sql doesn't like extra commas.
                    return name~ " " ~type~", "~impl!(Ts[2..$]);
                }
            }
        }
        return "CREATE TABLE IF NOT EXISTS "~ name~ " (" ~
            "id "~ primaryKeyType ~ ", " ~
            impl!(Args) ~");";
    }
}
