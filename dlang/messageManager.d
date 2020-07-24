import fullMessage;
import misc;
import contactsList;
import config;

class DbusManager {
    import ddbus;
    Connection conn;
    PathIface obj;

    this() {
        static if (config.useDbusWidget) {
            conn = connectToBus();
            obj = new PathIface(conn, busName("org.azbyn.scli"),
                                ObjectPath("/"),
                                interfaceName("org.azbyn.scli"));
        }
    }

    void barUpdateUnread(long val) {
        static if (config.useDbusWidget)
            obj.opDispatch!("Update")(val);
    }

    bool shouldSendDisconnect = true;

    void barConnect() {
        static if (config.useDbusWidget)
            obj.opDispatch!("Connect")();
    }
    void barDisconnect() {
        static if (config.useDbusWidget)
            if (shouldSendDisconnect)
                obj.opDispatch!("Disconnect")();
    }
}

private string b64(string msg) {
    import std.base64;
    return Base64.encode(cast(immutable(ubyte)[])  msg);
}
private string b64(string[] msgs) {
    import std.base64;
    string res = "";
    foreach (m; msgs) res ~= b64(m);
    return res;
}



import graphics.renderMessage;
class MessageManager {
    import std.stdio;
    import database.messageHistory;
    import std.string;
    import app : ResultLong, NativeThread;

    ContactsList contacts;

    MessageHistory history;


    private bool initialized_ = false;
    bool initialized() const { return initialized_; }

    void sendPragmaSticker(in GroupOrContact goc, string val) {
        return sendMessage(goc, val, [], null);
    }
    void sendMessage(in GroupOrContact goc, string message,
                     string[] attachments,
                     in RenderMessage* quote) {
        message = message.strip;
        if (message.empty && attachments.empty)
            return;
        //todo add a "sendingMessages" to convoInfo and show that one till it
        // gets sent
        import std.parallelism;
        auto t = task!sendMessageImpl(history, goc, message,
                                      attachments, quote);
        //not perfect - we can't send and receive at the same time
        t.executeInNewThread();
    }
    static void sendMessageImpl(MessageHistory history,
                                in GroupOrContact goc, string message,
                                string[] attachments,
                                in RenderMessage* quote) {
        import app : attachCurrentThread;
        attachCurrentThread();
        import std.conv, std.algorithm : map;
        alias nt = NativeThread;
        auto wAtt = attachments.map!(x=>x.to!wstring);
        auto wMsg = message.to!wstring;

        ResultLong res;
        if (goc.isContact) {
            const Contact c = cast(const Contact) goc;
            auto dst = c.number.to!wstring;
            res = quote == null
                ? NativeThread.sendMessage(wMsg, wAtt, dst)
                : NativeThread.sendMessageWithQuote(
                    wMsg, wAtt, dst,
                    quote.signalTime.val,
                    quote.sender.number.to!wstring,
                    quote.message == "" ? "\u180E" : quote.message.to!wstring
                    );

        } else {
            auto g = cast(const Group) goc;
            res = quote == null
                ? NativeThread.sendGroupMessage(wMsg, wAtt, g.groupIdBytes)
                : NativeThread.sendGroupMessageWithQuote(
                    wMsg, wAtt, g.groupIdBytes,
                    quote.signalTime.val,
                    quote.sender.number.to!wstring,
                    quote.message.to!wstring
                    );
        }
        // if (res != 0) {
        //     history.onSendMessage(goc, message, attachments,
        //                           SignalTime(res));
        // }

        if (res.isSuccess) {
            import std.datetime.systime, std.path, std.file :copy;
            auto id = Clock.currTime().stdTime;
            foreach (ref a; attachments) {
                auto path = format!"%s%d__!%s"(attachmentsPath, id,
                                               baseName(a));
                copy(a, path);
                a = path;
            }
            history.onSendMessage(goc, message, attachments,
                                  SignalTime(res.val), quote);
        } else {
            //TODO ERROR MESSAGE
            derr!"sendMessage error '%s'"(res.error);
        }
    }
    void sync() {
        auto res = NativeThread.requestSyncAll();
        if (!res.isSuccess) {
            derr!"sync error '%s'"(res.error);
        } else {
            contacts.update();
        }
    }
    void react(in GroupOrContact goc, in RenderMessage msg, string reaction) {
        import std.conv;
        bool isRemove = reaction.empty;
        wstring emoji;
        if (isRemove) {
            auto ptr = msg.reactions.findPtr!(x=>x.sender == contacts.thisUser);
            if (ptr == null) {
                dwarn!"can't unreact if you didn't react before";
                return;
            }
            emoji = ptr.emoji.to!wstring;
        } else {
            emoji = reaction.to!wstring;
        }
        wstring targetAuthor = msg.sender.number.to!wstring;
        long targetSentTimestamp = msg.signalTime.val;

        auto res = goc.visit(
            (const Group g) => NativeThread.sendGroupMessageReaction(
                emoji, isRemove, targetAuthor, targetSentTimestamp,
                g.groupIdBytes),
            (const Contact c) => NativeThread.sendMessageReaction(
                emoji, isRemove, targetAuthor, targetSentTimestamp,
                c.number.to!wstring));
        if (!res.isSuccess) {
            derr!"react error %s"(res.error);
            return;
        }
        auto time = SignalTime(res.val);

        history.addReactionFromSelf(goc, msg.id, time, reaction);
        //TODO ? -just update the message with ref
        history.emit(goc);
    }

    this(MessageHistory history, ContactsList contacts) {
        this.history = history;
        this.contacts = contacts;
    }
    void evalLine(L)(scope L line) {
        try {
            // if (l.length == 0) return;
            logToFile(line);
            auto obj = parseJSON(line);
            auto e = "error" in obj;
            // dlog!"ln '%s'"(line);
            if (e != null)
                derr!"SENT ERROR %s"(*e);
            processJSON(obj["envelope"]);
        }
        catch (JSONException e) {
            derr!"Json exception %s\n'%s'"(e, line);
        }
        catch (Exception e) {
            derr("ERROR", e);
        }
    }

private:

    import std.json;
    void processJSON(JSONValue obj) {
        if (obj["isFull"].boolean) {
            auto e = Envelope(obj, contacts);
            history.receiveEnvelope(e);
        }
        else {
            if (obj["isReceipt"].boolean) return;
            if (!obj["dataMessage"].isNull) return;
        }
    }
}
