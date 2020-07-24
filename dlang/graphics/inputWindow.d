module graphics.inputWindow;

import misc;
public import graphics.windowBase;
public import std.typecons : Yes, No, Flag;

alias HasHorizontal = Flag!"hasHorizontal";
alias DrawWhenUnselected = Flag!"drawWhenUnselected";
alias HasCompletion = Flag!"hasCompletion";

class InputWindow(HasHorizontal hasHorizontal,
                  //for simplicity we just allow ascii
                  string firstIndentAscii, //something like ">>>" like for python
                  DrawWhenUnselected drawWhenUnselected,
                  HasCompletion hasCompletion,
                  size_t initialUsableHeight = 1) : WindowBase {

    //enum hasHorizontal = hasHorizontal_ == HasHorizontal.Yes;
    //enum drawWhenUnselected = drawWhenUnselected_ == DrawWhenUnselected.Yes;

    // assert(!canFindWith!(c =>
    //                   (c & 0x80) != 0 || c == 0x1B)(firstIndentAscii));

    import std.uni, std.algorithm, std.conv, std.array;
    import std.string;
    import graphics.utils;


    private {
        static if (hasHorizontal) {
            //kinda hax - but we only use horizontal in Input
            protected @property abstract inout(string)[] lines() inout;

            protected @property abstract ref string[] lines();
            protected @property abstract void lines(string[] val);

            //string[] lines = [""];
            ref auto line() {
                //todo hax
                if (cursorY >= lines.length) cursorY = lines.length -1;
                return lines[cursorY];
            }
            //
            ref auto line() const {
                //todo hax
                //if (cursorY >= lines.length) cursorY = lines.length -1;
                return lines[min(cursorY, lines.length -1)];
            }
            // this might be bigger than the line width to allow for
            // nicer scrolling
            long cursorX;
            long cursorY;
        //     @property int cursorY() const {
        //         return cursorY_.clamp(0, lines.length-1);
        //     }
        //     @property auto cursorY(int val) { return cursorY_ = val;}
        }
        else {
            string line;
            long cursor;
            alias cursorX = cursor;
        }
    }
    static if (hasCompletion) {
        //show the val in gray starting at x;
        struct CompletionResult {
            const Grapheme[] val;
            long x;

            enum null_ = CompletionResult();
        }
        // if the returned CompletionResult.val == "" then we don't draw anything
        abstract CompletionResult completeAtPoint(in Grapheme[] line, long pos);

        void acceptCompletion() {
            auto graphemes = line.byGrapheme.array;
            auto res = completeAtPoint(graphemes, cursorX);
            if (!res.val.empty) {
                line = (graphemes[0..res.x]~res.val~graphemes[res.x..$])
                    .toStr;
                cursorX = res.x + res.val.length;
            }
        }
    }
    this(Graphics parent, BorderStyle bs) {
        super(parent, bs, initialUsableHeight);
    }
    bool isSelected() const { return parent.currentWin == this; }

    long getCursorX() const {
        return min(cursorX, line.graphemeCount);
    }
    static if (hasHorizontal) {
        long getCursorY() { return cursorY; }
        long maxY() const { return lines.length.to!int; }
    }

    abstract ShouldDraw onEscape();
    abstract ShouldDraw onEnter();
    abstract void onWantsResize(size_t height);

    @virtual override ShouldDraw loop(const Key key) {
        switch (key) {
        case Key.Esc:
        case Key.ctrl('g'):
            auto res = onEscape();
            //ugly hax since we probably change the current window;
            draw();
            return res;
        case Key.Return:
            return onEnter();
        case Key('\n'):
        case Key.alt(Key('m')):
        case Key.alt(Key.Return):
        case Key.alt('\n'):
            addLine();
            break;
        case Key.Left:
        case Key.ctrl(Key('b')):
            moveX(-1);
            break;
        case Key.Right:
        case Key.ctrl(Key('f')):
            moveX(1);
            break;
        case Key.Up:
        case Key.ctrl('p'):
            moveY(-1);
            break;
        case Key.Down:
        case Key.ctrl('n'):
            moveY(1);
            break;
        case Key.Backspace:
        case Key(0x7f):// sent instead of backspace on some terminals
            backspace();
            break;
        case Key.Delete:
        case Key.ctrl(Key('d')):
            del();
            break;

        case Key.CtrlUp: moveBigY!(-1); break;
        case Key.CtrlDown: moveBigY!(1); break;

        case Key.alt(Key('b')):
        case Key.CtrlLeft: moveCursorWord!(-1); break;
        case Key.alt(Key('f')):
        case Key.CtrlRight: moveCursorWord!(1); break;

        case Key.Home:
        case Key.ctrl(Key('a')):
            cursorX = 0;
            break;
        case Key.End:
        case Key.ctrl(Key('e')):
            cursorX = line.graphemeCount.to!int;
            break;
        case Key.PasteEnd:
            dwarn!"PasteEnd without PasteBegin - weird";
            break;
        case Key.PasteBegin: {
            string val = "";
            import graphics.keyboard;

            for (;;) {
                auto k = graphics.keyboard.getkey();
                if (k == Key.PasteEnd || key == Key.Null)
                    break;
                if (k.isNormalChar) {
                    val ~= k.getChar;
                }
            }
            pasteHandler(val);
        } break;
        case Key('\t'):
            static if (hasCompletion)
                acceptCompletion();
            break;
        //meh, I'll leave this in
        case Key.alt(Key('S')):
            addChar('😃');
            break;
        case Key.Null:
            return ShouldDraw.No;
        default:
            if (key.isNormalChar) {
                if (isGraphical(key.getChar))
                    addChar!(IncrementCursor.Yes)(key.getChar);
                //else if (key != Key(0))
                    //dlog!"Non graphical %x"(key.getChar);
            }
        }
        // draw();
        return ShouldDraw.Yes;
    }

    private Point graphicalCursor;
    override void draw() {
        win.initDrawingCursor();

        static if (!drawWhenUnselected) {
            if (!isSelected) {
                win.fillToBot();
                return;
            }
        }
        long wantedHeight = 0;

        //if it's first line we assume str contains firstIndentAscii
        Point cursorPosInLine(const(Grapheme)[] graphemes, long cursorX) {
            //it's important that we only work with grapheme count
            size_t subLineStart;//offset into graphemes
            long y = 0;
            for (;;) {
                //the only way we indirectly use grapheme width
                auto res = sublineWithSize(graphemes, usableWidth,
                                           GraphemeLine());
                auto sublineLen = res.val.arr.length;
                long/* size_t*/ cursorOffset = cursorX - subLineStart;
                if (cursorOffset < 0) {
                    dwarn!"this should never happen^TM";
                    return Point(0, y);
                }

                if (cursorOffset < sublineLen) {
                    auto x = res.val.arr[0..cursorOffset].
                        map!(v=>v.ts).sum;
                    return Point(x, y);
                } else if (res.remaining.length == 0 &&
                           cursorOffset >= sublineLen) {
                    return Point(res.val.width, y);
                }
                graphemes = graphemes[sublineLen..$];
                subLineStart += sublineLen;
                ++y;
            }
        }

        static if (hasHorizontal) {
            assert(lines.length > 0, "lines length expected to be > 0");
            foreach(i, ln; lines) {
                if (i == 0)
                    ln = firstIndentAscii ~ ln;

                auto graphemes = ln.byGrapheme.array;
                immutable setCursor = i == cursorY;

                if (setCursor) {
                    //TODO autocomplete thing
                    graphicalCursor = cursorPosInLine(graphemes, cursorX);
                    graphicalCursor.y += wantedHeight + win.borderStyle.hasTS;
                    graphicalCursor.x += win.borderStyle.hasLS;
                }
                auto res = sublineWithSize(graphemes, usableWidth);

                for (;;) {
                    win.setLine(res.val);
                    ++wantedHeight;
                    if (res.remaining.empty)
                        break;
                    res = sublineWithSize(res.remaining, usableWidth,
                                          Line(usableWidth));
                }
            }
        } else {
            auto ln = firstIndentAscii ~ line;
            const(Grapheme)[] graphemes = ln.byGrapheme.array;


            //TODO this way is just easier for our use case
            // we _could_ `cursorPosInLine` more robust, but we don't
            // really need it anywhere else
            graphicalCursor = cursorPosInLine(
                graphemes, cursorX + firstIndentAscii.length.to!int);
            graphicalCursor.y += wantedHeight + win.borderStyle.hasTS;
            graphicalCursor.x += win.borderStyle.hasLS;
            static if (hasCompletion) {
                auto completionRes = completeAtPoint(
                    graphemes[firstIndentAscii.length..$],//skip the first thing
                    cursorX);
                import config;
                if (!completionRes.val.empty) {
                    completionRes.x += firstIndentAscii.length;
                    graphemes = graphemes[0..completionRes.x]
                        ~ Grapheme(ansi.fg256str(config.niceLighterGray256).to!dstring)//0 width
                        ~ completionRes.val
                        ~ Grapheme(ansi.fgclear.to!dstring)//0 width
                        ~ graphemes[completionRes.x..$];
                }
            }

            auto res = sublineWithSize(graphemes, usableWidth);

            for (;;) {
                win.setLine(res.val);
                ++wantedHeight;
                if (res.remaining.empty)
                    break;
                res = sublineWithSize(res.remaining, usableWidth,
                                      Line(usableWidth));
            }
        }

        wantedHeight = max(wantedHeight,
                           initialUsableHeight) + win.borderHeight;

        if (wantedHeight != height) {
            onWantsResize(wantedHeight);
        }
        else
            win.fillToBot();
    }

    override Nullable!Point getGlobalCursorPos() const {
        return (win.rect.p0 + graphicalCursor).nullable;
    }

    string getValue() const {
        static if (!hasHorizontal) {
            return line;
        } else {
            return lines.join("\n");
        }
    }
    enum IncrementCursor { Yes, No }
    void addChar(IncrementCursor increment = IncrementCursor.Yes)(dchar c) {
        // dlog!"addc start";
        auto graphemes = line.byGrapheme.array;
        cursorX = cursorX.clamp(0, graphemes.length.to!int);
        graphemes.insertInPlace(cursorX, Grapheme(c));
        static if (increment == IncrementCursor.Yes)
            ++cursorX;
        line = graphemes.toStr;
    }

    //returns true if at the begining or end of lines
    bool moveX(int dx) {
        cursorX += dx;
        auto graphemeCount = line.graphemeCount.to!int;
        static if (hasHorizontal) {
            if (cursorX < 0) {
                if (cursorY > 0) {
                    --cursorY;
                    //new line, new grapheme count
                    cursorX = line.graphemeCount.to!int;
                }
                else {
                    cursorX = 0;
                    return true;
                }
            }
            else if (cursorX >= graphemeCount) {
                if (cursorY < lines.length-1) {
                    ++cursorY;
                    cursorX = 0;
                }
                else {
                    auto res = cursorX > graphemeCount;
                    cursorX = graphemeCount;
                    return res;
                }
            }
        } else {
            if (cursorX < 0) {
                cursorX = 0;
                return true;
            } else if (cursorX > graphemeCount) {
                cursorX = graphemeCount;
                return true;
            }
        }
        return false;
    }
    void backspace() {
        void deleteLine() {
            static if (hasHorizontal) {
                if (cursorY > 0) {
                    cursorX = lines[cursorY-1].graphemeCount.to!int;
                    lines[cursorY-1] ~= lines[cursorY];
                    lines = lines.remove(cursorY--);
                }
            }
        }
        if (cursorX == 0) {
            deleteLine();
        } else {
            auto graphemes = line.byGrapheme.array;
            static if (hasHorizontal) {
                if (cursorX > graphemes.length)
                    return deleteLine();
            }
            cursorX = min(cursorX,
                          graphemes.length);
            graphemes = graphemes.remove(--cursorX);
            line = graphemes.toStr;
        }
    }
    void del() {
        // a lot simpler than reimplementing it
        if (!moveX(1))
            backspace();
        /*auto graphemes = line.byGrapheme.array;
        if (cursorX < graphemes.length) {
            graphemes = graphemes.remove(cursorX);
            line = graphemes.toStr;
        } else {
            static if (hasHorizontal) {
                if (cursorY != lines.count) {
                    //cursorX = lines[cursorY].graphemeCount.to!int;
                    lines[cursorY] ~= lines[cursorY+1];
                    lines = lines.remove(cursorY+1);
                }
            }
            }*/
    }
    void clear() {
        static if (hasHorizontal)
            cursorY = 0;
        static if (hasHorizontal)
            lines = [[]];
        else
            line = [];
        if (usableHeight != initialUsableHeight)
            onWantsResize(initialUsableHeight+win.borderHeight);
        cursorX = 0;
    }

    void moveY(int dy) {
        static if (hasHorizontal) {
            cursorY += dy;
            cursorY = cursorY.clamp(0, lines.length-1);

            //not doing this makes for a nicer scrolling
            // cursorX = cursorX.clamp(0, line.length);
        }
    }
    void addLine() {
        static if (hasHorizontal) {
            auto graphemes = line.byGrapheme.array;
            //the cursor might be somewhere weird
            cursorX = cursorX.clamp(0, line.length);

            auto arr = graphemes[cursorX..$].toStr;
            line = graphemes[0..cursorX].toStr;
            lines.insertInPlace(++cursorY, arr);
            cursorX = 0;
        }
    }
    void moveBigY(int delta)() {
        static if (hasHorizontal) {
            if (delta == -1) cursorY = 0;
            else cursorY = lines.length.to!int - 1;
            cursorX = cursorX.clamp(0, line.length);
        }
    }
    void moveCursorWord(int delta)() {
        //move till first non space
        //then move to the first space
        immutable graphemes = line.byGrapheme.array;
        immutable graphemeCount = graphemes.length;
        import graphics.graphemeUtils;
        static if (delta == 1) {
            static if (hasHorizontal) {
                if (cursorX == graphemeCount) {
                    moveX(1);
                    return;
                }
            }
            for (;;) {
                if (cursorX >= graphemeCount) return;
                if (!graphemes[cursorX].isSpace) break;
                cursorX += delta;
            }
            for (;;) {
                if (cursorX >= graphemeCount-1) {
                    cursorX = graphemeCount.to!int;
                    return;
                }
                cursorX += delta;
                if (graphemes[cursorX].isSpace) break;
            }
        }
        else {
            static if (hasHorizontal) {
                if (cursorX == 0) {
                    moveX(-1);
                    return;
                }
            }
            if (cursorX == line.length) {
                if (line.length == 0) return;
                cursorX--;
            }
            if (cursorX == 0) return;
            --cursorX;
            for (;;) {
                if (cursorX == 0) return;
                if (!graphemes[cursorX].isSpace) break;
                cursorX += delta;
            }
            for (;;) {
                if (cursorX == 0) return;
                if (graphemes[cursorX].isSpace) {
                    moveX(-delta);
                    break;
                }
                cursorX += delta;
            }
        }
    }

    void pasteHandler(string val) {
        //very dumb, could be a lot more effcient
        foreach (g; val.byGrapheme) {
            foreach (dchar dc; g[0..g.length-1]) {
                addChar!(IncrementCursor.No)(dc);
            }
            dchar c = g[g.length-1];
            if (c== '\n' || c == '\r')
                addLine();
            else
                addChar!(IncrementCursor.Yes)(g[g.length-1]);
        }
    }
}
