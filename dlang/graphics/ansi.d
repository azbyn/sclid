module graphics.ansi;

import std.format;
import graphics.utils;

string with_(string s, OnOff oo) {
    return oo.on ~s ~oo.off;
}

struct OnOff {
    string on, off;

    this(string on, string off) { this.on = on; this.off = off; }

    string opCall(string s) const {
        return on ~s~off;
    }

    T opCall(T)(T t) const {
        return t.with_(this);
    }
    OnOff opBinary(string val)(OnOff rhs) const if (val == "~") {
        return OnOff(on ~ rhs.on, rhs.off ~ off);
    }
}

enum normal        = "\033[m";
enum bold          = OnOff("\033[1m", "\033[22m");
enum italic        = OnOff("\033[3m", "\033[23m");
enum underline     = OnOff("\033[4m", "\033[24m");
enum reverse       = OnOff("\033[7m", "\033[27m");
enum strikethrough = OnOff("\033[9m", "\033[29m");

enum alternativeBuffer = OnOff("\033[?1049h", "\033[?1049l");
enum bracketedPaste    = OnOff("\033[?2004h", "\033[?2004l");
enum cursorVisibility  = OnOff("\033[?25h", "\033[?25l");

enum Color {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
}

string fgstr(Color c) { return format!"\033[%dm"(30 + cast(int) c); }
string bgstr(Color c) { return format!"\033[%dm"(40 + cast(int) c); }

OnOff bg(Color c) { return OnOff(bgstr(c), bgclear); }
OnOff fg(Color c) { return OnOff(fgstr(c), fgclear); }

//OnOff

enum fgclear = "\033[39m";
enum bgclear = "\033[49m";

OnOff fg256(ubyte c) { return OnOff(fg256str(c), fgclear); }
OnOff bg256(ubyte c) { return OnOff(bg256str(c), bgclear); }

string fg256str(ubyte c) { return format!"\033[38;5;%dm"(c); }
string bg256str(ubyte c) { return format!"\033[48;5;%dm"(c); }


enum clearScr = "\033[2J"; //the whole screen;
enum clearToEol = "\033[K";
enum clearToBot = "\033[J";

string cursorHoriAbs(size_t x) { return format!"\033[%dG"(x+1); }

enum cursorDefault = "\x1b[0 q";
// i don't like blinking cursors
enum cursorFull  = "\x1b[2 q";
enum cursorUnder = "\x1b[4 q";
enum cursorI     = "\x1b[6 q";

string moveCursor(Point p) { return format!"\033[%d;%dH"(p.y+1,p.x+1); }
