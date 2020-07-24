module graphics.keyboard;

import std.format, std.traits, std.range;

//escape sequence
struct ES {
    string seq; Key k;
}
//todo https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
//or st source code
enum ES[] keyEscapeSequences = [// "\033" is implied
    ES("\0", Key.Esc),
    //it's easier to do it this way than inside the mixin
    ES("[\0", Key.alt('[')),// if it was not an escape code
    ES("[200~", Key.PasteBegin),
    ES("[201~", Key.PasteEnd),

    //straight outa wikipedia
    //vt
    ES("[1~", Key.Home),
    ES("[2~", Key.Insert),
    ES("[3~", Key.Delete),
    ES("[4~", Key.End),
    ES("[5~", Key.PgUp),
    ES("[6~", Key.PgDown),
    ES("[7~", Key.Home),
    ES("[8~", Key.End),
    ES("[10~", Key.F0),
    ES("[11~", Key.F1),
    ES("[12~", Key.F2),
    ES("[13~", Key.F3),
    ES("[14~", Key.F4),
    ES("[15~", Key.F5),
    ES("[17~", Key.F6),
    ES("[18~", Key.F7),
    ES("[19~", Key.F8),
    ES("[20~", Key.F9),
    ES("[21~", Key.F10),
    ES("[23~", Key.F11),
    ES("[24~", Key.F12),
    ES("[25~", Key.F13),
    ES("[26~", Key.F14),
    ES("[28~", Key.F15),
    ES("[29~", Key.F16),
    ES("[31~", Key.F17),
    ES("[32~", Key.F18),
    ES("[33~", Key.F19),
    ES("[34~", Key.F20),

    // xterm
    ES("[A", Key.Up),
    ES("[B", Key.Down),
    ES("[C", Key.Right),
    ES("[D", Key.Left),
    ES("[F", Key.End),
    ES("[G", Key.Keypad5),
    ES("[H", Key.Home),
    ES("[1Q", Key.F2),
    ES("[1R", Key.F3),
    ES("[1S", Key.F4),

//todo some sort of logic?
    ES("[1;2A", Key.ShiftUp),
    ES("[1;2B", Key.ShiftDown),
    ES("[1;2C", Key.ShiftRight),
    ES("[1;2D", Key.ShiftLeft),

    ES("[1;3A", Key.alt(Key.Up)),
    ES("[1;3B", Key.alt(Key.Down)),
    ES("[1;3C", Key.alt(Key.Right)),
    ES("[1;3D", Key.alt(Key.Left)),

    ES("[1;4A", Key.alt(Key.ShiftUp)),
    ES("[1;4B", Key.alt(Key.ShiftDown)),
    ES("[1;4C", Key.alt(Key.ShiftRight)),
    ES("[1;4D", Key.alt(Key.ShiftLeft)),


    ES("[1;5A", Key.CtrlUp),
    ES("[1;5B", Key.CtrlDown),
    ES("[1;5C", Key.CtrlRight),
    ES("[1;5D", Key.CtrlLeft),

    ES("[1;6A", Key.ShiftCtrlUp),
    ES("[1;6B", Key.ShiftCtrlDown),
    ES("[1;6C", Key.ShiftCtrlRight),
    ES("[1;6D", Key.ShiftCtrlLeft),

    ES("[1;7A", Key.alt(Key.CtrlUp)),
    ES("[1;7B", Key.alt(Key.CtrlDown)),
    ES("[1;7C", Key.alt(Key.CtrlRight)),
    ES("[1;7D", Key.alt(Key.CtrlLeft)),

    ES("[1;8A", Key.alt(Key.ShiftCtrlUp)),
    ES("[1;8B", Key.alt(Key.ShiftCtrlDown)),
    ES("[1;8C", Key.alt(Key.ShiftCtrlRight)),
    ES("[1;8D", Key.alt(Key.ShiftCtrlLeft)),



    //there are also these \eO sequences
    ES("O\0", Key.alt('O')),// if it was not an escape code
    ES("OP", Key.F1),
    ES("OQ", Key.F2),
    ES("OR", Key.F3),
    ES("OS", Key.F4),
];

struct Key {
    dchar val;
    alias val this;

    //aka '\033' - but this breaks the emacs highlighting
    enum Null = Key(0);
    enum Esc = Key(0x1B);
    enum Return = Key('\r');

    private enum Extra {
        Left,
        Right,
        Up,
        Down,
        Backspace,
        Home,
        End,
        Insert,
        Delete,
        PgUp,
        PgDown,

        Keypad5,

        PasteBegin,
        PasteEnd,

        CtrlLeft,
        CtrlRight,
        CtrlUp,
        CtrlDown,

        ShiftLeft,
        ShiftRight,
        ShiftUp,
        ShiftDown,


        ShiftCtrlLeft,
        ShiftCtrlRight,
        ShiftCtrlUp,
        ShiftCtrlDown,


        NotImplemented
    }

    // unicode range 0x0F_0000-​0x10_FFFF is private use area and we use it to
    // signify other keys and mark alt

    enum altMask   = 0x000F_1000;
    enum extraMask = 0x000F_2000;
    enum fMask     = 0x000F_4000;
    // enum ?Mask     = 0x0010_1000;

    static Key ctrl(dchar c) { return Key(c & 0x1f); }
    static Key alt(dchar c)  { return Key(c | altMask); }
    static Key F(int x)      { return Key(x | fMask); }

