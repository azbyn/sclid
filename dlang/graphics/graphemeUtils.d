module graphics.graphemeUtils;
import std.conv;
import std.uni, std.range;

bool hasAnsi(string s) {
    import std.algorithm;
    return s.canFind('\033');
}
bool isGraphemeRange(T)() {
    import std.traits, std.range;
    return isInputRange!T && is(Unqual!(ElementType!T) == Grapheme);
}
alias terminalWidth = terminalSize;
size_t terminalSize(in string s) {
    return terminalSize(s.byGrapheme);
}
string toStr(in Grapheme g) {
    return [g].byCodePoint.to!string;
}
string toStr(Range)(Range range) if (isGraphemeRange!Range) {
    return range.byCodePoint.to!string;
}


//doesn't take care of ansi codes
size_t terminalSize(in Grapheme g) {
    bool isHangulJamo(dchar c) { return c >= 0x1100 && c <= 0x11FF; }
    // i assume (probably wrongly) that everything in this range
    bool isIdeograph(dchar c) {
        return c >= 0x2E80 && c <= 0xA63F;//until extended cyrillic
    }
    bool isEmoji(dchar c) { return c >= 0x1F200 && c <= 0x1F64F; }
    bool isIdeograph2(dchar c) {
        return c>= 0x20000 &&c <= 0x3134F;
    }
    if (g[0]== 0x1b) return 0;
    if (g.length > 1) {
        //emoji selector for stuff like red heart and such
        if (g[1] == 0xFE0F)
            return 2;
    }
    immutable dchar c = g[0];
    if (c == 0x180E)//mongolian vowel separator
        return 0;
    if (isHangulJamo(c) || isIdeograph(c) || isEmoji(c) || isIdeograph2(c))
        return 2;
    return 1;
}


size_t terminalSize(Range)(Range range) if (isGraphemeRange!Range) {
    size_t res = 0;
    for (; !range.empty; range.popFront())
        // foreach (constdd g; r)
        res += range.front.terminalSize;
    return res;
}

size_t graphemeCount(string s)
in {
    assert(!s.hasAnsi, "non ansi expected");
} do {
    return s.byGrapheme.walkLength;
}

bool isSpace(in Grapheme g) {
    return std.uni.isSpace(g[0]);// == ' ';
}

unittest {
    assert("❤️".terminalSize == 2);
    assert("".terminalSize == 0);
    assert("の".terminalSize == 2);
    assert("ż".terminalSize == 1);
    assert("😃".terminalSize == 2);
}
