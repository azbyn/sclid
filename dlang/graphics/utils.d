module graphics.utils;

public import graphics.graphemeUtils;
// import graphics.ansi;
public alias ansi = graphics.ansi;

struct Vec2i {
    long x, y;

    // even through stuff like vec*vec are implemened element wise
    // this is more useful for our purposes
    Vec2i opBinary(string op)(Vec2i rhs) {
        return mixin("Vec2i(x "~op~"rhs.x, y "~op~" rhs.y)");
    }
    Vec2i opMul(int rhs) { return Vec2i(x*rhs, y*rhs);}
    Vec2i opOpAssign(string op)(Vec2i rhs) {
        mixin("this.x "~op~"= rhs.x; this.y "~op~"= rhs.y;");
        return this;
    }
}


struct Size {
    long width, height;

    long w() const { return width; }
    long h() const { return height; }
    auto vec() const { return Vec2i(width, height); }
    Size opBinary(string op)(Size rhs) {
        return mixin("Size(w "~op~"rhs.w, h "~op~" rhs.h)");
    }
    Size opMul(int rhs) { return Size(w*rhs, h*rhs);}
    Size opOpAssign(string op)(Size rhs) {
        mixin("this.w "~op~"= rhs.w; this.h "~op~"= rhs.h;");
        return this;
    }
    //alias vec this;
}
alias Point = Vec2i;
alias Pos = Vec2i;

struct Rect {
    long x, y;
    long width, height;

    Point p0() const { return Point(x, y); }
    Point p1() const { return Point(x+width, y+height); }

    long w() const { return width; }
    long h() const { return height; }
}

struct Line {
    import std.array;
    import misc;
    import std.uni;

    string val;
    long width;
    long maxWidth;

    invariant() {
        assert(width <= maxWidth);
    }

    private this(string val, long width, long maxWidth) {
        this.width = width;
        this.val = val;
        this.maxWidth = maxWidth;
    }
    this(long maxWidth) {
        this.maxWidth = maxWidth;
    }

    string flushLeft() {
        return rightSpaces(maxWidth - width);
    }
    string flushRight() {
        return leftSpaces(maxWidth - width);
    }
    string centered() {
        const totalPadding = (maxWidth - width);
        const leftPadding  = totalPadding / 2;
        const rightPadding = totalPadding - leftPadding;
        return sideSpaces(leftPadding, rightPadding);
    }

    import config;
    import std.conv, std.format, std.algorithm;
    enum addFuncs;

    private static string[] getFunctions() {
        string[] res;
        import std.traits, std.string, std.uni;
        static foreach (name; __traits(allMembers, Line)) {{
            mixin("alias Sym = "~name~";");
            static if (hasUDA!(Sym, addFuncs)) {
                enum makeName = name.chomp("Impl");
                // enum makeName1 = appendName.chompPrefix("append");
                enum appendName = "append"~makeName[0].toUpper.text~makeName[1..$];
                res ~= "auto "~appendName~"(string str) {"
                    ~ name~"(&appendImpl, "
                    ~ "maxWidth - width, str); }\n";

                res ~= "auto "~appendName~"(string str, OnOff oo) {"
                    ~ name~"((string str, size_t w) => "
                    ~ "this.appendImpl(oo(str), w),"
                    ~ "maxWidth - width, str); }\n";

                res ~= "static Line "~makeName~"(string str, size_t maxWidth) {"
                    ~ "Line res;"~ name~"((string str, size_t w) =>"
                    ~ " res = Line(str, w, maxWidth),"
                    ~ "maxWidth, str); return res; }\n";

                res ~= "static Line "~makeName~"(string str, size_t maxWidth,"
                    ~ "OnOff oo) {"
                    ~ "auto res = Line(maxWidth);"
                    ~ "res."~appendName~"(str, oo); return res; }";
            }
        }}
        return res;
    }
    static foreach (f; getFunctions) {
        // pragma(msg, f);
        mixin(f);
    }

    Line with_(OnOff oo) const {
        return Line(oo(val), width, maxWidth);
    }

    //we can't use terminalSize cuz errors, so this is the next best thing
    private enum ellipsisSize = config.ellipsis.to!dstring.length;
    //all these things return true if we ran out of space.

    static Line fill(string c, long count) in {
        assert(c.terminalWidth == 1);
    } do {
        return Line(c.replicate(count), count, count);
    }

    @addFuncs
    static void asciiWithEllipsisImpl(F)(F /*void delegate(string, long)*/ f,
                                      size_t usableWidth, string str)
    in {
        auto ptr = str.findIndexAndPtr!(c => (c & 0x80) != 0 || c == 0x1B).ptr;
        assert(ptr == null,
               format!"only ascii expected, got '%s' - %s - %x"(
                   str, str.map!(c=>cast(ubyte) c), *ptr));

        // assert(usableWidth >= ellipsisSize, "usableWidth too small");
    } do {
        if (usableWidth < ellipsisSize) return;
        auto width = str.length;
        // dlog!"ž: %s, %s"(str, width);
        if (str.length > usableWidth) {
            width = usableWidth;
            str = str[0..usableWidth-ellipsisSize] ~ config.ellipsis;
        }

        f(str, width);
    }

