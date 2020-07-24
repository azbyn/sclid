module graphics.input;

import graphics.inputWindow;
import graphics.graphics;
import misc;
import graphics.window;

class Input : InputWindow!(Yes.hasHorizontal,
                           /*firstIndentAscii = */ "",
                           Yes.drawWhenUnselected,
                           No.hasCompletion,
                           /*initialUsableHeight = */ 2) {
    import std.uni;
    import std.conv, std.string;
    import std.array;
    import std.algorithm;
    import graphics.renderMessage;

    struct InputData {
        string[] lines = [""];
        string[] attachments;
        const(RenderMessage)* replyingMsg;
    }

    import contactsList : GroupOrContact;
    private InputData* currData;
    private InputData[const GroupOrContact] datas;

    protected override @property inout(string)[] lines() inout {
        return currData.lines;
    }
    protected override @property ref string[] lines() {
        return currData.lines;
    }
    protected override @property void lines(string[] val) {
        currData.lines = val;
    }
    void onChangedGoc(in GroupOrContact goc) {
        currData = &datas.require(goc, InputData());
    }

    string replyingInfo() {
        if (currData == null) return "";
        return currData.replyingMsg == null
            ? "" : currData.replyingMsg.sender.theName;
    }

    //TODO make this nicer (with a visualisation and stuff)
    // create a top and bottom offset for the lines in InputWindow
    // so we can show at the bottom the attachments and stuff.
    // (or use a new window)

    this(Graphics parent) {
        enum BorderStyle toplessThick = {
            ls: "┃", rs: "┃", ts: "", bs: " ",
            tl: "", tr: "", bl: " ", br: " ",
        };
        super(parent, toplessThick);
        onChangedGoc(null);//saves some checking TODO hax?
    }

    override void draw() {
        super.draw();
        //draw bar
        //TODO SCROLLING
        auto cursorInfo = format!"%d/%d:%2d"(
            super.getCursorY+1,//it's 0 based and 1 based makes more sense
            super.maxY,
            super.getCursorX
            );
        //we don't care for super small terminal sizes TODO?
        auto cursorWidth = max(cursorInfo.length,
                               "20/20:80".length);
        Line cursor = Line.asciiWithEllipsis(cursorInfo, cursorWidth+1);
        Line attached = Line(win.usableInfoBarWidth / 3);
        Line replying = Line(win.usableInfoBarWidth
                             -attached.maxWidth
                             -cursor.maxWidth
                             -2);//-2 for the separators
        import std.path;
        //hax
        auto data = *currData;
        if (!data.attachments.empty) {
            attached.appendUtfWithEllipsis(format!"Attached %d: %s"(
                                               data.attachments.length,
                                               data.attachments
                                               .shortNiceAttachmentsStr));
        }
        if (!replyingInfo.empty) {
            replying.maxWidth -= 2;//for some nice spacing
            replying.appendAsciiWithEllipsis("Replying to ");
            replying.appendUtfWithEllipsis(replyingInfo);
            replying.maxWidth += 2;
        }

        import graphics.ansi;
        import config;
        enum primaryCol = Color.Blue;
        enum primaryOO = bg(primaryCol)~fg(Color.Black);
        enum replyingBg = bg256(config.niceDarkGray256);

        win.setInfoBarUnsafe(
            attached.flushLeft.with_(primaryOO)
            ~ config.leftSeparator.with_(replyingBg ~ fg(primaryCol))
            ~ replying.centered.with_(replyingBg ~ fg(Color.White))
            ~ config.rightSeparator.with_(replyingBg ~ fg(primaryCol))
            ~ cursor.flushRight.with_(primaryOO),
            fg(primaryCol)~reverse,// fgOnOff(primary), //leftOo
            fg(primaryCol), //rightOO
            //graphics.ansi.reverse(line.flushLeft)
            );
    }

    override ShouldDraw onEscape() {
        parent.selectWindow(parent.messages);
        return ShouldDraw.Yes;
    }

    override ShouldDraw onEnter() {
        auto val = getValue.to!string;
        super.clear();
        parent.man.sendMessage(parent.messages.groupOrContact, val,
                               currData.attachments, currData.replyingMsg);
        currData.attachments = [];
        currData.replyingMsg = null;
        return ShouldDraw.Yes;
    }
    override void onWantsResize(size_t height) {
        parent.resizeInput(height);
    }
    import graphics.windowBase, graphics.keyboard;
    override ShouldDraw loop(const Key key) {
        switch (key) {
        case Key.alt(Key('x')):
            parent.commandMode();
            return ShouldDraw.Yes;
        default:
            break;
        }
        return super.loop(key);
    }
    void onAttachFiles(string[] val) {
        this.currData.attachments = val;
        draw();
    }
    //may be null
    void onReply(in RenderMessage* msg) {
        this.currData.replyingMsg = msg;
    }
    void unreply() {
        onReply(null);
    }
    void editInEditor(string editor) {
        assert(!editor.empty);
        lines = parent.editInEditor(editor, lines);
    }
}
