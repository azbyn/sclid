import result;

class PragmaManager {
    PragmaSticker sticker;
    PragmaLatex latex;

    this() {
        this.sticker = new PragmaSticker();
        this.latex = new PragmaLatex();
    }

    Result!(string) tryParse(string msg) {
        import std.string;
        msg = msg.strip;
        return this.sticker.tryParse(msg)
            .or(this.latex.tryParse(msg));
    }
    bool tryMakeSticker(string val, string* res) {
        return this.sticker.tryMake(val, res);
    }
}

// i'll come back to this later - probably
class LinkManager {
    string[string] linkCache;

    // string getUrlTitles(string msg) {
    //     import std.regex;
    //     auto m = matchAll(msg, `(http(s)?:\/\/.)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)`);
    // }

    //TODO use std.parallism.task
    //WARNING MAY BE *VERY* SLOW, use getUrlTitleAsync
    //we might have to call byline before drawing, then evaluate
    private string getUrlTitle(string url) {
        auto ptr = url in linkCache;
        if (ptr) return *ptr;
        import std.net.curl;
        import std.regex;
        auto r = ctRegex!(`<title>(.*)</title>`, "i");
        foreach (line; byLineAsync(url)) {
            auto match = matchFirst(line, r);
            if (!match.empty) {
                return match[1].idup;
            }
        }
        return "Unknown title url";
    }
}

//
private bool checkDelimiters(string l, string r)(ref string value) {
    import std.algorithm;
    if (!value.startsWith(l) || !value.endsWith(r))
        return false;
    value = value[l.length..$-r.length];
    return true;
}

class PragmaLatex {
    import std.file;
    import config;
    //string[] cachedFiles;
    this() {
        mkdirRecurse(latexCachePath);
    }
    Result!string tryParse(string msg) {
        auto delimiterLen = 2;
        if (checkDelimiters!(`\(`, `\)`)(msg)) {
            return makePath(msg, "math");
        }
        if (checkDelimiters!(`\[`, `\]`)(msg)) {
            return makePath(msg, "displaymath");
        }
        return LightErr!string();
    }
    private Result!string makePath(string innerVal, string env) {
        import config;
        import std.file, std.conv;
        import std.base64;
        auto bytes = cast(immutable(ubyte)[]) (env ~ innerVal);
        string filename = Base64URL.encode(bytes);
        string path = config.latexCachePath  ~"/"~filename ~ ".png";
        if (!exists(path)) {
            import misc;
            import std.string, std.process;
            auto p = pipeProcess(["pnglatex", "-F", "White",
                                  "-b", "Transparent",
                                  "-p", "amssymb:amsmath",//must haves
                                  "-d", config.latexDpi.to!string,
                                  "-e", env,
                                  "-f", innerVal,
                                  "-o", path],
                                 Redirect.stdout | Redirect.stderr);
            //auto res = p.stdout.readln().strip;
            auto exitCode = wait(p.pid);
            if (exitCode) {
                //TODO test this
                return Err!(string, "Latex Error: '%s'")(
                    p.stderr.byLine.join(" "));
            }
            //return res;
        }
        return Ok(path);
    }
}

class PragmaSticker {
    import std.stdio, std.array, std.algorithm, std.range, std.string;
    import std.conv;
    import config;
    //todo
    import misc;

    string[string] links;
    this() {
        import std.file;
        mkdirRecurse(pragmaStickerDir);
        if (!exists(pragmaStickerConfigPath)) {
            createConfigFile();
        } else {
            foreach (string l; File(pragmaStickerConfigPath, "r").lines) {
                l = l.strip;
                if (l.empty) continue;
                auto split = l.split(' ');
                if (split.length != 2) {
                    derr!("invalid pragma sticker line in config: '%s', "~
                          "it should be the name, a space, then the link.")
                        (l);
                }
                links[split[0]] = split[1];
            }
        }
    }

    //just for fun
    enum wchar[] chars = ['λ', 'ß', 'ż', 'γ', 'š', 'ō', 'ć', 'ń',
                          'ł', 'ą', 'ν', 'я', 'ж', 'ξ', 'щ', 'ы',];
    import misc : dumbMap;
    //enum /*string[]*/ strings = chars.dumbMap(x=>format!"%s"(x));//.array;
    static assert(chars.length == 16);

    //sigh -they're unique anyway
    //static assert(strings.sort.uniq.walkLength == 16);// aka check that they are all unique

    //string nameManglin

    //for stickers
    enum header = mvs ~"∫";
    enum footer = " dμ";

    //my boy, the mongolian vowel separator
    enum string mvs = "\u180E";

    Result!string tryParse(string str) const {
        if (!checkDelimiters!(header, footer)(str))
            return LightErr!string;
        import std.utf : byWchar;
        int i = 0;
        //ja, ja it's inefficient.
        byte thing;
        string res;
        foreach (c; str.byWchar) {
            auto idx = chars.findIndex!(x=>x==c);
            if (idx < 0) {
                return Err!(string, "Invalid char in sticker '%s' - %s")(
                    str, cast(immutable ubyte[]) str);
            }
            if (i % 2 == 0) {
                thing = cast(ubyte) idx;
            } else {
                thing = (thing | (idx << 4)).to!ubyte;
                res ~= cast(char) thing;
            }
            ++i;
        }
        if (i % 2 != 0) {
            // sounds fancy
            return Err!(string, "Invalid sticker '%s' Parity check failed.")(str);
        }
        //todo
        auto ptr = res in links;
        if (ptr == null) {
            return Err!(string, "Pragma sticker '%s' not found (%s)")(
                res, cast(immutable ubyte[]) res);
        }
        return nameToPath(res, *ptr);
    }

    bool tryMake(string val, string* outVal) const {
        auto ptr = val in links;
        if (ptr == null)
            return false;

        *outVal = encode(val);
        return true;
    }

    // there's no need to encode anything, but it's more fun when
    // people don't know what this is.
    //where val is a key from pragmaMsgPaths
    private string encode(string val) const {
        string res;
        foreach (c; val) {
            immutable b = cast(byte)c;
            //todo eficiency? ie don't append but prealocate memory
            //well anyway, this shouldn't be called that often.
            res ~= chars[b&15];
            res ~= chars[b>>4];
        }
        return header ~ res ~ footer;
    }
    private Result!string nameToPath(string name, string link) const {
        //static string[] existCache;
        import misc : derr;
        import std.net.curl;
        auto path = pragmaStickerDir ~ "/"~name;
        import std.file;
        if (/*!existCache.canFind(path) && */!exists(path)) {
            try {
                download(link, path);
                //existCache ~= path;
            } catch (CurlException e) {
                derr!"Downloading of '%s' failed (%s) "(name, link);
                // it's ok to also return path - it doesn't exist,
                // so it'll be handled in renderMessage
            }
        }
        return Ok(path);
    }

    private void createConfigFile() {
        enum defaultLinks = [
            "proGamerMove": "https://i.kym-cdn.com/photos/images/newsfeed/001/498/705/803.png",
            "germanScience": "https://satchiikoma.files.wordpress.com/2013/12/german-science-is-the-worlds-finest.jpg",
            "mjEatingPopcorn": "https://i.kym-cdn.com/photos/images/newsfeed/000/296/328/d64.gif",
            ];
        // if it dies, let it die
        auto f = File(pragmaStickerConfigPath, "w");
        foreach (key, link; defaultLinks) {
            f.writeln(key, " ", link);
        }
        links = defaultLinks;
    }
}
