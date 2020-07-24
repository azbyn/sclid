module graphics.windowBase;

import misc;
public import graphics.keyboard;
public import std.typecons;
public import graphics.utils;
public import graphics.graphics : Graphics;
public import graphics.window : BorderStyle;

import graphics.utils;

//pointless, but i can remember later what i can change
enum virtual;

//similar to haskell's do notation for Maybe; all of these must be
// some sort of function that returns bool
bool do_(Ts...)(Ts ts) {
    //the code generated is exactly the same as a || b || c...
    import std.traits;
    static assert(ts.length > 0);
    alias F = ts[0];
    static assert (isSomeFunction!F);
    static assert (is(ReturnType!F == bool));
    static if (ts.length >= 2) {
        return F() || do_(ts[1..$]);
    }
    else return F();
}


enum ShouldDraw { Yes, No }

class WindowBase {
    import graphics.window, graphics.screen;

    alias ansi = graphics.ansi;

    protected Window win;
    protected Graphics parent;
    private Screen* s() { return &parent.screen; }

    static foreach (name; ["renderLines", "rect", "width", "height",
                           "usableHeight", "usableWidth"])
        mixin("final auto " ~name~"() const { return win."~name~"; }");
    // alias win this;
    this(Args...)(Graphics parent, Args args) {
        this.parent = parent;
        this.win = Window(s, args);
    }

    @virtual ShouldDraw loop(Key key) {
        parent.defaultKeyHandler(key);
        return ShouldDraw.No;
    }
    abstract void draw();
    abstract Nullable!Point getGlobalCursorPos() const;

    void resize(Rect r) {
        // d!"resize: %s"(r);
        win.resize(r);
        win.drawTopBottomBorder();
        draw();
    }
    @virtual void onSelect() {
        win.borderColorAnsi = ansi.fgstr(selectedBorderCol);
        win.drawTopBottomBorder();
        draw();
    }
    @virtual void onDeselect() {
        win.borderColorAnsi = "";
        win.drawTopBottomBorder();
        draw();
    }
}
Key replaceSimilar(Key key) {
    switch (key) {
    case 'h':
    case Key.ctrl('b'):
        return Key.Left;
    case 'l':
    case Key.ctrl('f'):
        return Key.Right;
    case 'j':
    case Key.ctrl('n'):
        return Key.Down;
    case 'k':
    case Key.ctrl('p'):
        return Key.Up;
    case Key(' '):
        return Key.Return;
    case Key('g'):
    case Key.alt('<'):
        return Key.Home;
    case Key('G'):
    case Key.alt('>'):
        return Key.End;
    default:
        return key;
    }
}
