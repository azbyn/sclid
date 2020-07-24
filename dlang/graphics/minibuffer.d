module graphics.minibuffer;

import graphics.inputWindow;

class Minibuffer : InputWindow!(No.hasHorizontal,
                                /*firstIndentAscii = */ ":",
                                No.drawWhenUnselected,
                                Yes.hasCompletion,
                                /*initialUsableHeight = */1) {

    import graphics.graphics, graphics.window;
    import misc, config;
    // import std.uni;
    import std.conv, std.string;
    import std.algorithm, std.array;

    this(Graphics parent) {
        super(parent, BorderStyle.none);
    }

    private auto man() { return parent.man; }
    private auto messages() { return parent.messages; }

    override ShouldDraw onEscape() {
        super.clear();
        parent.selectPrevious();
        return ShouldDraw.Yes;
    }
    private Line msg;
    void setError(string utfString) {
        msg = Line.utfWithEllipsis(utfString, usableWidth,
                                   ansi.fg(ansi.Color.Red));
    }
    void setInfo(string utfString) {
        msg = Line.utfWithEllipsis(utfString, usableWidth);
    }
    override void onSelect() {
        msg = Line(usableWidth);
        super.onSelect();
    }
    override void draw() {
        import graphics.utils;
        alias ansi = graphics.ansi;
        if (msg.width != 0) {
            win.initDrawingCursor();
            win.setLine(msg);
            //Line.utfWithEllipsis(err, usableWidth.to!int,
            //                                 ansi.fg(ansi.Color.Red)));
            return;
        }
        super.draw();
    }
    enum commands = makeCmds();
    struct Cmd {
        dstring name;//can't be Grapheme[] sadly
        dstring[] argCompletions;
        void function(Minibuffer thiz, WindowBase from,
                      WindowBase* returnTo, string arg) func;
    }


    import std.uni : Grapheme, byGrapheme, byCodePoint;
    CompletionResult completeWordImpl(Value,
                                      bool hasMoreCompletions=true)
        (const(dstring) function(in Value) valueName,
         const(dstring)[] function(in Value) wordCompletions,
         in Grapheme[] line, long pos, in Value[] values) {

        /// first non-space
        // leading spaces count is the same thing as the index of
        long leadingSpacesCount =
            line.findIndex!((in Grapheme g) => !g.isSpace);
        if (leadingSpacesCount < 0) return CompletionResult.null_;

        // if we're on the first spaces
        if (pos < leadingSpacesCount) return CompletionResult.null_;

        pos -= leadingSpacesCount;
        //the first word in the line
        const Grapheme[] firstWordGr =
            line[leadingSpacesCount..$].splitAtFirst(Grapheme(' ')).first;

        string firstWordStr = firstWordGr.toStr.toLower;

        //short, simple, dumb.
        auto range = values.filter!(x=>valueName(x)
                                    .startsWith(firstWordStr));


        //aka nothing starts with that word
        if (range.empty) return CompletionResult.null_;

        if (pos > firstWordGr.length) {
            // check for the second word
            const newValues = wordCompletions(range.front);
            static if (hasMoreCompletions) {
                if (firstWordGr.byCodePoint.array != valueName(range.front)
                    || newValues.empty) return CompletionResult.null_;

                auto res = completeWordImpl!(dstring, false)(
                    (in dstring x)=>x, (in dstring x) => cast(dstring[]) [],
                    line[firstWordGr.length..$],
                    pos - firstWordGr.length, newValues
                    );
                res.x += firstWordGr.length;
                return res;
            } else {
                return CompletionResult.null_;
            }
        }
        // we want to draw the suggestion after the word, not necessarily
        // after the cursor.
        auto cursorPos = leadingSpacesCount + firstWordGr.length;
        return CompletionResult(
            valueName(range.front)[firstWordGr.length..$].byGrapheme.array,
            cursorPos);
    }
    override CompletionResult completeAtPoint(in Grapheme[] line, long pos) {
        assert(pos <= line.length);
        // the cursor is not over the first word
        import std.algorithm;

        return completeWordImpl!(Cmd)((in Cmd c) => c.name,
                                     (in Cmd c) =>c.argCompletions,
                                      line, pos, commands);
    }

    override ShouldDraw onEnter() {
        //stuff like reply
        //returns true on success
        super.acceptCompletion();
        auto returnTo = parent.previousWin;
        auto val = super.getValue.strip.splitAtFirst(' ');
        auto cmd = val.first.strip.toLower;
        auto arg = val.rest.strip;

        auto ptr = commands.findPtr!(x=>x.name.to!string==cmd);
        if (ptr == null) {
            setError(format!"ERROR: not a command: %s"(cmd));
        } else {
            ptr.func(this, parent.previousWin, &returnTo, arg);
        }

        super.clear();
        parent.selectWindow(returnTo);
        return ShouldDraw.Yes;
    }
    override void onWantsResize(size_t height) {
        parent.resizeMinibuffer(height);
    }

    enum exportCmd;

    @exportCmd
    void quit() { parent.quit(); }

    @exportCmd
    void sync() {parent.man.sync();}

    @exportCmd
    void edit(string editor) {
        if (editor.empty) editor = config.editor;
        parent.input.editInEditor(editor);
    }
    @exportCmd
    void yank(WindowBase from) {
        messageCommands!("yank", msg => parent.copyToClipboard(*msg))(from);
        setInfo("Copied thing");
    }
    @exportCmd
    void copy(WindowBase from) {
        messageCommands!("copy", msg => parent.copyToClipboard(*msg))(from);
        setInfo("Copied thing");
    }
    @exportCmd
    void react(WindowBase from, string arg) {
        if (arg != "") {
            if (arg[0] == '\'') {
                //hax for myself
                arg = arg[1..$];
            } else {
                auto ptr = arg in theEmoji;
                if (ptr == null) {
                    import std.algorithm;
                    setError("Invalid reaction. Only "
                             ~kosherEmoji.join(", ")
                             ~" are supported.");
                    return;
                }
                arg = *ptr;
            }
        }
        messageCommands!("react", (msg) {
             this.msg.width = 1;
             return parent.man.react(parent.messages.groupOrContact,
                                     *msg, arg);
            })(from);
    }

    // todo make a generic complete thing that takes some array and
    // a word index

    //why can't this be a variable - sigh
    static string[] kosherEmoji() {
        return theEmoji.keys.filter!(x=> !verbotenesEmoji.canFind(x)).array; }



    //used by command
    static dstring[] react_completions() {
        return kosherEmoji.map!(x=>x.to!dstring).array; }

    @exportCmd
    void attach() {
        parent.input.onAttachFiles(parent.selectFile());
        //THIS IS HAX TODO
        msg.width = 1;// " ";
    }

    @exportCmd
    void attachClipboard() {
        import std.process;
        auto file = execute(["mktemp", "/tmp/sclid_clip_XXXXXXX"]).output.strip;
        executeShell("xclip -selection clipboard -o > "~file);
        parent.input.onAttachFiles([file]);
        msg.width = 1;
    }

    @exportCmd
    void pragmaSticker(string arg) {
        string msg;
        auto res = messages.pragmaManager.tryMakeSticker(arg, &msg);
        if (!res) {
            setError(format!"pragma msg not found '%s'"(arg));
        }
        man.sendPragmaSticker(messages.groupOrContact, msg);
        this.msg.width = 1;// " ";
    }

    @exportCmd
    void reply(WindowBase from) {
        WindowBase returnTo = from;
        reply(from, &returnTo);
        parent.selectWindow(returnTo);
    }
    @exportCmd
    private void reply(WindowBase from, WindowBase* returnTo) {
        messageCommands!("reply", (m) {
                parent.input.onReply(m);
                //super.clear();
                *returnTo = parent.input;
                //hax
                this.msg.width = 1;
            })(from);
    }
    @exportCmd
    void unreply() {
        parent.input.unreply();
        parent.input.draw();
    }

    private void messageCommands(string cmd, alias F)(WindowBase from) {
        if (from != parent.messages) {
            setError(format!"%s only works from the MessagesWindow"(cmd));
            brek();
            return;// false;
        }
        auto msg = messages.currentMessage;
        if (msg == null) {
            setError(format!"you don't have any message for `%s`"(cmd));
            return;// false;
        }
        F(msg);
        //return true;
    }

    //could be avoided, but it's fun
    static string camelToKebab(string s) {//someThing becomes some-thing

        // using regex doesn't work in this case at compile time
        //doesn't work properly with MULTIpLe uppercase letters
        dstring res = "";
        dstring remaining = s.to!dstring;
        import std.uni;

        for (;;) {
            long i = remaining.findIndex!(isUpper);
            if (i < 0) {
                res ~= remaining;
                break;
            }
            res ~= remaining[0..i]~'-'~remaining[i..i+1].toLower;
            remaining = remaining[i+1..$];
        }
        return res.to!string.chompPrefix("-");
    }
    static auto makeCmds() {
        import std.traits;
        Cmd[] cmds;
        static foreach (name; __traits(derivedMembers, Minibuffer)) {{
                static if (name != "commands") {
                mixin("alias Sym = "~name~";");
                static if (hasUDA!(Sym, exportCmd)) {
                    static assert(isSomeFunction!Sym);
                    static assert(__traits(isSame, ReturnType!Sym, void));
                    alias Args = Parameters!Sym;
                    import std.typecons;

                    enum string params = () {
                        string[] usedParams;
                        string params = "";

                        static foreach (A; Args) {{
                                string aname = fullyQualifiedName!A;
                                assert(!usedParams.canFind(aname),
                                       "already used "~aname);
                                usedParams ~= aname;

                                static if (is(A==string)) {
                                    params ~= "arg, ";
                                }
                                else static if (is(A==WindowBase*)) {
                                    params ~= "returnTo, ";
                                }
                                else static if (is(A==WindowBase)) {
                                    params ~= "from, ";
                                }
                                else static assert("invalid arg type: "~aname);
                            }}
                        return params;
                    }();
                    import std.uni, std.array, std.algorithm;
                    //this is dumb, why doesn't byGrapheme work at compile time
                    dstring[] argCompletions;
                    static if (hasMember!(Minibuffer, name~"_completions")) {
                        argCompletions = mixin(name~"_completions");
                    }
                    cmds ~= Cmd(camelToKebab(name).to!dstring,
                                argCompletions,
                                //.map!(x=>Grapheme(x)).array,
                                mixin("(Minibuffer thiz, "
                                      ~"WindowBase from, "
                                      ~"WindowBase* returnTo, "
                                      ~"string arg) => thiz."
                                      ~name~"("~params~")"));
                }
            }
        }}

        return cmds;
    }
    enum string[] verbotenesEmoji = ["kappa", "thatEmoji"];
    enum string[string] theEmoji = [
        "laugh": "😂",
        "kappa": "κ",
        "up": "👍",
        "down": "👎",
        "heart": "❤️",
        "angry": "😡",
        "sad": "😢",
        "thatEmoji": "😏",
        "wow": "😮"
    ];

}