    @addFuncs
    static void utfWithEllipsisImpl(F)(F /*void delegate(string, long)*/ f,
                                       size_t usableWidth, string str)
    in {
        assert(!str.hasAnsi, "non ansi expected");
    } do {
        if (usableWidth < ellipsisSize) return;
        auto graphemes = str.byGrapheme;
        auto res = sublineWithSize(graphemes, usableWidth-ellipsisSize);
        auto remainingWidth = res.remaining.terminalSize;
        res.val.maxWidth = usableWidth;
        if (remainingWidth <= ellipsisSize) {
            res.val.appendImpl(res.remaining.toStr, remainingWidth);
        } else {
            res.val.appendImpl(ellipsis, ellipsisSize);
        }

        f(res.val.val, res.val.width);
    }

    private void appendImpl(string val, size_t width) {
        return appendUnsafe(val, width);
    }
    void appendImpl(in Grapheme g, size_t width) {
        appendUnsafe(g.toStr, width);
    }

    void appendUnsafe(string val, size_t width) {
        this.width += width;
        this.val ~= val;
        assert(width <= maxWidth);
    }

    private string leftSpaces(long count) {
        assert(count >= 0);
        return replicate(" ", count) ~ val;
    }

    private string rightSpaces(long count) {
        assert(count >= 0);
        return val ~ replicate(" ", count);
    }

    private string sideSpaces(long l, long r) {
        return replicate(" ", l) ~ val ~ replicate(" ", r);
    }
}

import graphics.ansi;
auto selectedBorderCol = Color.Blue;
import std.uni;

struct SubLineRes(T, Range) {
    T val;
    Range remaining;
}

SubLineRes!(Line, Range) sublineWithSize(Range)(Range range, size_t width) {
    return sublineWithSize(range, width, Line(width));
}
SubLineRes!(T, Range) sublineWithSize(T, Range)(Range range, size_t width,
                                                T initial)
    if (isGraphemeRange!Range)
{
    import std.traits, std.range;
    T val = initial;
    for (; !range.empty; range.popFront()) {
        auto g = range.front;
        auto ts = g.terminalSize;
        if (val.width + ts > width) break;
        val.appendImpl(g, ts);
    }
    return SubLineRes!(T, Range)(val, range);
}


unittest {
    auto val = sublineWithSize("hello".byGrapheme, 3);
    assert(val.res == Line("hel", 3));
    assert(val.remaining == "lo".byGrapheme);

    val = sublineWithSize("he😃lo".byGrapheme, 3);
    assert(val.res == Line("he", 3));
    assert(val.remaining == "😃lo".byGrapheme);
}


struct GraphemeLine {
    struct Val {
        const Grapheme val;
        size_t ts;

        bool isSpace() const { return val.isSpace; }
    }
    Val[] arr;
    size_t width;

    //maxw
    Line toLineUnsafe(size_t maxWidth) const
    in {
        assert(width <= maxWidth);
    } do {
        import std.algorithm, std.array;
        return Line(
            arr.map!(v=>v.val).toStr,
            // arr.map!((Val v)=>v.val.toStr).join(),
            width, maxWidth);
    }

    void appendImpl(in Grapheme g, size_t ts) {
        arr ~= Val(g, ts);
        width += ts;
    }
}

enum SkipSpace { Yes, No }
//if we call (with the proper types, ie "blah".byGrapheme.array)
//sublineBySpace("  hello the   world", 7); we'd get
// "hello"
auto sublineBySpace(SkipSpace skipSpace = SkipSpace.Yes)(
        const(Grapheme)[] graphemes, size_t width) {
    import misc;

    //skip first whitespace
    static if (skipSpace == SkipSpace.Yes) {{
        auto i = graphemes.findIndex!(g => !g.isSpace);
        if (i >= 0)
            graphemes = graphemes[i..$];
        else {
            //we have nothing left (that's not whitespace)
            return SubLineRes!(GraphemeLine, const(Grapheme)[])();
        }
    }}
    auto res = sublineWithSize(graphemes, width, GraphemeLine());
    import std.range;
    if (res.remaining.empty)
        return res;
    auto lastSpace = res.val.arr.findLastIndex!(x=> x.isSpace);

    //if we can't break by spaces we just break wherever
    if (lastSpace < 0) return res;

    import std.algorithm;
    res.val.arr = res.val.arr[0..lastSpace];
    res.val.width = res.val.arr.map!(v=>v.ts).sum;
    res.remaining = graphemes[lastSpace..$];

    return res;
}
string shortNiceAttachmentsStr(R)(R attachments) {
    import std.algorithm, std.path, std.array;
    import fileInfo : removeSignalTimestamp;
    return attachments.map!(x=>x.baseName.removeSignalTimestamp).join(" ");
}
