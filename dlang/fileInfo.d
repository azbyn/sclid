import graphics.utils : Size;
import result;

string removeSignalTimestamp(string path) {
    import std.regex;
    enum r = ctRegex!(`^\d+__!`);

    return replaceFirst(path, r, ``);
}

string nicePath(string path) {
    import std.path;
    path = path.dirName ~"/"~ removeSignalTimestamp(path.baseName);

    import config;
    import std.string;
    if (path.startsWith(config.home)) {
        return "~/"~path.chompPrefix(config.home).chompPrefix("/");
    }
    return path;
    //import std.path;
    //return relative baseName(path);
}

struct FileInfo {
    enum Type {
        NotFound,
        Image,
        Audio,
        Video,
        Pdf,
        Archive,
        Source,
        Text,
        Other
    }
    Type type;
    string path;
    Size imageSize;

    bool isImage() const { return type == Type.Image; }

    bool isNotFound() const { return type == Type.NotFound; }
    string niceString() const {
        import misc;
        import std.format;
        return nicePath(path);// format!"%s (%s)"(nicePath(path), typeToNiceStr);
    }
    private  string typeToNiceStr() const {
        final switch (type) {
        case Type.NotFound:
        case Type.Image:
            //we shouldn't call niceString for these types
            assert(0, "we shouldn't get here");
        case Type.Audio:   return "audio";
        case Type.Video:   return "video";
        case Type.Pdf:     return "pdf";
        case Type.Archive: return "archive";
        case Type.Source:  return "source code";
        case Type.Text:    return "text";
        case Type.Other:   return "other";
        }
    }
}

Result!FileInfo getFileInfo(string path) {
    import std.process, std.conv, std.string, std.typecons;
    import std.regex;
    try {
        auto cmd = execute(["file",
                            "-b",//be brief
                            "-E",//error on failure
                            path]);

        bool canFind(string val)(string res) {
            return res.indexOf(val, No.caseSensitive) >= 0;
        }
        if (cmd.status != 0) {
            //for a nicer error message
            if (canFind!"No such file"(cmd.output)) {
                return Ok(FileInfo(FileInfo.Type.NotFound, path, Size()));
                //return Err!(FileInfo, "%s not found")(path);
            }
            return Err!FileInfo("file: "~cmd.output.chompPrefix("ERROR: "));
        }
        FileInfo res;
        res.path = path;
        //TODO could be better (without regex?)
        if (auto m = cmd.output.matchFirst(ctRegex!`image.*, (\d+) *x *(\d+)`)) {
            auto width = m[1];
            auto height = m[2];
            res.type = FileInfo.Type.Image;
            // an exception is justified, this shouldn't happen (unless smth is)
            // wrong with my code.
            try {
                res.imageSize.width = width.parse!long;
                res.imageSize.height = height.parse!long;
            } catch (Exception e) {
                return Err!(FileInfo, "Can't parse image size: '%s' x '%s'")(
                    width, height);
            }
        }
        else if (canFind!"audio"(cmd.output))   res.type = FileInfo.Type.Audio;
        else if (canFind!"media"(cmd.output))   res.type = FileInfo.Type.Video;
        else if (canFind!"PDF"(cmd.output))     res.type = FileInfo.Type.Pdf;
        else if (canFind!"archive"(cmd.output)) res.type = FileInfo.Type.Archive;
        else if (canFind!"source"(cmd.output))  res.type = FileInfo.Type.Source;
        else if (canFind!"text"(cmd.output))    res.type = FileInfo.Type.Text;
        else res.type = FileInfo.Type.Other;
        return Ok(res);
    } catch (Exception e) {
        return Err!FileInfo("getFileInfo: "~e.msg);
    }
}
