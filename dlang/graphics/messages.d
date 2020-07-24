module graphics.messages;

import graphics.windowBase;
import graphics.graphics;
import misc;
import std.datetime.systime;// : Clock;

string niceTimeFormat(SysTime then, SysTime now) {
    import std.string : format;
    auto delta = now - then;
    string res = "";
    import config;
    if (then.dayOfYear == now.dayOfYear && then.year == now.year) {
        res = config.todayName;
    } else {
        auto deltaDays = delta.total!"days";
        if (deltaDays > 6)
            res = format!"%d %s"(then.day, then.month.shortMonthName);
        else
            res = format!"%s"(then.dayOfWeek.shortWeekDayName);
        if (then.year != now.year) {
            res ~= format!".%d"(then.year);
        }
    }
    return format!"%s, %d:%02d"(res, then.hour, then.minute);
}

string getLatestVersion() {
    import config;
    import std.net.curl, std.regex;
    enum url = "https://raw.githubusercontent.com/azbyn/sclid/master/dlang/theVersion.d";

    try {
        auto val = get(url);
        auto res = matchFirst(val, ctRegex!`\d+\.\d+\.\d+`);
        if (res)
            return res.hit.idup;
        derr!"found invalid version: '%s'"(val);
    } catch (CurlException e) {
        derr!"can't find the latest version. %s"(e.msg);
    }
    return config.theVersion;
}
//taken from stack overflow
int versionCompare(string v1, string v2) {
    size_t i=0, j=0;
    while( i < v1.length || j < v2.length) {
        int acc1=0, acc2=0;

        while (i < v1.length && v1[i] != '.') {  acc1 = acc1 * 10 + (v1[i] - '0');  i++;  }
        while (j < v2.length && v2[j] != '.') {  acc2 = acc2 * 10 + (v2[j] - '0');  j++;  }

        if (acc1 < acc2)  return -1;
        if (acc1 > acc2)  return +1;

        ++i;
        ++j;
    }
    return 0;
}
static assert(versionCompare("0.0.1", "0.0.2") < 0);

class Messages : WindowBase {
    import std.conv;
    import contactsList;
    import database.messageHistory, graphics.renderMessage;
    import imgDisplay;
    import std.string;
    import fullMessage : SignalTime;
    alias ansi = graphics.ansi;

    import pragmaMsg;

    private Rebindable!(const(GroupOrContact)) groupOrContact_;
    private auto history() { return parent.history; }
    private ImgDisplay imgDisp;
    PragmaManager pragmaManager;

    private RenderMessage[] messagesFromGroup;

    //warning may be null
    const(RenderMessage)* currentMessage() const {
        if (messagesFromGroup.empty) return null;
        return &messagesFromGroup[currCursor.index];
    }

    Cursor* currCursor;
    Size fontSize;

    Cursor[const GroupOrContact] cursors;


    this(Graphics parent) {
        import graphics.window;

        enum BorderStyle bottomlessThick = {
            ls: "┃", rs: "┃", ts: "━", bs: " ",
            tl: "┏", tr: "┓", bl: " ", br: " ",
        };
        super(parent, bottomlessThick);
        this.groupOrContact_ = null;
        this.imgDisp = new ImgDisplay;
        this.pragmaManager = new PragmaManager();

    }

    @property auto groupOrContact() { return groupOrContact_; }
    @property void groupOrContact(in GroupOrContact val) {
        this.groupOrContact_ = val;
        this.messagesFromGroup = history.messagesFrom(val);
        this.currCursor = &cursors.require(
            val, Cursor(this, history.getConvoInfo(val),
                        this.messagesFromGroup));
        parent.input.onChangedGoc(val);
        this.recenterState = RecenterState.Default;
        if (!messagesFromGroup.empty) {
            //TODO not the index, but the bottom most one?
            onReadMessage(messagesFromGroup[currCursor.index]);
        }
    }
    private void makeMessagesDirty() {
        //removes the precalculated lines
        //this could be nicer, we don't have to get all of them
        messagesFromGroup = history.messagesFrom(groupOrContact);
        currCursor.onNewMessage(messagesFromGroup);
    }

