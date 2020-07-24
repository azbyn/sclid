import config;

import graphics.utils;
import result;
struct ImgData {
    import std.conv;
    import result;
    import fileInfo;

    //here term refers to the fact that it's in termnal units
    //(ie about 12x23 px on my laptop)
    Size pxSize;
    long termHeight;

    string path;

    @disable this();
    this(Size imgSize, string path, Size maxTermSize, Size fontSize) {
        alias size = imgSize;
        immutable aspectRatio = size.w.to!float / size.h;
        immutable maxPxSize = Size(
            maxTermSize.w * fontSize.w,
            maxTermSize.h * fontSize.h
            );

        this.path = path;
        if (size.w <= maxPxSize.w && size.h <= maxPxSize.h) {
            this.pxSize = size;
        } else {
            this.pxSize.height = maxPxSize.h;
            this.pxSize.width = (aspectRatio * maxPxSize.height).to!long;

            if (this.pxSize.width > maxPxSize.w) {
                this.pxSize.width  = maxPxSize.w;
                this.pxSize.height = (maxPxSize.w / aspectRatio).to!long;
            }
        }
        //round up
        this.termHeight = (this.pxSize.h+fontSize.h -1) / fontSize.h;
    }

    private Rect calculateRect(Vec2i termPos, Size fontSize) const {
        Rect val;
        val.x = termPos.x*fontSize.w;
        val.y = termPos.y*fontSize.h;
        val.height = this.pxSize.height;
        val.width = this.pxSize.width;
        return val;
    }
}
import std.process;
import std.conv;

class ImgDisplayer {
    abstract void addImg(in ImgData data, Pos termPos, Size fontSize);
    abstract void clearAll();
    void flush() {}
}
class NullDisplayer : ImgDisplayer {
    override void addImg(in ImgData data, Pos termPos, Size fontSize) {}
    override void clearAll() {}
}

class W3mimgDisplayer : ImgDisplayer {
    import std.process;
    import std.conv;

    override void addImg(in ImgData data, Pos termPos, Size fontSize) {
        add(data.calculateRect(termPos, fontSize), data.path);
    }
    private void clear(Rect r) {
        string xs = r.x.to!string;
        string ys = r.y.to!string;
        string hs = r.height.to!string;
        string ws = r.width.to!string;
        auto pipes = pipeProcess([w3mimgdisplayPath],
                                 Redirect.stdin | Redirect.stdout);
        string thing = "6;"~xs~";"~ys~";"~ws~";"~hs~"\n4;\n3;\n";
        pipes.stdin.writeln(thing);
        // pipes.stdout.readln();
        pipes.stdin.close();
        wait(pipes.pid);
    }
    override void clearAll() {
        foreach (r; imgRects) {
            clear(r);
        }
        imgRects = [];
    }
    private Rect[] imgRects;
    private void add(Rect r, string path) {
        string xs = r.x.to!string;
        string ys = r.y.to!string;
        string hs = r.height.to!string;
        string ws = r.width.to!string;
        auto pipes = pipeProcess([w3mimgdisplayPath],
                                 Redirect.stdin | Redirect.stdout);
        string thing = "0;1;"~xs~";"~ys~";"~ws~";"~hs~";;;;;"~path~"\n4;\n3;\n";
        pipes.stdin.writeln(thing);
        imgRects ~= r;
        // pipes.stdout.readln();
        pipes.stdin.close();
        wait(pipes.pid);
    }
}

class KittyDisplayer : ImgDisplayer {
    private uint indexCtr = 0;
    import std.stdio;
    import std.format;

    override void addImg(in ImgData data, Pos termPos, Size fontSize) {
        immutable idx = indexCtr++;
        import std.math;
        import std.algorithm;

        //TODO only works for png
        if (!data.path.endsWith(".png"))
            return;
        immutable termWidth  =
            ceil(data.pxSize.width.to!float / fontSize.w).to!int;
        immutable termHeight =
            ceil(data.pxSize.height.to!float / fontSize.h).to!int;

        //TODO use a=t and store the ids
        sendCode("f=100"//png
                 ~",a=T"
                 ~",t=f"//type=file
                 ~format!",i=%d"(indexCtr)//index =...
                 ~format!",c=%d,r=%d"(termWidth, termHeight)
                 , data.path);
        import graphics.keyboard;
        for (;;) {
            byte b = getch();
            if (b != 0x1B) {
                ungetc(b, stdin.getFP);
                break;
            }

            b = getch();
            //ignore responses
            if (b != '_') {
                ungetc(0x1B, stdin.getFP);
                ungetc(b, stdin.getFP);
                break;
            }
            for (;;) {
                b = getch();
                if (b == 0x1b) break;
            }
            getch();
        }
    }
    override void clearAll() {
        sendCode("a=d", "");
    }

