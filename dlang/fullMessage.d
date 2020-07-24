import std.json;
import std.typecons;
import std.conv;
// import std.datetime.systime;
import database.messageHistory;

import contactsList;
import misc;
import database.misc;

alias bytes = string;

//milliseconds since unix time 0
@DbInt
struct SignalTime {
    import std.math;
    long val;

    long opCmp(SignalTime s) const { return val - s.val; }// val.cmp(s.val); }

    auto toSystime() {
        import std.datetime.systime;
        import core.time;
        // "hnsecs" (hecto-nanoseconds - i.e. 100 ns)

        long msToHns(long ms) { return msecs(ms).total!"hnsecs"; }

        return SysTime(unixTimeToStdTime(val/1000)+msToHns(val%1000));
    }
}

struct Quote {
    SignalTime id;
    const Contact author;
    string text;

    // pragma(msg, genToString!Quote);
    mixin(genCtor!Quote);
    mixin(genToString!Quote);
}

struct Reaction {
    string emoji;
    SignalTime targetSentTimestamp;
    bool isRemove;
    string targetAuthorId;
    const Contact targetAuthor;

    mixin(genCtor!Reaction);
    mixin(genToString!Reaction);
}

struct Sticker {
    int id;
    bytes packId;
    bytes packKey;
    //attatchment

    mixin(genCtor!Sticker);
    mixin(genToString!Sticker);
}

struct RemoteDelete {
    SignalTime targetSentTimestamp;

    mixin(genCtor!RemoteDelete);
    mixin(genToString!RemoteDelete);
}

struct GroupInfo {
    const Group val;
    // bytes groupId;
    // string[] members;
    // string name;
    this(JSONValue v, ContactsList contacts) {
        val = contacts.getGroup(v["groupId"].str);
    }
    string toString() const { return "G`"~ val.name~"`"; }
}

struct DataMessage {
    bool hasPreview;

    SignalTime timestamp;
    int expiresInSeconds;
    string message;
    string[] attachments;
    Nullable!GroupInfo groupInfo;
    Nullable!Sticker sticker;
    Nullable!Reaction reaction;
    Nullable!RemoteDelete remoteDelete;
    Nullable!Quote quote;

    // pragma(msg, genToString!DataMessage);
    mixin(genCtor!DataMessage);
    mixin(genToString!DataMessage);

    const(GroupOrContact) groupOrContact(const Contact sender) const {
        return groupInfo.isNull ? sender : groupInfo.get.val;
    }
}

struct SentTranscript {
    const Contact destination; //may be null if message.group is not null
    SignalTime timestamp;
    DataMessage message;

    const(GroupOrContact) groupOrContact() const {
        return message.groupOrContact(destination);
    }

    mixin(genCtor!SentTranscript);
    mixin(genToString!SentTranscript);
}

struct SyncMessage {
    Nullable!SentTranscript sent;
    const(GroupOrContact) groupOrContact(const Contact sender) const {
        return !sent.isNull ? sent.get.groupOrContact : sender;
    }

    mixin(genCtor!SyncMessage);
    mixin(genToString!SyncMessage);
}
struct ReceiptMessage {
    enum Action {
        Delivery = 1, Read=2, Unknown= 0,
    }
    Nullable!SignalTime when;
    Action action;
    SignalTime[] timestamps;

    mixin(genCtor!ReceiptMessage);
    mixin(genToString!ReceiptMessage);
}
struct TypingMessage {
    enum Action {
        Started=1, Stopped=2, Unknown=0,
    }
    SignalTime timestamp;
    Action action;
    const Group groupId;//may be null

    mixin(genCtor!TypingMessage);
    mixin(genToString!TypingMessage);


    const(GroupOrContact) groupOrContact(const Contact sender) const {
        return groupId is null ? sender : groupId;
    }
}

struct Envelope {
    const Contact sender;
    Nullable!DataMessage message;
    Nullable!ReceiptMessage receiptMessage;
    bool callMessage;// Nullable!CallMessage callMessage;
    Nullable!TypingMessage typingMessage;
    Nullable!SyncMessage syncMessage;

    Nullable!DataMessage dataMessage() { return message; }

    const(GroupOrContact) groupOrContact() const {
        if (!message.isNull)
            return message.get.groupOrContact(sender);

        if (!syncMessage.isNull)
            return syncMessage.get.groupOrContact(sender);

        if (!typingMessage.isNull)
            return typingMessage.get.groupOrContact(sender);

        return sender;
    }

    mixin(genCtor!Envelope);
    mixin(genToString!Envelope);
}
