module database.messageHistory;

import fullMessage;
import messageManager;
import std.string;
import std.traits;
import contactsList;
import std.typecons;
import fullMessage;
import graphics.renderMessage;

import misc;
import database.misc;

//TODO store this? in the database?
struct ConvoInfo {
    import fullMessage, std.datetime.systime;
    alias IsTyping = AtTimestamp!bool;

    SysTime /*SignalTime*/ lastRead;
    int unreadCount;
    IsTyping[const Contact] typingVector;

    //@disable this(this);
    //@disable this();

    this(SignalTime lastRead) {
        this.lastRead = lastRead.toSystime;
        this.unreadCount = 0;
    }

    void update(in RenderMessage lastRead, in RenderMessage[] sortedMessages) {
        if (lastRead.timestamp < this.lastRead)
            return;
        this.lastRead = lastRead.timestamp;
        //we expect there to be a lot more unread messages than read,
        // so we search for the first one that was sent before the lastRead
        unreadCount = 0;
        import std.range;
        foreach (m; sortedMessages.retro) {
            if (m.timestamp <= lastRead.timestamp) break;
            ++unreadCount;
        }
    }
    void setTyping(const Contact sender, TypingMessage tm) {
        if (tm.action == TypingMessage.Action.Unknown)
            dwarn("Typing action == unknown");

        bool typing = tm.action == TypingMessage.Action.Started;
        if (auto ptr = sender in typingVector)
            ptr.update(tm.timestamp, typing);
        else
            typingVector[sender] = IsTyping(tm.timestamp, typing);
    }
}

// alias dbstring = wstring;
//it also sends notifications and updates the ui
class MessageHistory {
    import std.algorithm, std.array;
    import std.json;
    import std.signals;
    import config;

    import d2sqlite3.database;
    import database.sql;

    mixin Signal!(const GroupOrContact);

private:
    Database db;

    DbusManager dbus;
    ContactsList contacts;
    private ConvoInfo[const GroupOrContact] convoInfos;

    //kinda ugly but we have to do this to get id type safety
    static foreach(a; ["messages", "conversations", "stickers",
                       "attachments", "reactions"])
        mixin("public "~ genTableId!a);

