module graphics.window;
import std.string;
import std.uni;

struct BorderStyle {
    import graphics.utils;
    // if one of these is "" then it's not drawn
    // These MUST have be AT MOST ONE grapheme. ie "" or "1"
    string ls, rs, ts, bs;
    string tl, tr, bl, br;

    invariant () {
        static foreach (m; fields)
            assert(mixin(m~".terminalSize <= 1"));
    }

    enum BorderStyle thick = {
            ls: "┃", rs: "┃", ts: "━", bs: "━",
            tl: "┏", tr: "┓", bl: "┗", br: "┛",
    };

    enum BorderStyle none = {
        ls: "", rs: "", ts: "", bs: "",
        tl: "", tr: "", bl: "", br: "",
    };
    enum fields = ["ls","rs","ts","bs", "tl","tr","bl","br"];
    static foreach (m; fields)
        mixin("bool has"~m.toUpper~"() const { return "~m~".length != 0; }");
}

struct Window {
    import std.traits;
    import std.conv;
    import std.array;

    import graphics.ansi, graphics.utils, graphics.screen;
    private Rect rect_;
    immutable BorderStyle borderStyle;
    private string[] renderLines_;
    string borderColorAnsi = "";

    public const(string[]) renderLines() const { return renderLines_; }
    private string[] renderLines() { return renderLines_; }

    public @property Rect rect() const { return rect_; }
    private @property auto rect(Rect val) { return rect_ = val; }

    auto width()  const { return rect.width; }
    auto height() const { return rect.height; }

    private alias lines = renderLines;
    private alias lines_ = renderLines_;

    // private Screen* s;

    this(Screen* s, BorderStyle borderStyle = borderStyle.thick,
         size_t initialUsableHeight = 0) {
        // this.rect = r;
        this.borderStyle = borderStyle;
        this.rect_.height = initialUsableHeight.to!int + borderHeight;
        // this.s = s;
    }
    long borderWidth() const { return borderStyle.hasLS + borderStyle.hasRS; }
    long usableWidth() const {
        return rect.width - borderWidth;
    }

    long borderHeight() const {
        return borderStyle.hasBS + borderStyle.hasTS;
    }
    long usableHeight() const {
        return rect.height - borderHeight;
    }

    private OnOff borderOnOff() const {
        return OnOff(borderColorAnsi, fgclear);
    }

    void clear() {
        foreach (ref ln; renderLines)
            ln = "";
    }
    void resize(Rect r) {
        this.rect = r;
        this.lines_ = minimallyInitializedArray!(string[])(height);
    }
    void drawTopBottomBorder() {
        immutable borderOnOff = borderOnOff();
        // NOT FULLY CORRECT (about the corners), but it's fewer comparasions
        //  and we don't use those edge cases
        if (borderStyle.hasTS) {
            lines_[0] = borderOnOff(borderStyle.tl ~
                                    borderStyle.ts.replicate(width - 2) ~
                                    borderStyle.tr);
        }

        if (borderStyle.hasBS) {
            lines_[height-1] = borderOnOff(borderStyle.bl ~
                                           borderStyle.bs.replicate(width - 2) ~
                                           borderStyle.br);
        }
    }
    size_t drawingCursor;
    void initDrawingCursor() {
        drawingCursor = borderStyle.hasTS?1:0;
    }

    //all of these return true if we're out of bounds

    auto setCentered(Line ln) { return setLineImpl(ln.centered); }
    alias setLine = setFlushLeft;
    // auto setLine(Line ln) { return setFlushLeft(ln); }
    auto setFlushLeft(Line ln) { return setLineImpl(ln.flushLeft); }
    auto setFlushRight(Line ln) { return setLineImpl(ln.flushRight); }
    private alias setLineImpl = setLineUnsafe;


    //the `Unsafe` part is to remind me that:
    // it assumes the string has a width of exactly `usableWidth`
    // doesn't work to draw on the border.
    bool setLineUnsafe(string s) {
        immutable y = drawingCursor++;
        immutable lastY = height - borderStyle.hasBS;
        if (y >= lastY)
            return true;
        immutable borderOnOff = borderOnOff();
        lines[y] = "";
        if (borderStyle.hasLS)
            lines[y] ~= borderOnOff(borderStyle.ls);
        lines[y] ~= s;
        if (borderStyle.hasRS)
            lines[y] ~= borderOnOff(borderStyle.rs);
        return false;
    }

    auto usableInfoBarWidth() { return width - 2; }
    void setInfoBarUnsafe(string s,
                          OnOff leftOO = ansi.reverse,
                          OnOff rightOO = OnOff()) {
        immutable y = height - 1;
        import config;
        lines[y] = leftOO(config.boxHalfLeft) ~ s ~ rightOO(config.boxHalfRight);
    }

    auto line(string s = "-")
    in {
        assert(s.terminalSize == 1, format!"\"%s\".terminalSize != 1"(s));
    } do {
        return setLineImpl(replicate(s, usableWidth));
    }

    bool fillToBot() {
        while (!setLineUnsafe(" ".replicate(usableWidth))) {}
        return true;
    }
}