    override void resize(Rect r) {
        if (groupOrContact_ != null)
            makeMessagesDirty();
        fontSize = parent.screen.fetchFontSize();
        //dlog!"fontSize = %s"(fontSize);
        super.resize(r);
    }
    //called from Cursor mainly
    void onReadMessage(in RenderMessage m) {
        //dlog!"update thing '%s' - "(m.message);
        parent.history.updateConvoInfo(groupOrContact, m, messagesFromGroup);
    }

    void onReadMessage(long index) {
        if (messagesFromGroup.empty)
            return;
        onReadMessage(messagesFromGroup[index]);
    }

    override Nullable!Point getGlobalCursorPos() const {
        return Nullable!Point();
    }
    void selectConvo(in GroupOrContact goc) {
        //TODO
        this.groupOrContact = goc;
        parent.input.draw();
        //we don't call draw because Graphics calls it for us in onSelect
    }
    void updateConvo(in GroupOrContact sender) {
        if (groupOrContact == sender) {
            makeMessagesDirty();
            draw();
        }
    }
    private enum RecenterState {
        Default = 0,
        Bot = 0,
        Center = 1,
        Top = 2,
    }
    private RecenterState recenterState = RecenterState.Default;
    override ShouldDraw loop(const Key key) {
        //assert(groupOrContact_ != null,
        //       "This can't be selected without seting a goc first");
        if (groupOrContact_ == null) {
            if (key.replaceSimilar == Key.Left)
                parent.selectWindow(parent.contacts);
            return ShouldDraw.Yes;
            }
        RecenterState newRecenterState = RecenterState.Default;
        switch (key.replaceSimilar) {
        case Key.Left:
            parent.selectWindow(parent.contacts);
            break;
        case Key('i'):
        case Key('I'):
        case Key.Return:
            parent.selectWindow(parent.input);
            break;
        case Key('y'):
        case Key.alt(Key('w')):
            parent.minibuffer.copy(this);
            break;
        case Key.ctrl(Key('l')):
            //dumber version of emacs' C-l
            newRecenterState = cast(RecenterState) (
                (cast(int) recenterState +1) % 3);
            currCursor.recenterTopBot(newRecenterState);
            break;
        case Key('r'):
            parent.minibuffer.reply(this);
            break;
        case Key.Down: currCursor.move(1); break;
        case Key.Up: currCursor.move(-1); break;

        case Key.Home: currCursor.moveExtremity(-1); break;
        case Key.End: currCursor.moveExtremity(1); break;

            //TODO move page wise (ie ctrl+v, alt+v)
            //todo move halfPage
        default:
            return parent.defaultKeyHandler(key);
        }
        recenterState = newRecenterState;
        return ShouldDraw.Yes;
    }

    //ie where the message drawing begins - should be 3
    private long cachedFirstMsgLine;
    private Cursor.Top cachedCursorTop;

    enum string[] helpMessageParagraphs = [
        //todo
        "<btw, at the moment there's no scrolling here, so please "
        ~"just make your window larger if you can't see the \"- azbyn\" "
        ~"at the end of this. sorry for the inconvenience>",


        "First thing you should probably do, if you haven't already, "
        ~"is sync your contacts. You can do that with by pressing "
        ~": then typing sync, then enter.",

        "When writing a message, pressing : won't enter command mode, it "
        ~"will insert a \":\", you can either press escape (or Ctrl-g) to "
        ~"exit input mode, then press :, or you can use Alt-x. Alt-x works "
        ~"everywhere, including input mode.",

        "If you came here to read one of those messages with all the "
        ~"diacritics and cyrillic/greek letters "
        ~"(if you don't know what that is, just ignore this paragraph), "
        ~"you should redirect that message to self from your phone or "
        ~"whatever (long press, right arrow at the top => share with) "
        ~"so that you see it in sclid. "
        ~"(due to security reasons, Signal doesn't give you your history "
        ~"from old devices when connecting to a new device. there are ways "
        ~"around that - doing a backup, but I haven't implemented that yet, "
        ~"so don't worry about it <insert tofuchan>).",

        "Don't worry about not reading the whole thing, this will show up "
        ~"again when you open sclid.",

        "Btw, do complain if this is hard to understand.",
    ];