    // TODO receipt
    // TODO messages to be deleted
    mixin(genTable!("conversations",
                    [SELECT!("all"),
                     SELECT!("find", "WHERE name == :name",
                             string, "name"/*, bool, "isContact"*/),
                     UPDATE!("updateExpiresInSeconds",
                             long, "expiresInSecondsVal",
                             SignalTime, "expiresInSecondsTs",
                         )
                    ],
                    string, "name",
                    bool, "isContact",
                    // like AtTimestamp!long
                    long, "expiresInSecondsVal",
                    SignalTime, "expiresInSecondsTs",
                    // ExpiresInSeconds, "expiresInSeconds",
                    // long, "notificationCounter"
              ));
    alias ConvoId = ConversationId;
    // inserts in the database if it doesn't exist
    ConvoId getConvoId(const GroupOrContact goc) {
        return getConvoIdAndUpdate(goc, AtTimestamp!long(SignalTime(0), 0));
    }
    ConvoId getConvoIdAndUpdate(const GroupOrContact goc,
                                AtTimestamp!long expiresInSeconds) {
        string name = goc.numberOrId;
        bool isContact = goc.isContact;
        auto convo = conversations.find(name/*, isContact*/);
        if (!convo.empty) {
            auto c = convo.front;
            if (c.expiresInSecondsVal != expiresInSeconds.val &&
                c.expiresInSecondsTs < expiresInSeconds.ts) {
                conversations.updateExpiresInSeconds(c.id, expiresInSeconds.val,
                                                     expiresInSeconds.ts);
            }
            return c.id;
        }
        return conversations.insert(db, name, isContact,
                                    expiresInSeconds.val,
                                    expiresInSeconds.ts);
    }
    mixin(genTable!("messages",
                    [SELECT!("fromConvo",
                             "WHERE convoId == :cid",
                             ConvoId, "cid"),
                     SELECT!("fromId", "WHERE id == :id",
                             MessageId, "id"),
                     SELECT!("latestFrom",
                             "WHERE convoId == :cid ORDER BY timestamp DESC LIMIT 1",
                             ConvoId, "cid"),
                     SELECT!("find",
                             "WHERE (timestamp == :ts AND senderName == :name
                                      AND convoId == :cid)",
                             SignalTime, "ts",
                             string,     "name",
                             ConvoId,    "cid"),
                     UPDATE!("replacePlaceholder",
                             bool,        "isPlaceholder",
                             bool,        "hasAttachments",
                             bool,        "hasPreview",
                             string,      "message",
                             MessageId,   "quotedMsgId",
                             StickerId,   "stickerId",
                         ),
                    ],
                    ConvoId,     "convoId",
                    string,      "senderName",
                    bool,        "hasAttachments",
                    bool,        "isPlaceholder",
                    bool,        "hasPreview",
                    SignalTime,  "timestamp",
                    string,      "message",
                    MessageId,   "quotedMsgId", // 0 means no quote
                    StickerId,   "stickerId",   // 0 means no sticker
              ));

    public Nullable!Message findQuotedMessage(MessageId id) {
        if (id.val == 0) return Nullable!Message();
        auto val = messages.fromId(id);
        if (val.empty) {
            derr!"message %d not found"(id.val);
            return Nullable!Message();
        }
        return val.front.nullable;
    }


    mixin(genTable!("attachments",
                    [SELECT!("fromMsg", "WHERE msgId == :id",
                             MessageId, "id"),
                        ],
                    MessageId, "msgId",
                    string,    "path"));

    public string[] getAttachments(MessageId id) {
        return attachments.fromMsg(id).map!(x=>x.path).array;
    }
    mixin(genTable!("reactions",
                    [SELECT!("fromMsg", "WHERE msgId == :id",
                             MessageId, "id"),
                     SELECT!("find",
                             "WHERE (msgId == :msgId AND senderName == :name)",
                             MessageId, "msgId", string, "name"),
                     UPDATE!("update",
                             string, "emoji",
                             SignalTime, "timestamp"),
                    ],
                    MessageId,  "msgId",
                    string,     "emoji",
                    string,     "senderName",
                    SignalTime, "timestamp"));
    public auto findReactions(MessageId id) { return reactions.fromMsg(id); }
    mixin(genTable!("stickers",
                    [SELECT!("fromId", "WHERE id == :sid",
                             StickerId, "sid"),
                     SELECT!("find",
                             "WHERE signalId == :sid AND packId == :pid AND "~
                             "packKey == :key",
                             long, "sid", string, "pid", string, "key"),
                    ],
                    long,   "signalId",
                    string, "packId",
                    string, "packKey"));
    //StickerPath = Nullable!(string, "");
    public StickerPath findStickerPath(StickerId id) {
        if (id.val == 0) return StickerPath();
        auto val = stickers.fromId(id);
        if (val.empty) {
            derr!"sticker %d not found"(id.val);
            return StickerPath();
        }
        auto s = val.front;
        dwarn!"we don't support stickers yet, here's tofuchan instead";
        return StickerPath("/home/azbyn/img.png");//.nullable;//!"";
    }

