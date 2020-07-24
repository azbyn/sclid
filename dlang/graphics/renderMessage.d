module graphics.renderMessage;

import std.typecons;
import std.traits;
import contactsList;
import config;
import fullMessage;
import database.messageHistory;
import misc;
import database.misc;
import std.json;
import imgDisplay;

alias StickerPath = Nullable!string;
struct RenderMessage {
    import std.datetime.systime;
    import graphics.utils;
    alias Id = MessageHistory.MessageId;

    struct Reaction {
        const Contact sender;
        string emoji; //can't be empty
    }

    Id id;

    enum Type { Receive, Send }

    Type getType(in ContactsList cl) const {
        return sender == cl.thisUser ? Type.Send : Type.Receive;
    }
    const Contact sender;

    bool isPlaceholder;
    // bool hasPreview;

    SysTime timestamp;//() { return signalTime.toSystime; }
    //easier than converting. TODO-?
    SignalTime signalTime;
    string message;
    string[] attachments;
    Reaction[] reactions;

    // we'll allocate this one on the heap
    RenderMessage* quotedMessage;
    //Nullable!RenderMessage quotedMessage;
    //Nullable!(HistoryMessage.)
    StickerPath stickerPath;

    //where text ends and the imgDatas begin
    size_t firstImgLine;

    private string[] renderLines;
    private ImgData[] imgDatas;
    long msgUsableWidth;
    bool isOnTheLeft;

    bool isPrecalculated() const { return renderLines.length != 0; }

    mixin(genToString!RenderMessage);
    /*this(ref return scope inout(RenderMessage) src) inout {
        foreach (i, ref inout field; src.tupleof)
            this.tupleof[i] = field;
    }*/

    this(in RenderMessage src)  {
        import std.traits;
        alias F = Fields!RenderMessage;
        quotedMessage = null;
        static foreach (i, name; FieldNameTuple!RenderMessage) {
            static if (name!="quotedMessage") {
                static if (isArray!(F[i]))
                    mixin("this."~name~"=src."~name~".dup;");
                else
                    mixin("this."~name~"=src."~name~";");
            }
        }
    }

    //must be called after getLines
    auto getImgDatasUnsafe() const {
        assert(isPrecalculated);
        return imgDatas;
    }
    auto renderHeightUnsafe() const {
        assert(isPrecalculated);
        return renderLines.length;
    }

    //sigh, we can only initialize const this way
    private this(const Contact sender) { this.sender = sender; }

    this(MessageHistory.Message val,
         scope MessageHistory history,
         scope ContactsList cl,
         in RenderMessage[] prevMessages)
    {
        this(cl.getContact(val.senderName));
        this.initImpl!(false)(val, history, cl, prevMessages);
    }