    override void draw() {
        imagesDirty = true;
        if (groupOrContact_ == null) {
            import config;
            void addEmptyLine() {
               win.setFlushRight(Line(usableWidth));
            }
            void addLine(string line) {
                import std.uni, std.array;
                const(Grapheme)[] graphemes = line.byGrapheme.array;
                immutable actualWidth = usableWidth-2;//for some nice spaces
                while (!graphemes.empty) {
                    auto res = sublineBySpace(graphemes, actualWidth);
                    graphemes = res.remaining;
                    win.setLineUnsafe(
                        " "~res.val.toLineUnsafe(actualWidth).flushLeft~" ");
                }
            }
            with (win) {
                initDrawingCursor();

                import graphics.ansi;
                addLine("Здравствуйте, welcome to sclid version "
                        ~theVersion~",");
                static if (config.checkForNewVersion) {
                    auto newVersion = getLatestVersion();
                    if (versionCompare(theVersion, getLatestVersion) < 0) {
                        addEmptyLine();
                        addLine(format!"btw, version %s is out."(newVersion));
                        //todo better way of updating
                        addLine("Simplest way i can think of updating is you "
                                ~"`git clone https://github.com/azbyn/sclid` "
                                ~"again, then you replace the dlang/config.d "
                                ~"then build as usual.");
                    }
                }
                addEmptyLine();
                foreach (par; helpMessageParagraphs) {
                    //mongolian vowel separator - hax to show leading spaces
                    addLine("\u180e   "~par);
                    addEmptyLine();
                }

                setFlushRight(Line.utfWithEllipsis("- azbyn ", usableWidth));

                //here so that there's not an empty place there
                setInfoBarUnsafe(Line(usableInfoBarWidth).flushLeft
                                 .with_(reverse));
                fillToBot();
            }
            return;
        }
        auto now = Clock.currTime();
        with(win) {
            initDrawingCursor();
            // dlog!"draw";
            do_(
                () {
                    auto line = Line.utfWithEllipsis(groupOrContact.theName,
                                                     usableWidth, ansi.bold);

                    //todo - don't repeat the stuff in contacts
                    auto i = history.getUnreadCount(groupOrContact);

                    if (i != 0) {
                        line.appendAsciiWithEllipsis(
                            format!" (%d)"(i), ansi.bold);
                        // it can't be thaaat short so we don't call
                        // printTruncatedEllipsis
                        // printWith(format!"(%d) "(i), A_BOLD);
                    }
                    return setCentered(line);
                },
                () => line(),
                () {
                    cachedFirstMsgLine = win.drawingCursor;
                    if (messagesFromGroup.empty) {
                        import std.array;
                        return setLineUnsafe(
                            ansi.reverse(" ".replicate(usableWidth)));
                    }
                    int y = 0;
                    //str width must be usableWidth
                    //this draws a line at the cursor if necessary
                    auto drawLineWithCursor(string str) {
                        if (currCursor.relative == y) {
                            str = ansi.reverse(str);
                        }
                        y++;
                        return setLineUnsafe(str);
                    }
                    auto top = currCursor.calculateTop();
                    cachedCursorTop = top;

                    auto topMsg = getMessagesFromGroupLines(top.index);

                    foreach (ln; topMsg[top.offset..$]) {
                        if (drawLineWithCursor(ln)) return true;
                    }
                    for (long i = top.index + 1; i < messagesCount; ++i) {
                        auto startY = win.drawingCursor;
                        foreach (ln; getMessagesFromGroupLines(i))
                            if (drawLineWithCursor(ln)) return true;
                    }
                    return false;
                },
                () {
                    return fillToBot();
                },
            );
        }
        drawInfoBar(now);
    }