public:

    public alias Message = Messages.Res;
    this(DbusManager dbus, ContactsList contacts) {
        this.dbus = dbus;
        this.contacts = contacts;

        import std.file, std.stdio : File;

        db = Database(config.databasePath);

        conversations.init(db);
        messages.init(db);
        attachments.init(db);
        reactions.init(db);
        stickers.init(db);

        foreach (convo; conversations.all()) {
            auto latest = messages.latestFrom(convo.id);
            if (latest.empty) continue;
            auto goc = convo.isContact
                ? contacts.getContact(convo.name)
                : contacts.getGroup(convo.name);
            convoInfos[goc] = ConvoInfo(latest.front.timestamp);
        }
    }

    //TODO don't get all of them
    RenderMessage[] messagesFrom(const GroupOrContact from) {
        auto convoId = getConvoId(from);
        auto fromConvo = messages.fromConvo(convoId);
        //auto res = uninitializedArray!(RenderMessage[])(fromConvo.length);
        //Appender!(RenderMessage[]) res = appender!RenderMessage;
        RenderMessage[] res;
        long i = 0;
        foreach (m; fromConvo) {
            res ~= RenderMessage(m, this, contacts, res[0..i]);
            ++i;
        }
        return res;
        //return messages.fromConvo(convoId).map!(
        //    x => RenderMessage(x, this, contacts)).array;
    }

    // scope const(HistoryMessage[]) messagesFrom(GroupOrContact from) {
    //     return getConvo(from).history;
    // }
    ref ConvoInfo getConvoInfo(const GroupOrContact from) {
        return convoInfos.require(from, ConvoInfo());
    }
    auto getUnreadCount(const GroupOrContact goc) {
        return getConvoInfo(goc).unreadCount;
    }
    void receiveEnvelope(Envelope e) {
        auto goc = e.groupOrContact;
        if (e.groupOrContact is null) {
            derr("empty group or contact");
            return;
        }
        if (!e.typingMessage.isNull)
            getConvoInfo(goc).setTyping(e.sender, e.typingMessage.get);
        // static if (verbose) {
        //     if (!e.callMessage)
        //         dlog("callMessage");
        //     if (!e.typingMessage.isNull) {
        //         auto t = e.typingMessage.get;
        //         dlog!"%s %s typing @%s"(e.sender.toString, t.action, t.groupId);
        //     }
        //     if (!e.receiptMessage.isNull) {
        //         auto r = e.receiptMessage.get;
        //         dlog!"receipt %s %s"(e.sender.toString, r.action);
        //     }
        // }

        if (!e.syncMessage.isNull && !e.syncMessage.get.sent.isNull) {
            auto s = e.syncMessage.get.sent.get;
            addToHistory(goc, s.message, s.destination);
        }
        if (!e.dataMessage.isNull) {
            addToHistory(goc, e.dataMessage.get, e.sender);
        }
    }
    void onSendMessage(const GroupOrContact goc, string message,
                       string[] attachments, SignalTime timestamp,
                       in RenderMessage* quote) {
        auto cid = getConvoId(goc);
        auto qid = getQuotedMessageId(cid, quote);
        addSentMessage(cid, message, attachments, timestamp, qid);
        emit(goc);
    }

    void updateConvoInfo(const GroupOrContact goc,
                         in RenderMessage lastRead,
                         in RenderMessage[] sortedMessages) {
        getConvoInfo(goc).update(lastRead, sortedMessages);
        //hax
        contacts.emit();
        updateBar();
    }

    void notify(const GroupOrContact goc) {

        //we just do this, we'll get a better estimate when we
        //call updateConvoInfo
        getConvoInfo(goc).unreadCount++;
        //import std.range;
        string r = "";
        updateBar();
        emit(goc);
    }
    private void updateBar() {
        long sum = 0;
        foreach (_, ci; convoInfos) sum += ci.unreadCount;
        dbus.barUpdateUnread(sum);
    }