    private void sendCode(string ctrlData, string unencodedPayload) {
        import std.base64;
        string encodedPayload = Base64.encode(cast(immutable(ubyte)[])unencodedPayload);
        stdout.write("\033_G", ctrlData, ";", encodedPayload, "\033\\");
    }
    override void flush() {
        stdout.flush();
    }
}

public import config : ImgDisplay;

/+
class ImgDisplay {
    import imageUtils;
    import std.conv;
    import std.process;
    ProcessPipes pipes;
    //only w3mimg works
    enum Mode {
        //Ueberzug,
        W3mimg,
        //Kitty, // could be better
    }
    enum mode = Mode.W3mimg;
    // enum mode = Mode.Kitty;

    this() {
        final switch (mode) {
            /*case Mode.Ueberzug:
            pipes = pipeProcess(["ueberzug", "layer", "-p", "simple"], //"--silent"
                            Redirect.stdin //| Redirect.stdout
            );
            break;*/
        case Mode.W3mimg:
            //case Mode.Kitty:
            break;
        }
    }
    /*
    void addNice(int id, int x, int y, int maxWidth, int height, string path) {
        Size size;
        getImageSize(path, /+out+/ size);
        float ratio = size.w.to!float / size.h;
        int width = (ratio * height).to!int;
        if (width >= maxWidth) {
            width = maxWidth;
            height = (maxWidth / ratio).to!int;
        }
        add(id, x, y, width, height, path);
    }*/
    void addImg(/*int id, */in ImgData data, Vec2i termPos, Size fontSize) {
        //import misc;
        //dlog!"addimg %s"(data.path);
        add(0/*id*/, data.calculateRect(termPos, fontSize), data.path);
    }
    private void clear(Rect r) {
        final switch (mode) {
        case Mode.W3mimg: {
            string xs = r.x.to!string;
            string ys = r.y.to!string;
            string hs = r.height.to!string;
            string ws = r.width.to!string;
            pipes = pipeProcess([w3mimgdisplayPath],
                                Redirect.stdin | Redirect.stdout);
            string thing = "6;"~xs~";"~ys~";"~ws~";"~hs~"\n4;\n3;\n";
            pipes.stdin.writeln(thing);
            // pipes.stdout.readln();
            pipes.stdin.close();
            wait(pipes.pid);
        } break;
        }
    void clearAll() {
        final switch (mode) {
        case Mode.W3mimg:
            import misc;
            foreach (r; imgRects) {
                clear(r);
            }
            imgRects = [];
            break;
        }
    }
    private Rect[] imgRects;
    private void add(int id, Rect r, string path) {
        final switch (mode) {
            /*case Mode.Ueberzug:
            pipes.stdin.writeln("action\t"~ "add\t"~
                                "identifier\t"~ id.to!string ~ "\t" ~
                                "x\t"~ r.x.to!string ~ "\t" ~
                                "y\t"~ r.y.to!string ~ "\t" ~
                                "height\t"~r.height.to!string ~ "\t"~
                                "width\t"~r.width.to!string ~ "\t"~
                                "path\t" ~path);
                                break;*/
        case Mode.W3mimg: {
            string xs = r.x.to!string;
            string ys = r.y.to!string;
            string hs = r.height.to!string;
            string ws = r.width.to!string;
            pipes = pipeProcess([w3mimgdisplayPath],
                                Redirect.stdin | Redirect.stdout);
            string thing = "0;1;"~xs~";"~ys~";"~ws~";"~hs~";;;;;"~path~"\n4;\n3;\n";
            pipes.stdin.writeln(thing);
            imgRects ~= r;
            // pipes.stdout.readln();
            pipes.stdin.close();
            wait(pipes.pid);
        } break;
            /*case Mode.Kitty:
            import std.string;
            pipes = pipeProcess(["kitty", "+kitten", "icat", path, "--place",
                                 format!"%dx%d@%dx%d"(r.width, r.height,
                                                      r.x, r.y), "--scale-up"],
                                                      );
                                                      break;*/
        }


/*/
  if not self.is_initialized or self.process.poll() is not None:
  self.initialize()
  try:
  input_gen = self._generate_w3m_input(path, start_x, start_y, width, height)
  except ImageDisplayError:
  raise

  # Mitigate the issue with the horizontal black bars when
  # selecting some images on some systems. 2 milliseconds seems
  # enough. Adjust as necessary.
  if self.fm.settings.w3m_delay > 0:
  from time import sleep
  sleep(self.fm.settings.w3m_delay)

  self.process.stdin.write(input_gen)
  self.process.stdin.flush()
  self.process.stdout.readline()
  self.quit()
  self.is_initialized = False
 */
    }

    ~this() {
        /*if (mode == Mode.Ueberzug) {
            pipes.stdin.close();
            wait(pipes.pid);
            }*/
    }
    /*
}
+/
