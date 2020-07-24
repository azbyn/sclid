module graphics.contacts;

import graphics.windowBase;
class Contacts : WindowBase {
    alias ansi = graphics.ansi;
    import graphics.utils;
    import graphics.graphics;

    import contactsList, database.messageHistory;
    import misc;

    long cursor = 0;

    const(ContactsList) cl() const { return parent.cl; }
    // const(MessageHistory) history() const { return parent.history; }
    MessageHistory history() { return parent.history; }

    this(Graphics parent) {
        super(parent);
    }
    void onContactsUpdate() {
        draw();
    }

    override void draw() {
        import std.string;
        import std.conv;
        bool withNotif(int localCursor, in GroupOrContact val) {
            int i = history.getUnreadCount(val);
            Line line = Line.asciiWithEllipsis(" ", usableWidth.to!long);
            if (i != 0) {
                line.appendAsciiWithEllipsis(
                    format!"(%d) "(i), ansi.bold);
            }
            line.appendUtfWithEllipsis(val.theName);
            if (localCursor == cursor) {
                return win.setLineUnsafe(ansi.reverse(line.flushLeft));
            } else {
                return win.setLine(line);
            }
        }
        win.initDrawingCursor();
        int localCursor = 0;
        bool addLines(T)(T t) {
            foreach (ref val; t) {
                if (withNotif(localCursor++, val)) return true;
            }
            return false;
        }
        with (win) {
            import std.array;
            //haskell's do notation wouda've been nicer
            do_(
                () => setCentered(
                    Line.asciiWithEllipsis("Contacts", usableWidth, ansi.bold)),
                () => line(),
                () => addLines(cl.contacts),
                () => line(" "),
                () => line(),
                () => setCentered(
                    Line.asciiWithEllipsis("Groups", usableWidth, ansi.bold)),
                () => line(),
                () => addLines(cl.groups),
                () => fillToBot(),
                );
        }
        long i = cursor;
        char c = ' ';
        long max = 0;

        auto clen = cl.contacts.length;
        if (cursor < clen) {
            max = clen;
            c = 'C';
        } else {
            i = cursor-clen;
            max = cl.groups.length;
            c = 'G';
        }

        Line line = Line.utfWithEllipsis(format!"%c %s/%s"(c, i+1, max),
                                         win.usableInfoBarWidth);

        import graphics.ansi;
        win.setInfoBarUnsafe(reverse(line.flushRight));

    }
    import std.typecons;
    override Nullable!Point getGlobalCursorPos() const {
        return Nullable!Point();
    }
    private auto cursorMax() {
        return cl.contacts.length + cl.groups.length;
    }
    import std.algorithm;
    override ShouldDraw loop(const Key key) {
        switch (key.replaceSimilar) {
        case Key.Right:
        case Key.Return:
            select();
            break;
        case Key.Up:   moveY(-1); break;
        case Key.Down: moveY(1); break;
        case Key.Home: cursor = 0; break;
        case Key.End:  cursor = max(cursorMax-1, 0); break;
        default:
            return parent.defaultKeyHandler(key);
        }

        return ShouldDraw.Yes;
    }

    private void moveY(int dy) {
        cursor += dy;
        if (cursor < 0) {
            cursor = 0;
        }
        auto l = cl.contacts.length + cl.groups.length;

        if (cursor >= cursorMax) {
            cursor = max(0, cursorMax- 1);
        }
    }
    private void select() {
        auto clen = cl.contacts.length;
        auto len = cursorMax;// cl.groups.length + clen;
        if (cursor < clen) parent.selectConvo(cl.contacts[cursor]);
        else if (cursor < len) parent.selectConvo(cl.groups[cursor-clen]);
    }
}