private:
    void addAttachments(MessageId msgId, string[] val) {
        foreach (a; val)
            attachments.insert(db, msgId, a);
    }
    StickerId getSticker(Nullable!Sticker sticker) {
        if (sticker.isNull) return StickerId.null_;
        auto s = sticker.get;
        auto res = stickers.find(s.id, s.packId, s.packKey);
        if (!res.empty)
            return res.front.id;
        return stickers.insert(db, s.id, s.packId, s.packKey);
    }
    MessageId findMessageId(ConvoId convoId,
                            const Contact author,
                            SignalTime ts,
                            string placeholderMessage = "PLACEHOLDER") {
        auto res = messages.find(ts, author.number, convoId);
        if (res.empty) {
            dwarn!"message not found. Adding as a placeholder.";
            return addPlaceholderMsg(convoId, ts, author, placeholderMessage);
        }
        return res.front.id;
    }
    MessageId getQuotedMessageId(ConvoId convoId, Nullable!Quote q) {
        if (q.isNull) return MessageId.null_;
        auto val = q.get;
        auto ts = val.id;
        return findMessageId(convoId, val.author, ts, val.text);
    }

    MessageId getQuotedMessageId(ConvoId convoId, in RenderMessage* q) {
        if (q == null) return MessageId.null_;
        return findMessageId(convoId, q.sender, q.signalTime, q.message);
    }

    public alias HistoryMessage = Messages.Res;

    auto getSenderName(const Contact sender) {
        return sender.number;
    }

    auto addSentMessage(ConvoId convoId, string message,
                        string[] attachments, SignalTime timestamp,
                        MessageId quotedMsgId) {
        return addToHistoryImpl(
            convoId,
            contacts.thisUser,
            attachments,
            false,//isPlaceholder
            false,//hasPreview
            timestamp,
            message,
            quotedMsgId);
    }
    auto addMessage(ConvoId convoId, DataMessage msg,
                    const(Contact) sender) {
        return addToHistoryImpl(
            convoId,
            sender is null ? contacts.thisUser : sender,
            msg.attachments,
            false,//isPlaceholder
            msg.hasPreview,
            msg.timestamp,
            msg.message,
            getQuotedMessageId(convoId, msg.quote),
            getSticker(msg.sticker),
            );
    }

    auto addPlaceholderMsg(ConvoId convoId, SignalTime timestamp,
                           const Contact sender, string msg) {
        return addToHistoryImpl(
            convoId,
            sender,
            [],//attachments
            true,//isPlaceholder
            false,//hasPreview
            timestamp,
            msg);
    }

    MessageId addToHistoryImpl(ConvoId convoId,
                               const Contact sender,
                               string[] attachments,
                               bool isPlaceholder,
                               bool hasPreview,
                               SignalTime timestamp,
                               string message,
                               MessageId quotedMsgId = MessageId.null_,
                               StickerId stickerId   = StickerId.null_) {
        MessageId generateMessageId(ConvoId cid, SignalTime time) {
            if (cid.val >= 1<<16) {
                derr!"You cant have that many conversations (%s)"(cid);
            }
            //this means greater than year 04/03/584556019 @ 2:25pm (UTC)
            if (time.val >= 1L << 48) {
                derr!"Greetings from the 2020! We don't support your time (%s)"(
                    time.toSystime);
            }
            return MessageId(cid.val << 48L | time.val);
        }
        HistoryMessage mkMsg() {
            HistoryMessage res;
            res.convoId = convoId;
            res.senderName = getSenderName(sender);
            res.hasAttachments = attachments.length != 0;
            res.isPlaceholder = isPlaceholder;
            res.hasPreview = hasPreview;
            res.timestamp = timestamp;
            res.message = message;
            res.quotedMsgId = quotedMsgId;
            res.stickerId = stickerId;
            res.id = generateMessageId(convoId, timestamp);
            return res;
        }
        auto val = mkMsg();
        auto impl() {
            if (!val.isPlaceholder) {
                auto res = messages.find(val.timestamp, val.senderName,
                                         val.convoId);
                if (!res.empty) {
                    auto id = res.front.id;
                    messages.replacePlaceholder(
                        id,
                        val.isPlaceholder,
                        val.hasAttachments,
                        val.hasPreview,
                        val.message,
                        val.quotedMsgId,
                        val.stickerId);
                    return id;
                }
            }
            return messages.insertWithID(db, val);
        }
        auto msgID = impl();

        if (val.hasAttachments)
            addAttachments(msgID, attachments);
        return msgID;
    }
    public void addReactionFromSelf(in GroupOrContact goc, MessageId msgId,
                                    SignalTime newTs, string emoji) {
        auto convoId = getConvoId(goc);

        auto senderName = getSenderName(contacts.thisUser);
        auto res = reactions.find(msgId, senderName);

        if (res.empty) {
            reactions.insert(db, msgId, emoji, senderName, newTs);
        } else {
            auto reaction = res.front;
            if (reaction.timestamp < newTs) {
                reactions.update(reaction.id, emoji, newTs);
            }
        }
    }
    void addReaction(ConvoId convoId, in Contact sender, Reaction val,
                     SignalTime newTs,
                     MessageId* outMessageId) {
        if (val.isRemove)
            val.emoji = "";
        auto msgId = findMessageId(convoId, val.targetAuthor,
                                   val.targetSentTimestamp);
        *outMessageId = msgId;
        auto senderName = getSenderName(sender);//getSenderName(val.targetAuthor);
        auto res = reactions.find(msgId, senderName);

        if (res.empty) {
            reactions.insert(db, msgId, val.emoji, senderName, newTs);
        } else {
            auto reaction = res.front;
            if (reaction.timestamp < newTs) {
                reactions.update(reaction.id, val.emoji, newTs);
            }
        }
    }
    void addToHistory(const GroupOrContact goc, DataMessage msg,
                      in Contact sender) {
        if (!msg.remoteDelete.isNull) {
            dwarn!"WE GOT A REMOTE DELETE WAAAAT?! %s"(msg.remoteDelete.get);
        }
        if (sender is null) {
            //this ony seems to happen when we send a message from the phone
            //on a group
            //dwarn("Null sender, assumming self");
            if (contacts.thisUser is null) {
                derr!"infinite loop prevented";
                return;
            }
            //we can't reassign sender
            addToHistory(goc, msg, contacts.thisUser);
            return;
        }

        auto convoId = getConvoIdAndUpdate(goc, AtTimestamp!long(
                                               msg.timestamp,
                                               msg.expiresInSeconds));
        if (!msg.reaction.isNull) {
            auto r = msg.reaction.get;
            MessageId msgId;
            addReaction(convoId, sender, r, msg.timestamp, &msgId);
            //TODO add a new notify with (goc, msgId);?
            notify(goc, );
            if (msg.message == "" && msg.sticker.isNull) return;
        }
        addMessage(convoId, msg, sender);
        notify(goc);
    }
}
