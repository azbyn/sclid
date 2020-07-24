module graphics.screen;

struct Screen {
    import core.sys.posix.unistd;
    import core.sys.posix.termios;
    import core.sys.posix.sys.ioctl;
    import std.conv;
    import std.exception;
    import std.typecons;
    import graphics.utils;
    import graphics.ansi;
    import misc;
    import std.format;

    alias ansi = graphics.ansi;
    // import core.stdc.errno;

    bool initialized;
    termios ogTermios;

    enum defaultFontDim = Size(0,0);

    Size fontDimensions;
    Size size;
    auto width()  { return size.width; }
    auto height() { return size.height; }


    @disable this(this);
    @disable this();
    // we can't use the default constructor, and i want to know exactly when
    // the descructor gets called
    this(int foo) {
        enableRawMode();
        this.initialized = true;
        print(alternativeBuffer.on);
        print(bracketedPaste.on);
        //kinda pointless since we'll draw anyway, but oh, well
        print(clearScr);
        flush();
        updateTermsize();
    }
    ~this() {
        if (initialized) {
            print(cursorVisibility.on);
            print(ansi.cursorDefault);
            print(bracketedPaste.off);
            print(alternativeBuffer.off);
            flush();
            disableRawMode();
        }
    }
    void gotoOtherBuffer() {
        print(alternativeBuffer.on);
    }
    import graphics.keyboard;
    Key getkey() {
        return graphics.keyboard.getkey();
    }
    bool checkTermSizeUpdate() {
        auto old = this.size;
        updateTermsize();
        return old != this.size;
    }

    void setLines(in char[][] lines, Nullable!Point cursor, size_t startAt)
    in {
        assert(lines.length == height, "Exactly `height` lines expected.");
    } do {
        // we don't want to see the cursor in the middle of the screen for a
        // brief second when we draw
        const(char)[] res = ansi.cursorVisibility.off;
        for (long i = startAt; i < lines.length; ++i) {
            // we could get away with not using clearToEol the screen and
            // using \r\n, but perhaps, we have a line that is wider
            // (or shorter) than it should
            // yet, "that should never happen" - even i don't belive myself
            res ~= ansi.moveCursor(Point(0, i.to!int))
                ~ lines[i];
            // ~ clearToEol; - this deletes the last character if the line
            // is as it should be - exactly as wide as the screen
            //so wcs we'll get some garbage at the end
        }
        //this clears the last character, just as clearToEol
        // res ~= ansi.clearToBot;
        if (!cursor.isNull) {
            res ~= ansi.cursorVisibility.on ~
                ansi.moveCursor(cursor.get);
        }
        //we may have fewer lines than we should
        print(res);
        flush();
    }

    // void printf(string fmt, Args...)(Args args) {
    //     print(format!fmt(args));
    //     // stdout.writef!fmt(args);
    // }
    // void printff(string fmt, Args...)(Args args) {
    //     printf!(fmt, Args)(args);
    //     flush();
    // }

private:
    void print(const (char)[] s) {
        import std.stdio;
        stdout.write(s);
    }
    void flush() {
        import std.stdio;
        stdout.flush();
    }

    //from kilo the text editor
    void disableRawMode() {
        enforce(tcsetattr(STDIN_FILENO, TCSAFLUSH, &ogTermios)==0, "tcsetattr");
    }
    void enableRawMode() {
        enforce(tcgetattr(STDIN_FILENO, &ogTermios) == 0, "tcgetattr");

        termios raw = ogTermios;
        raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        raw.c_oflag &= ~(OPOST);
        raw.c_cflag |= (CS8);
        raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);

        //don't block for input?
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 1;

        enforce(tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0, "tcsetattr");
    }
    void updateTermsize() {
        tiocgwinsz!false(&size, null);
    }
    ///TODO config
    //shouldn't be called all the time
    void tiocgwinsz(bool getPixelsize)(Size* outSize, Size* outPixelsize) const {
        winsize ws;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0) {
            //https://viewsourcecode.org/snaptoken/kilo/03.rawInputAndOutput.html
            throw new Exception("Welp, great. i won't implement that " ~
                                "(unless there's demmand). Try switching " ~
                                "terminals");
        } else {
            *outSize = Size(ws.ws_col, ws.ws_row);
            static if (getPixelsize) {
                // with the cast if it's something like 0xFFFF it becomes
                // a negative number
                *outPixelsize = Size(cast(short) ws.ws_xpixel,
                                     cast(short) ws.ws_ypixel
                    );
            }
        }
    }

public:
    import config;
    Size fetchFontSize() const {
        string w3mimgPath = config.w3mimgdisplayPath;
        Size size, pixelSize;
        tiocgwinsz!true(&size, &pixelSize);
        if (size.width == 0 && size.height == 0) {
            dwarn!"terminalSize == 0";
            return Size(1, 1);
        }
        // printff!"pixelSize `%s`\r\n"(pixelSize);
        // printff!"sz `%s`\r\n"(size);
        if (pixelSize.height <= 0) {
            import std.process;

            auto p = execute([w3mimgPath, "-test"]);

            //we really expect this not to fail, so exceptions are justified
            try {
                auto str = p.output;
                import std.string;
                pixelSize.width = parse!int(str);
                str = str.stripLeft;
                pixelSize.height = parse!int(str);
                //ranger does the +=2, so i'll do that too
                pixelSize.width += 2;
                pixelSize.height += 2;

            } catch (Exception e) {
                derr!"w3mimgdisplay -test failed (%s)"(p.output);
                return Size(-1, -1);
            }
        }

        return Size(pixelSize.width  / size.width,
                    pixelSize.height / size.height);
    }
}