    auto messagesCount() { return messagesFromGroup.length; }

    auto usableMsgHeight() {
        return usableHeight-2;//-2 for the title and the line
    }
    private void drawInfoBar(SysTime now) {
        import config;
        import std.algorithm;
        //the fact that ths doesn't introduce a scope is awesome
        alias cc = currCursor;
        //auto cursorInfo = format!"%d/%d off: %d; rel %d"
        //    (cc.index+1, messagesCount/, cc.messageOffset, cc.relative);
        auto cursorInfo = format!"%d/%d"(cc.index+1, messagesCount);
        auto cursorWidth = max(cursorInfo.length,
                               "123/321".length);

        // bool hasNewMessages = true;

        Line cursor = Line.asciiWithEllipsis(cursorInfo, cursorWidth+1);
        // Line newMessagesInfo = hasNewMessages
        //     ? Line.asciiWithEllipsis(
        //         " = NEW MESSAGES = ",
        //         " = NEW MESSAGES = ".length,//todo hax
        //         ansi.fg(ansi.Color.Red)~ ansi.bg(ansi.Color.Yellow))
        //     : Line(0);
        Line info = Line.asciiWithEllipsis(
            " ",
            win.usableInfoBarWidth
            - cursorWidth
            //- newMessagesInfo.width
            - 2);//-1 for separators, -1 for a nice space

        if (!messagesFromGroup.empty) {
            info.appendUtfWithEllipsis(
                niceTimeFormat(currentMessage.timestamp, now));
            auto imgDatas = currentMessage.getImgDatasUnsafe;
            if (!imgDatas.empty) {
                info.appendUtfWithEllipsis(" "~ leftSeparatorThin~" ");
                info.appendUtfWithEllipsis(
                    format!"Images: %s"(imgDatas.map!(x=>x.path)
                                        .shortNiceAttachmentsStr));
            }
        }

        import graphics.ansi;
        alias ansi = graphics.ansi;
        import config;
        //TODO add this to config or smth
        enum primaryCol = Color.Blue;
        enum primaryOO = bg(primaryCol)~fg(Color.Black);
        enum restBg = bg256(config.niceDarkGray256);
        win.setInfoBarUnsafe(
            info.flushLeft.with_(restBg ~ fg(Color.White))
            //~ newMessagesInfo.centered//.with_(restBg)
            ~ config.rightSeparator.with_(restBg ~ fg(primaryCol))
            ~ cursor.flushRight.with_(primaryOO),
            fg256(config.niceDarkGray256) ~ansi.reverse,//leftOo
            fg(primaryCol), //graphics
            );
    }

