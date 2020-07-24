module graphics.graphics;

class Graphics {
    import graphics.windowBase;
    import graphics.screen, graphics.keyboard, graphics.utils;
    import graphics.contacts, graphics.messages, graphics.input,
        graphics.minibuffer;
    import std.conv, std.format;
    import misc;
    alias ansi = graphics.ansi;

    import contactsList, database.messageHistory, messageManager;

    Screen screen;

    Contacts contacts;
    Messages messages;
    Input input;
    Minibuffer minibuffer;

    WindowBase currentWin_, prevWin;

    bool mustDraw = false;

    ContactsList cl;
    MessageHistory history;
    MessageManager man;
    void watchContacts() { contacts.onContactsUpdate(); }
    void watchHistory(const GroupOrContact sender) {
        messages.updateConvo(sender);
        contacts.onContactsUpdate();
        if (currentWin == input)
            input.draw();
        drawFrame();
    }

    this(ContactsList cl, MessageHistory history, MessageManager man) {
        screen = Screen(42);
        this.cl = cl;
        this.history = history;
        this.man = man;

        contacts = new Contacts(this);
        messages = new Messages(this);
        input = new Input(this);
        minibuffer = new Minibuffer(this);
        cl.connect(&watchContacts);
        history.connect(&watchHistory);
    }
    string[] selectFile() {
        import std.process, std.file, std.stdio, std.algorithm, std.array;
        enum path = "/tmp/sclid_selected_files";

        if (exists(path)) std.file.remove(path);
        auto pid = spawnProcess(["ranger", "--choosefiles", path ]);
        wait(pid);
        screen.gotoOtherBuffer();

        currentWin.draw();
        drawFrame();

        if (!exists(path))
            return [];

        auto res = File(path, "r").byLine.filter!(x=>x != "").
            map!(x=>x.idup).array;
        mustDraw = true;
        return res;
    }
    string[] editInEditor(string editor, string[] initial) {
        enum path = "/tmp/sclid_edit";
        import std.file, std.process, std.array;
        import std.stdio : File;
        //if (exists(path)) std.file.remove(path);
        write(path, initial.join('\n'));

        auto pid = spawnProcess([editor, path]);

        wait(pid);
        screen.gotoOtherBuffer();

        currentWin.draw();
        drawFrame();
        mustDraw = true;

        if (!exists(path))
            return initial;
        return File(path, "r").byLineCopy().array;// readText(path);
    }
    void copyToClipboard(string str) {
        import std.process;
        auto p = pipeProcess(["xclip", "-selection", "clipboard", "-i"],
                             Redirect.stdin);
        p.stdin.write(str);
        p.stdin.flush();
        p.stdin.close();
        wait(p.pid);
    }
    import graphics.renderMessage;
    void copyToClipboard(in RenderMessage msg) {
        return copyToClipboard(msg.message);
    }

    @property WindowBase currentWin() { return currentWin_; }
    @property WindowBase previousWin() { return prevWin; }
    @property const(WindowBase) currentWin() const { return currentWin_; }
    void selectWindow(bool isInitial = false)(WindowBase w) {
        if (!isInitial) {
            currentWin_.onDeselect();
            prevWin = currentWin_;
        }
        else {
            prevWin = w;
        }
        currentWin_ = w;
        // refresh();
        currentWin_.onSelect();

        drawFrame();
        mustDraw = true;
        //will be called next loopImpl();
        // drawFrame();
    }
    void selectPrevious() {
        selectWindow(prevWin);
    }

    void selectConvo(T)(T v) {
        return selectConvo(GroupOrContact(v));
    }
    void selectConvo(in GroupOrContact goc) {
        messages.selectConvo(goc);
        selectWindow(messages);
    }

    void end() {
        this.destroy;
    }

    void loopInit() {
        updateSizes!true();

        selectWindow!true(contacts);
    }
    void loopImpl() {
        import std.uni;

        if (screen.checkTermSizeUpdate) {
            updateSizes();
        }
        if (currentWin.loop(screen.getkey()) == ShouldDraw.Yes) {
            currentWin.draw();
            drawFrame();
        }
        static if (imgDelayMs != 0) {
            if (imgSW.peek > msecs(imgDelayMs)) {
                messages.drawImages();
                imgSW.stop();
                imgSW.reset();
            }
        }
    }
    ShouldDraw defaultKeyHandler(Key k) {
        switch (k) {
        case 'q':
            quit();
            return ShouldDraw.No;
        case Key.alt('x'):
        case ':':
            commandMode();
            break;
        default:
            break;
        }
        return ShouldDraw.No;
    }
    void quit() {
        import app;
        //version(Lib)
        version(Exec)
            app.stopLoop();
        else
            NativeThread.stopLoop();
    }

    void resizeMinibuffer(size_t height) {
        updateSizes(height, input.height);
    }
    void resizeInput(size_t h) {
        updateSizes(minibuffer.height, h);
    }
    void commandMode() {
        selectWindow(minibuffer);
    }

private:
    import config;
    static if (imgDelayMs != 0) {
        import std.datetime.stopwatch;
        StopWatch imgSW;
    }
    void drawFrame() {
        import graphics.utils;
        import std.array;
        const(char)[][] lines =
            uninitializedArray!(const(char)[][])(screen.height);
        int y = 0;
        immutable toEndOfContacts = ansi.cursorHoriAbs(contacts.width);
        for (;y < messages.height; ++y) {
            lines[y] = contacts.renderLines[y] ~ toEndOfContacts ~
                messages.renderLines[y];
        }
        int ii = 0;
        for (; y < contacts.height; ++y) {
            lines[y] = contacts.renderLines[y] ~ toEndOfContacts
                ~ input.renderLines[ii++];
        }

        for (size_t i = 0; i < minibuffer.height/* < botLines*/; ++i)
            lines[i+contacts.height] = minibuffer.renderLines[i];
        //dlog!"lines %s"(lines.length);


        // TODO hax, could be done nicer
        // doesn't even work in Kitty (but does in urxvt)
        long startAt = !mustDraw
            && (currentWin == input|| currentWin== minibuffer)
            && !messages.imagesDirty
            ? messages.height : 0;


        screen.setLines(lines, currentWin.getGlobalCursorPos, startAt);

        static if (config.imgDelayMs == 0) {
            messages.drawImages();
        } else {
            imgSW.reset();
            if (!imgSW.running)
                imgSW.start();
        }
    }
    void updateSizes(bool isFirst = false)() {
        updateSizes!isFirst(minibuffer.height, input.height);
    }
    void updateSizes(bool isFirst = false)(long mbLines, long inputLines) {
        contacts.resize(Rect(0, 0, screen.width/4, screen.height-mbLines));

        messages.resize(Rect(contacts.width, 0,
                         screen.width - contacts.width,
                         screen.height - mbLines - inputLines));

        input.resize(Rect(contacts.width, messages.height,
                          messages.width,
                          inputLines));
        minibuffer.resize(Rect(0, screen.height-mbLines, screen.width, mbLines));

        static if (!isFirst)
            drawFrame();
        mustDraw = true;
    }
}
