import std.json;
import std.string;

import misc;
import database.messageHistory;

class GroupOrContact {
    immutable bool isContact;
    bool isGroup() const { return !isContact; }
    this(bool isContact) {
        this.isContact = isContact;
    }

    auto ref visit(T)(T delegate(const Contact) c,
                      T delegate(const Group) g) const {
        return isContact ?
            c(cast(const Contact) this) : g(cast(const Group) this);
    }
    auto ref visit(T)(T delegate(const Group) g,
                      T delegate(const Contact) c) const {
        return isContact
            ? c(cast(const Contact) this)
            : g(cast(const Group) this);
    }
    auto ref visit(T)(T function(Contact) c,
                      T function(Group) g) const {
        return isContact
            ? c(cast(const Contact) this)
            : g(cast(const Group) this);
    }
    auto ref visit(T)(T function(Group) g,
                      T function(Contact) c) const {
        return isContact
            ? c(cast(const Contact) this)
            : g(cast(const Group) this);
    }

    string name;
    long messageExpirationTime;

    abstract string theName() const;
    abstract string numberOrId() const;
}

class Contact : GroupOrContact {
    string number;
    string uuid;

    string shortName() const { return theName()[0..1]; }

    override string theName() const {
        return this is null ? "NULL" : (name == "" ? number : name);
    }
    override string numberOrId() const { return number; }

    this(JSONValue val, ContactsList cl) {
        super(/*isContact*/ true);
        this.name = val["name"].getVal!(string)(cl);
        this.number = val["number"].getVal!(string)(cl);
        this.uuid = val["uuid"].getVal!(string)(cl);
        this.messageExpirationTime =
            val["messageExpirationTime"].getVal!(long)(cl);
    }
    //mixin(genCtor!Contact);
    this(string number, string uuid) {
        super(/*isContact*/ true);
        this.number = number;
        this.uuid = uuid;
        messageExpirationTime = 0;
        name = "";
    }
    override string toString() const { return format!"C`%s`"(theName); }
}

class Group : GroupOrContact {
    string groupId;
    const(Contact)[] members;

    override string numberOrId() const { return groupId; }

    byte[] groupIdBytes() const {
        import std.base64;
        auto res = cast(byte[]) Base64.decode(groupId);
        return res;
    }
    this(JSONValue val, ContactsList cl) {
        super(/*isContact*/false);
        this.groupId = val["groupId"].getVal!(string)(cl);
        this.name = val["name"].getVal!(string)(cl);
        this.messageExpirationTime =
            val["messageExpirationTime"].getVal!(long)(cl);
        this.members =
            val["members"].getVal!(const(contactsList.Contact)[])(cl);
    }
    //mixin(genCtor!Group);
    override string toString() const {
        if (this is null) return "NULL";
        string res = "";
        foreach (m; members) res ~= m.toString ~ ", ";
        return format!"id `%s`; `%s`; members: [%s]"(groupId, name, res);
    }
    override string theName() const {
        return this is null ? "NULL" : name;
    }
}
// emits a signal on contacts or groups update
class ContactsList {
    import config;
    import std.signals;

    private Contact[] contacts_;
    private Group[] groups_;
    const string path;

    const(Contact)[] contacts() const { return contacts_; }
    const(Group)[] groups() const { return groups_; }

    mixin Signal!();

    const Contact thisUser;

    this(string userNumber) {
        path = config.getSignalCliConfigFile(userNumber);

        updateImpl!true();

        this.thisUser = getContact(userNumber);
        emit();
    }

    void update() {
        updateImpl!false();
        emit();
    }
    private void updateImpl(bool isFirst)() {
        import std.file, std.array;
        // this.path = path;
        auto text = readText(path);

        JSONValue val = parseJSON(text);
        auto jcontacts = val["contactStore"]["contacts"].array;
        auto jgroups = val["groupStore"]["groups"].array;
        static if (isFirst) {
            this.contacts_ = uninitializedArray!(Contact[])(jcontacts.length);
            foreach (i, o; jcontacts)
                this.contacts_[i] = new Contact(o, this);
            this.groups_ = uninitializedArray!(Group[])(jgroups.length);
            foreach (i, o; jgroups)
                this.groups_[i] = new Group(o, this);
        } else {
            foreach (o; jcontacts) {
                auto number = o["number"].str;
                auto ptr = contacts_.findPtr!((c) => c.number == number);
                if (ptr == null) {
                    this.contacts_ ~= new Contact(o, this);
                }
            }
            foreach (o; jgroups) {
                auto id = o["groupId"].str;
                auto ptr = groups_.findPtr!(g => g.groupId == id);
                if (ptr == null) {
                    this.groups_ ~= new Group(o, this);
                }
            }
        }
    }

    const(Contact) getContact(string number,
                              string uuid = "",
                              string f = __FILE__,
                              long n = __LINE__) {
        auto ptr = contacts_.findPtr!((c) => c.number == number);
        if (ptr) {
            return *ptr;
        }
        else {
            auto j = contacts_.length;
            contacts_ ~= new Contact(number, uuid);
            emit();
            dwarn!"'%s' not found in contacts. Adding as a temporary."(number);
            return contacts_[j];
        }
    }
    const(Group) getGroup(string groupId) const {
        auto ptr = groups_.findPtr!((g) => g.groupId == groupId);
        assert(ptr != null, "GroupId `"~groupId~"` not found");
        return *ptr;
    }
}