    private void initImpl(bool isQuote)(MessageHistory.Message val,
                                        scope MessageHistory history,
                                        scope ContactsList cl,
                                        in RenderMessage[] prevMessages) {
        import std.algorithm, std.array;
        //val.convoId;
        this.id = val.id;

        //this.sender = cl.getContact(val.senderName);
        static if (!isQuote) {
            if (val.hasAttachments) {
                auto v = history.getAttachments(val.id);
                this.attachments = v;
            }
        }
        this.isPlaceholder = val.isPlaceholder;
        // this.hasPreview = val.hasPreview;
        this.signalTime = val.timestamp;
        this.timestamp = val.timestamp.toSystime;
        this.message = val.message;
        static if (!isQuote) {
            this.reactions = history.findReactions(val.id)
                .filter!(x=>x.emoji != "")
                .map!(x => Reaction(cl.getContact(x.senderName), x.emoji)).array;


            RenderMessage* fromQuote(Nullable!(MessageHistory.Message) val) {
                if (val.isNull) return null;

                //TODO binary search?
                foreach (m; prevMessages) {
                    if (m.id == val.get.id) {
                        return new RenderMessage(m);
                        //dlog!"found !";
                    } else if (m.id.val > val.get.id.val) {
                        break;
                    }
                }

                RenderMessage* res = new RenderMessage(
                    cl.getContact(val.get.senderName));
                res.initImpl!true(val.get, null, cl, prevMessages);
                return res;
            }
            this.quotedMessage = fromQuote(
                history.findQuotedMessage(val.quotedMsgId));
            //TODO we might respond to a sticker
            //but then again, we'll use our "Pragma stickers"
            this.stickerPath = history.findStickerPath(val.stickerId);
        }
    }
    import pragmaMsg;
    string[] getLines(long usableWidth, in ContactsList cl,
                      Size fontSize, PragmaManager pragmaMan) {
        return getLines!(false)(usableWidth,
                                getType(cl) == Type.Receive,
                                fontSize, pragmaMan);
    }
    string[] getLines(bool isQuote)(long fullUsableWidth,
                                    bool isOnTheLeft,
                                    Size fontSize,
                                    PragmaManager pragmaMan) {
        import fileInfo;
        string message = this.message;
        int attachments;
        FileInfo[] attachmentInfos;
        //this has a nicer look than adding them to errors
        //(it shows them bellow the message border)
        string[] attachmentsNotFound;
        string[] errors;
        if (isPrecalculated)
            return renderLines;

        immutable hasQuote = this.quotedMessage != null;
        immutable quoteUsableWidth = fullUsableWidth * 4 / 8;
        immutable msgUsableWidth = isQuote ?
            quoteUsableWidth - 2 ://-2 because we have some spaces
            fullUsableWidth * 5 / 8;
        this.msgUsableWidth = msgUsableWidth;
        this.isOnTheLeft = isOnTheLeft;

        import imgDisplay;
        import std.algorithm;
        auto pragmaRes = pragmaMan.tryParse(message);

        if (pragmaRes.isSuccess) {
            message = "";
            //TODO - separate handling?
            this.attachments ~= pragmaRes.value;
        } else if (pragmaRes.isRealError) {
            errors ~= pragmaRes.error;
        }

        immutable maxTermSize = Size(msgUsableWidth,
                                     config.imageMaxRowsHeight);

        foreach (path; this.attachments) {
            immutable infoRes = getFileInfo(path);
            if (infoRes.isSuccess) {
                immutable info = infoRes.val;

                if (info.isImage) {
                    imgDatas ~= ImgData(info.imageSize, info.path,
                                        maxTermSize, fontSize);
                } else if (info.isNotFound) {
                    attachmentsNotFound ~= info.path;
                } else {
                    attachmentInfos ~= info;
                }
            } else if (infoRes.isRealError) {
                errors ~= infoRes.err;
            }
        }

        import graphics.utils;
        void addFullLine(Line l) {
            if (isOnTheLeft)
                renderLines ~= l.flushLeft;
            else
                renderLines ~= l.flushRight;
        }
        void addMsgLine(Line l) {
            l.maxWidth = fullUsableWidth;
            addFullLine(l);
        }
        void addMsgLineWithBorder(Line l) {
            addFullLine(Line("│ "~ l.flushLeft~" │",
                             l.maxWidth + 4, fullUsableWidth));
        }
        Line mkTopBotLine(bool isTop)() {
            Line res = Line(fullUsableWidth);
            with (res) {
                if (isOnTheLeft) {
                    if (isTop && hasQuote)
                        appendUnsafe("├", 1);
                    else
                        appendUnsafe(isTop ? "┌" : "└", 1);
                } else {
                    appendUnsafe(isTop ? "╭" : "╰", 1);
                }
                enum lineCh = "─";
                import std.array;
                immutable lineWidth = msgUsableWidth+2;//we want some spaces
                if (isTop && hasQuote) {
                    immutable firstSz = isOnTheLeft ? quoteUsableWidth :
                        (lineWidth - quoteUsableWidth-1);
                    immutable secondSz = lineWidth - firstSz-1;
                    appendUnsafe(lineCh.replicate(firstSz), firstSz);
                    appendUnsafe("┴", 1);
                    appendUnsafe(lineCh.replicate(secondSz), secondSz);
                } else {
                    appendUnsafe(lineCh.replicate(lineWidth),
                                 lineWidth);
                }

                if (isOnTheLeft) {
                    appendUnsafe(isTop ? "╮" : "╯", 1);
                } else {
                    if (isTop && hasQuote)
                        appendUnsafe("┤", 1);
                    else
                        appendUnsafe(isTop ? "┐" : "┘", 1);
                }
            }
            return res;
        }
        immutable showName = !isQuote && isOnTheLeft;
        if (showName) {
            Line ln = Line.asciiWithEllipsis(" ", msgUsableWidth);
            ln.appendUtfWithEllipsis(sender.theName, ansi.bold);
            if (hasQuote) {
                ln.appendAsciiWithEllipsis(" replied to ");
                ln.appendUtfWithEllipsis(quotedMessage.sender.theName);
            }
            addMsgLine(ln);
        }
        if (hasQuote) {
            auto startY = renderLines.length;
            renderLines ~= this.quotedMessage.getLines!true(
                fullUsableWidth, isOnTheLeft, fontSize, pragmaMan);
            this.quotedMessage.firstImgLine += startY;
        }
        addFullLine(mkTopBotLine!true());

        import std.uni, std.array, std.string;

        import std.algorithm;
        foreach (ln; lineSplitter(message.strip)) {
            const(Grapheme)[] graphemes = ln.byGrapheme.array;

            while (!graphemes.empty) {
                auto res = sublineBySpace(graphemes, msgUsableWidth);
                graphemes = res.remaining;
                addMsgLineWithBorder(res.val.toLineUnsafe(msgUsableWidth));
            }
        }
        firstImgLine = renderLines.length;
        foreach (img; imgDatas) {
            for (long i = 0; i < img.termHeight; ++i) {
                addMsgLineWithBorder(Line(msgUsableWidth));
            }
        }
        if (!errors.empty) {
            addFullLine(Line("│"~"=".replicate(msgUsableWidth+2)~"│",
                             msgUsableWidth + 4, fullUsableWidth));
            //addMsgLineWithBorder(Line.fill("=", msgUsableWidth));
            foreach (e; errors) {
                const(Grapheme)[] graphemes = e.byGrapheme.array;

                while (!graphemes.empty) {
                    auto res = sublineBySpace(graphemes, msgUsableWidth);
                    graphemes = res.remaining;
                    addMsgLineWithBorder(
                        res.val.toLineUnsafe(msgUsableWidth).with_(
                            ansi.fg(ansi.Color.Red)
                            ));
                }
            }
        }

        if (!isQuote)
            addFullLine(mkTopBotLine!false());

        if (!isQuote) {
            void addAttchLine(Line l) {
                addMsgLine(Line(" "~l.flushLeft~" ",
                                l.maxWidth+2,l.maxWidth+2));
            }
            if (attachmentInfos.length != 0) {
                //addMsgLine(Line.asciiWithEllipsisImpl("Attached:",
                //                                      msgUsableWidth));
                //Line ln = Line.asciiWithEllipsis(format!"Attached: ");
                //import std.path;
                foreach (info; attachmentInfos){ //[0..$-1]) {
                    addAttchLine(Line.utfWithEllipsis(info.niceString,
                                                    msgUsableWidth+2));
                    //ln.appendUtfWithEllipsis(info.niceString~", ");
                }
                //ln.appendUtfWithEllipsis(baseName(attachmentsInfos[$-1]));
                //addMsgLine(ln);
            }
            if (attachmentsNotFound.length != 0) {
                foreach (path; attachmentsNotFound) { //[0..$-1]) {
                    addAttchLine(Line.utfWithEllipsis(
                                   format!"%s not found"(nicePath(path)),
                                   msgUsableWidth+2, ansi.fg(ansi.Color.Red)));
                }
            }
            // print reactions
            if (reactions.length != 0) {

                Line ln = Line(msgUsableWidth);
                int i = 0;
                foreach (r; reactions) {
                    ln.appendUtfWithEllipsis(r.emoji~":");
                    ln.appendUtfWithEllipsis(r.sender.shortName, ansi.bold);
                    //kinda ugly, but oh, well
                    if (i++ != reactions.length - 1)
                        ln.appendUtfWithEllipsis(", ");
                }
                addMsgLine(ln);
            }
        }

        return renderLines;
    }
}