    bool imagesDirty = true;
    void drawImages() {
        if (!imagesDirty) return;
        imgDisp.clearAll();
        scope(exit) imgDisp.flush();
        scope(exit) imagesDirty = false;
        if (messagesFromGroup.empty) {
            return;
        }
        auto startY = cachedFirstMsgLine;

        const top = cachedCursorTop;

        auto getX(in RenderMessage m) {
            enum padding = 3; //we have 2 borders, so 2, and 1 for a space
            return rect.x + (m.isOnTheLeft ? padding :
                             this.width - m.msgUsableWidth
                             - padding);
        }
        import std.algorithm;
        auto lastY = this.height - 1;// -1 for the infobar


        //so that i don't have to put `top` in front of everything
        bool drawTopMsg(bool incrementStart)(in RenderMessage m) {
            long offset = top.offset - m.firstImgLine;
            //if this is <= 0, we draw all the images (if present)
            //if this is > 0 we draw all the images from firstIndex onwards
            const imgDatas = m.getImgDatasUnsafe;
            long firstIndex = imgDatas.length;
            long firstY = m.firstImgLine;

            foreach (i, img; imgDatas) {
                if (firstY >= top.offset) {
                    firstIndex = i;
                    break;
                }
                firstY += img.termHeight;
            }

            firstY -= top.offset;
            firstY += startY;

            immutable x = getX(m);
            for (long i = firstIndex; i < imgDatas.length; ++i) {
                const img = imgDatas[i];
                auto y = firstY;
                firstY += img.termHeight;
                if (firstY > lastY) return true;
                imgDisp.addImg(imgDatas[i], Pos(x, y), fontSize);
            }

            static if (incrementStart)
                startY += m.renderHeightUnsafe - top.offset;
            return false;
        }

        const firstMsg = messagesFromGroup[top.index];
        if (firstMsg.quotedMessage != null) {
            if (drawTopMsg!false(*firstMsg.quotedMessage)) return;
        }
        if (drawTopMsg!true(firstMsg)) return;

        //returns true if it runs out of space (ie y > lastY);
        bool addDatas(in RenderMessage m) {
            immutable x = getX(m);
            const imgDatas = m.getImgDatasUnsafe;
            auto firstY = startY + m.firstImgLine;
            foreach (img; imgDatas) {
                auto y = firstY;
                firstY += img.termHeight;
                if (firstY > lastY) return true;
                imgDisp.addImg(img, Pos(x, y), fontSize);
            }

            return false;
        }

        for (long i = top.index + 1; i < messagesCount; ++i) {
            const m = messagesFromGroup[i];

            if (m.quotedMessage != null) {
                if (addDatas(*m.quotedMessage)) return;
            }

            if (addDatas(m)) return;

            startY += m.renderHeightUnsafe;
            if (startY > lastY) return;
        }
    }

    const(string)[] getMessagesFromGroupLines(long i) {
        return getLines(messagesFromGroup[i]);
    }

    const(string)[] getLines(ref RenderMessage m) {
        return m.getLines(usableWidth, parent.cl, fontSize,
                          pragmaManager);
    }

    static struct Cursor {
        long relative = 0;      // relative to top of the file
        long index_ = 0;         // which message are we on top of
        long messageOffset = 0; // how far into that message ar we

        @property long index() const { return index_; }
        @property auto index(long val) {
            return this.index_ = val;
        }
        void parentOnRead(long val) {
            if (parent.currCursor == &this && messagesCount > 0) {
                parent.onReadMessage(val);
            }
        }

        Messages parent;

        this(Messages parent, in ConvoInfo ci, in RenderMessage[] sortedMessages) {
            this.parent = parent;
            this.index_ = sortedMessages.findLastIndex!(
                x => x.timestamp < ci.lastRead)+1;
            // import std.algorithm;
            if (this.index == 0) return;
            this.relative = -1;// parent.usableMsgHeight;
            this.messageOffset = -1;//will be set in calculateTop
        }
        auto messagesCount() const { return parent.messagesFromGroup.length; }

        //todo?
        /*void onResize() {
            if (this.messageOffset)
            }*/

        void onNewMessage(in RenderMessage[] sortedMessages) {
            //could be improved - like if we're not exactly at the bot or smth
            if (index == sortedMessages.length-2) {
                //this.messageOffset = -1;
                //dlog!"relative = -1";
                this.relative = -1;
                ++index_;
            }
            else {
                return;
            }
            this.messageOffset = -1;

            import std.range;
            if (parent.currCursor == &this)
                parent.onReadMessage(sortedMessages.back);
        }