    bool  isAlt() const { return (val & altMask) != 0; }
    dchar unAlt() const { return cast(dchar)(val ^ altMask); }

    //ie not our masked madness
    bool isNormalChar() const { return val < 0x000F_0000; }

    dchar getChar() const { return val; }

    static foreach (e; EnumMembers!Extra)
        mixin(format!"enum Key %s = Key(Extra.%s | extraMask);"(e, e));

    static foreach (i; iota(0, 63))
        mixin(format!"enum Key F%d = Key.F(%d);"(i, i));
}



Key getkey() {
    import misc;
    import std.algorithm;
    // all escape sequences of form \033[ are terminated by a char in range
    // 0x40–0x7E (ASCII @A–Z[\]^_`a–z{|}~)
    Key findTerminator(const(char)[] prev...) {
        const(char)[] res = prev;
        //unless the user frame-perfectly mashes the correct keys
        // we should terminate the loop
        for (;;) {
            auto c = getch();
            if (c == 0) break;
            res ~= c;
            if (c >= 0x40 && c <= 0x7E) break;
        }
        dwarn!"'\\e%s'"(res);
        dwarn!"sequence '\\e%s' not implemented (%s)"(
            res, res.map!(x=>cast(int)x));
        return Key.NotImplemented;
    }

    //template metamagic here I go:
    import std.typecons;
    import std.array;

    // groups the keys by first char. for example if we call:
    // splitES(["2~":a, "2m":b, "3":c]);
    // we'll get: (using (a, b) to denote Res(a, b), and a:b for ES(a, b))
    // [ ('2', ["~":a, "m":b], ('3', ["":c]) ]

    auto /*Tuple!(char, ES[])[]*/ splitES(ES[] keys) {
        struct Res {
            char c;
            ES[] es;
        }
        //we use fairly inefficent functional-style code, but it's at compile
        //time and performance doesn't really matter

        // I bet this looks better in haskell
        ES[] getSubES(char c) {
            return keys.filter!(es => es.seq.length > 0 && es.seq[0] == c).
                map!(es=>ES(es.seq[1..$], es.k)).array;
        }
        // we ignore duplicates, but i'm the only one using this, so i can
        // deal with that. (that and _template errors_)
        Res impl(ES x) {
            if (x.seq.length==0) return Res(0, [ES("", x.k)]);
            auto c = x.seq[0];
            return Res(c, getSubES(c));
        }

        return dumbMap(keys, &impl).sort!"a.c < b.c".uniq!"a.c == b.c";
    }
    enum initialDepth = 1;
    string genSwitch(ES[] keys, int depth = initialDepth) {
        import std.uni;

        //for readablility when we do pragma(msg, ...);
        string idt(int d = depth) {
            return ' '.repeat(d * 2).array.idup;
        }

        string res = idt~
            format!"auto c%d = getch();\n%sswitch (c%d) {\n"(depth, idt, depth);
        auto chars = iota(1, depth+1).map!(x=>format!"c%d,"(x)).join;

        foreach (r; splitES(keys)) {
            bool isTerminalCase = r.es[0].seq.length == 0;
            if (r.c.isGraphical)
                res ~= idt(depth+1)~format!"case '%c': "(r.c);
            else
                res ~= idt(depth+1)~format!"case 0x%x: "(r.c);
            if (isTerminalCase) {
                res ~= format!"return cast(Key)(0x%x);\n"(r.es[0].k);
            } else {
                res ~= "{\n"~ genSwitch(r.es, depth+1)
                    ~idt(depth+1)~"}\n"; //"~format!"%s;\n"(r.es);
            }
        }
        res ~= idt;
        if (depth == initialDepth)
            res ~= format!"default: return Key.alt(%s);\n"(chars);
        else
            res ~= format!"default: return findTerminator(%s);\n"(chars);
        return res ~idt~"}\n";
    }

    auto c = getch();

    if (c != 0x1B)// Key.Esc)
        return Key(readUtf8(c));

    enum val = genSwitch(keyEscapeSequences);
    // pragma(msg, val);
    mixin(val);
    // auto c1 = getch();
    // switch (c1) {
    // case 0: return Key.Esc;
    // case '[':
    // default:
    //     return alt(c1);
    // }
}

byte getch() {
    import std.exception;
    import core.sys.posix.unistd;
    import core.stdc.errno;
    byte c = 0;
    enforce(read(STDIN_FILENO, &c, 1) >= 0 || errno == EAGAIN, "read failed");
    return c;
}


private dchar readUtf8(int c) {
    auto readExtra() { return getch() & 0b0011_1111; }
    // if (c & 0x80) {
    if ((c & 0b1110_0000) == 0b1100_0000) { //110x_xxxx - 2 bytes
        auto b1 = c & 0b0001_1111;
        auto b2 = readExtra();
        return (b1 << 6) | b2;
    } else if ((c & 0b1111_0000) == 0b1110_0000) { //1110_xxxx - 3 bytes
        auto b1 = c & 0b0000_1111;
        auto b2 = readExtra();
        auto b3 = readExtra();
        return (b1 << 6*2) | (b2 << 6) | b3;
    } else if ((c & 0b1111_1000) == 0b1111_0000) { //1111_0xxx - 4 bytes
        auto b1 = c & 0b0000_0111;
        auto b2 = readExtra();
        auto b3 = readExtra();
        auto b4 = readExtra();
        return (b1 << 6*3) | (b2 << 6*2) | (b3 << 6) | b4;
    }
    // }
    return c;
}
