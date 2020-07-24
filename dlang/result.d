struct Result(V, E = string) {
    import std.traits, std.range;
    private bool isSuccess_;
    union {
        private V val_;
        private E err_;
    }

    string toString() const {
        import std.format;
        return isSuccess ? format!"Ok(%s)"(val) : format!"Err(%s)"(err);
    }

    @property bool isSuccess() const { return isSuccess_; }
    @property bool isError() const { return !isSuccess_; }
    @property V value() const { return val; }
    @property E error() const { return err; }

    @property V val() const {
        debug assert(isSuccess, "Expected success, got error.");
        return val_;
    }
    @property E err() const {
        debug assert(isError, "Expected error, got success.");
        return err_;
    }

    // in a parser we may want to return "" if it doesn't match
    // and some sort of error if something failed (like mismatched parens)
    // if that's the case we want to get the more expressive error message
    static if (isSomeString!E) {
        bool isLightError() const { return isError && error.empty; }
        bool isRealError() const { return isError && !error.empty; }
        auto or(lazy Result v) const {
            if (isSuccess) return this;
            auto o = v;
            if (o.isLightError) return this;
            return o;
        }
    } else {
        auto or(lazy Result v) const {
            return isSuccess ? this : v;
        }
    }

    static auto Err(E e) {
        auto r = Result!(V, E)();
        r.isSuccess_ = false;
        r.err_ = e;
        return r;
    }
    static auto Ok(V v) {
        auto r = Result!(V, E)();
        r.isSuccess_ = true;
        r.val_ = v;
        return r;
    }
}
auto Err(V, E = string)(E e) {
    return Result!(V, E).Err(e);
}

auto Err(V, string fmt, Args...)(Args args) {
    import std.format;
    return Result!(V).Err(format!fmt(args));
}

auto LightErr(V, E = string)() { return Err!V(""); }
auto Ok(V, E = string)(V v) {
    return Result!(V, E).Ok(v);
}

//similar to haskell's do notation
auto do_(V, E, Fs...)(Result!(V, E) res, Fs fs) {
    import std.traits;
    static assert(fs.length > 0);
    alias F = fs[0];
    static assert (isSomeFunction!F);
    static assert (__traits(isSame, TemplateOf!(ReturnType!F), Result));

    // res' V might be different to the return type's V
    auto makeFinalError(Ts...)(Ts ts) {
        static assert (ts.length > 0);
        alias F = ts[0];
        static assert (isSomeFunction!F);
        alias Ret = ReturnType!F;
        static assert (__traits(isSame, TemplateOf!Ret, Result));

        static if (ts.length == 1) {
            return Ret.Err(res.error);
        }
        else return makeFinalError(ts[1..$]);
    }

    if (res.isError) {
        return makeFinalError(fs);
    }
    auto val = F(res.val);
    static if (fs.length >= 2) {
        return do_(val, fs[1..$]);
    }
    else return val;
}
unittest {
    import std.conv;
    {
        auto v = do_(Ok!int(1),
                     (int x) => Ok(x.to!string),
                     (string s) => Ok(s ~"="));
        assert(v.val == "1=");
    }

    {
        auto v = do_(Err!int("NiE"),
                 (int x) => Ok(x.to!string),
                 (string s) => Ok(s ~"="));
        assert(v.error == "NiE");
    }
    {
        auto v = do_(Ok!int(1),
                     (int x) => Err!string("nie"),
                     (string s) => Ok(s ~"="));

        assert(v.err == "nie");
    }
}
