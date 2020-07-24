module database.misc;

import std.json;
import std.traits, std.conv, std.format, std.array;
import fullMessage, contactsList;

public import database.sql : DbInt;

struct AtTimestamp(T) {
    SignalTime ts;
    T val;

    void update(SignalTime newTs, T newVal) {
        if (newTs < ts) return;
        val = newVal;
        ts = newTs;
    }

    alias val this;
}