        struct Top {
            long index;// which is the first message
            long offset;//how far into that message are we
        }
        import config;
        void recenterTopBot(RecenterState state) {
            final switch (state) {
            case RecenterState.Center:
                relative = parent.usableMsgHeight/2;
                break;
            case RecenterState.Top:
                relative = config.mainScrollOffset;
                break;
            case RecenterState.Bot:
                relative = parent.usableMsgHeight - 1
                    - config.mainScrollOffset;
                break;
            }
        }
        //not const since we may reset if the state is wrong
        Top calculateTop() {
            //hax since we can't initialize it to the width in Main's constructor
            //(since widths aren't yet set)
            if (this.relative < 0|| this.relative >= parent.usableMsgHeight) {
                this.relative = parent.usableMsgHeight -1;
            }
            if (this.messageOffset < 0) {
                assert(index < messagesCount);
                this.messageOffset =
                    parent.getMessagesFromGroupLines(index).length-1;
            }
            auto relativeI = relative - messageOffset;
            auto i = index-1;// messageOffset-1;

            for (;;) {
                if (relativeI < 0) {
                    ++i;
                    break;
                }
                if (i < 0) {
                    //this is normal behavior, this may happen after for
                    //example, when we press End and we don't have many
                    //messages
                    relative -= relativeI;
                    i = 0;
                    relativeI = 0;
                    break;
                }
                auto currentHeight = parent.getMessagesFromGroupLines(i).length;
                relativeI -= currentHeight;
                --i;
            }
            return Top(i, -relativeI);
        }

        void move(int dy) {
            if (messagesCount == 0) {
                messageOffset = 0;
                index = 0;
                relative = 0;
                return;
            }
            messageOffset += dy;
            auto msgHeight = parent.getMessagesFromGroupLines(index).length;
            //one of the (only) situations where being 0 based kinda coplictes
            //things
            if (messageOffset < 0) {
                // dlog!"idx = %d "(index);
                if (index == 0) {
                    messageOffset = 0;
                    return;
                }
                --index_;//-=1;
                if (index < 0) {
                    index_ = 0;
                }
                //new index, new msgHeight
                messageOffset =
                    parent.getMessagesFromGroupLines(index).length-1;
                parentOnRead(index);
            }
            else if (messageOffset >= msgHeight) {
                //dlog!"biggr %d"();
                ++index_;
                if (index >= messagesCount) {
                    index_ = messagesCount-1;
                    messageOffset = msgHeight-1;
                    return;
                }
                parentOnRead(index);
                messageOffset = 0;
            }
            import config;

            relative += dy;
            if (relative < 0) {
                relative = 0;
            }
            else if (relative >= parent.usableMsgHeight) {
                relative = parent.usableMsgHeight-1;
            }
            //TODO scroll offset
            /*
            static assert(mainScrollOffset <= 2,//TODO remove limitation
                          "we have this max scroll because it makes "~
                          "things easier because we assume a message is at "~
                          "least 2 lines long.");
            relative += dy;
            if (relative < mainScrollOffset) {
                if (index == 0 && messageOffset < mainScrollOffset) {
                    if (relative < 0) relative = 0;
                }
                else {
                    relative = mainScrollOffset;
                }
            }
            else if (relative >= parent.usableHeight - mainScrollOffset) {
                if (index == messagesCount-1
                && (messageOffset < msgHeight - mainScrollOffset)) {
                    if (relative >= parent.usableHeight - 1) {
                        relative = parent.usableHeight;
                    }
                } else {
                    relative = msgHeight.to!int - mainScrollOffset;
                }
            }*/
        }

        void moveExtremity(int dy) {
            import std.algorithm;
            auto height = parent.usableMsgHeight;
            if (dy < 0 || parent.messagesFromGroup.empty) {
                relative = 0;
                messageOffset = 0;
                index = 0;
            } else {
                relative = height - 1;
                index = messagesCount - 1;
                messageOffset =
                    parent.getMessagesFromGroupLines(index).length-1;
                parentOnRead(index);
            }
        }
    }
}
