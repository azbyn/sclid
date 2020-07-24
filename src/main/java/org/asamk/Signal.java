package org.asamk;

import org.asamk.signal.JsonDbusReceiveMessageHandler;
import org.asamk.signal.Main;
import org.asamk.signal.manager.Manager;
import org.whispersystems.signalservice.api.messages.*;
import org.whispersystems.signalservice.api.messages.calls.SignalServiceCallMessage;
import org.whispersystems.signalservice.api.messages.multidevice.SentTranscriptMessage;
import org.whispersystems.signalservice.api.messages.multidevice.SignalServiceSyncMessage;
import org.whispersystems.signalservice.api.push.SignalServiceAddress;
import org.whispersystems.util.Base64;

import java.util.ArrayList;
import java.util.List;

/**
 * DBus interface for the org.asamk.Signal service.
 * Including emitted Signals and returned Errors.
 */
public interface Signal {
/*
    long sendFancy(String message);

    long sendMessage(String message, List<String> attachments, String recipient) throws Error.AttachmentInvalid, Error.Failure, Error.InvalidNumber;

    long sendMessage(String message, List<String> attachments, List<String> recipients) throws Error.AttachmentInvalid, Error.Failure, Error.InvalidNumber, Error.UnregisteredUser, Error.UntrustedIdentity;

    void sendEndSessionMessage(List<String> recipients) throws Error.Failure, Error.InvalidNumber, Error.UnregisteredUser, Error.UntrustedIdentity;

    long sendGroupMessage(String message, List<String> attachments, byte[] groupId) throws Error.GroupNotFound, Error.Failure, Error.AttachmentInvalid, Error.UnregisteredUser, Error.UntrustedIdentity;

    String getContactName(String number) throws Error.InvalidNumber;

    void setContactName(String number, String name) throws Error.InvalidNumber;

    void setContactBlocked(String number, boolean blocked) throws Error.InvalidNumber;

    void setGroupBlocked(byte[] groupId, boolean blocked) throws Error.GroupNotFound;

    List<byte[]> getGroupIds();

    String getGroupName(byte[] groupId);

    List<String> getGroupMembers(byte[] groupId);

    byte[] updateGroup(byte[] groupId, String name, List<String> members, String avatar) throws Error.AttachmentInvalid, Error.Failure, Error.InvalidNumber, Error.GroupNotFound, Error.UnregisteredUser, Error.UntrustedIdentity;

    boolean isRegistered();
*/
    //////
    @SuppressWarnings("SameParameterValue")
    class FullMessage {

        //public final long timestamp;
        public final String sender;
        public final Manager m;

        public final SignalServiceContent content;

        /*
  //private final SignalServiceAddress      sender;
  //private final int                       senderDevice;
  //private final long                      serverTimestamp;
  //private final boolean                   needsReceipt;
  //private final SignalServiceContentProto serializedState;

        * */

        String s(String name, SignalServiceDataMessage val) {
            if (val == null) return sNull(name);
            return s(name) + "{"+
                    s("hasPreview", val.getPreviews().isPresent()) + "," +
                    s("timestamp", val.getTimestamp()) + "," +
                    s("expiresInSeconds", val.getExpiresInSeconds()) + "," +
                    s("groupInfo", val.getGroupContext().orNull()) + "," +
                    s("message", val.getBody().or("")) + "," +
                    s("attachments", JsonDbusReceiveMessageHandler.getAttachments(val, m)) + "," +
                    s("sticker", val.getSticker().orNull()) + "," +
                    s("reaction", val.getReaction().orNull()) + "," +
                    s("remoteDelete", val.getRemoteDelete().orNull()) + "," +
                    s("quote", val.getQuote().orNull()) + "}";
        }
        String s(String name, SentTranscriptMessage val) {
            if (val == null) return sNull(name);
            /*
  private final Optional<SignalServiceAddress> destination;
  private final long                           timestamp;
  private final long                           expirationStartTimestamp;
  private final SignalServiceDataMessage       message;
  private final Map<String, Boolean>           unidentifiedStatusByUuid;
  private final Map<String, Boolean>           unidentifiedStatusByE164;
  private final Set<SignalServiceAddress>      recipients;
  private final boolean                        isRecipientUpdate;
            * */
            return s(name) + "{"+
                    s("destination", val.getDestination().orNull()) + "," +
                    s("timestamp", val.getTimestamp()) + "," +
                    s("message", val.getMessage()) + //"," +
                    //s("expirationStartTimestamp", val.getExpirationStartTimestamp()) + "," +
                    //s("")
                    //s("groups", val.getGroups()) + "," +
                    //s("when", val.getWhen()) +
                    "}";
        }
        String s(String name, SignalServiceSyncMessage val) {
            if (val == null) return sNull(name);
            /*
  private final Optional<SentTranscriptMessage>             sent;
  private final Optional<ContactsMessage>                   contacts;
  private final Optional<SignalServiceAttachment>           groups;
  private final Optional<BlockedListMessage>                blockedList;
  private final Optional<RequestMessage>                    request;
  private final Optional<List<ReadMessage>>                 reads;
  private final Optional<ViewOnceOpenMessage>               viewOnceOpen;
  private final Optional<VerifiedMessage>                   verified;
  private final Optional<ConfigurationMessage>              configuration;
  private final Optional<List<StickerPackOperationMessage>> stickerPackOperations;
  private final Optional<FetchType>                         fetchType;
  private final Optional<KeysMessage>                       keys;
  private final Optional<MessageRequestResponseMessage>     messageRequestResponse;
            * */

            return s(name) + "{"+
                    s("sent", val.getSent().orNull()) + //"," +
                    //s("contacts", val.getContacts().orNull()) + "," +
                    //s("groups", val.getGroups()) + "," +
                    //s("when", val.getWhen()) +
                    "}";
        }
        static String s(String name, SignalServiceCallMessage val) {
            return s(name, val==null);
        }
        static String s(String name, SignalServiceReceiptMessage.Type val) {
            switch (val) {
                case DELIVERY: return s(name, 1);
                case READ: return s(name, 2);
                default: return s(name, 0); //unknown
            }
        }
        static String s(String name, SignalServiceReceiptMessage val) {
            if (val == null) return sNull(name);

            return s(name) + "{"+
                    s("action", val.getType()) + "," +
                    sl("timestamps", val.getTimestamps()) + "," +
                    s("when", val.getWhen()) + "}";
        }
        static String s(String name, SignalServiceTypingMessage.Action val) {
            switch (val) {
                case STARTED: return s(name, 1);
                case STOPPED: return s(name, 2);
                default: return s(name, 0); //unknown
            }
        }

        static String s(String name, SignalServiceTypingMessage val) {
            if (val == null) return sNull(name);
            return s(name) + "{"+
                    s("action", val.getAction()) + "," +
                    s("timestamp", val.getTimestamp()) + "," +
                    s("groupId", val.getGroupId().orNull()) + "}";
        }


        public FullMessage(SignalServiceContent content,
                           String sender, Manager m) {
            this.content = content;
            this.m = m;
            this.sender = sender;
            //this.timestamp = ;
        }

        public static String escaped(String s){
            if (s==null) return "null";
            return '"' + s.replace("\\", "\\\\")
                           .replace("\t", "\\t")
                           .replace("\b", "\\b")
                           .replace("\n", "\\n")
                           .replace("\r", "\\r")
                           .replace("\f", "\\f")
                           //.replace("'", "\\'")
                           .replace("\"", "\\\"") + '"';
        }
        static String s(String name) { return "\""+name+"\":"; }
        static String s(String name, String val) {
            return s(name) + escaped(val);
        }
        static String s(String name, long val) {
            return s(name) + val;
        }
        static String s(String name, byte[] val) {
            if (val == null) return sNull(name);
            var d = '"' + Base64.encodeBytes(val) + '"';
            //var d = "\"" + new String(val) + '"';
            return s(name) + d;
        }
        static String sNull(String name) {
            return s(name) + "null";
        }
        static String s(String name, SignalServiceDataMessage.Quote val) {
            if (val == null) return sNull(name);
            //Main.log(String.format("text nul %s", val.getText() == null));
            //Main.log(String.format("text %s", val.getText()));
            return s(name) + "{"+
                    s("id", val.getId()) + "," +
                    s("author", val.getAuthor()) + "," +
                    s("text", val.getText())+
                    "}";
        }
        static String s(String name, SignalServiceAddress val) {
            if (val == null) return sNull(name);
            return s(name, val.getNumber().get());
        }

        static String s(String name, SignalServiceDataMessage.Sticker val) {
            if (val == null) return sNull(name);
            return s(name) + "{"+
                    s("id", val.getStickerId()) + "," +
                    s("packId", val.getPackId()) + "," +
                    //s("attachment", val.getAttachment()) + "," +
                    s("packKey", val.getPackKey()) +"}";
        }
        static String s(String name, SignalServiceDataMessage.Reaction val) {
            if (val == null) return sNull(name);
            return s(name) + "{"+
                    s("emoji", val.getEmoji()) + "," +
                    s("targetSentTimestamp", val.getTargetSentTimestamp()) + "," +
                    s("isRemove", val.isRemove()) + "," +
                    s("targetAuthorId", val.getTargetAuthor().getIdentifier()) + "," +
                    s("targetAuthor", val.getTargetAuthor()) + "}";
        }
        static String s(String name, SignalServiceDataMessage.RemoteDelete val) {
            if (val == null) return sNull(name);
            return s(name) + "{"+
                s("targetSentTimestamp", val.getTargetSentTimestamp()) + "}";
        }
        static String sa(String name, List<SignalServiceAddress> val) {
            if (val == null) return sNull(name);
            List<String> members = new ArrayList<>(val.size());
            for (SignalServiceAddress address : val) {
                members.add(address.getNumber().get());
            }
            return s(name, members);
        }

        static String s(String name, SignalServiceGroupContext val) {
            if (val == null || !val.getGroupV1().isPresent()) return sNull(name);
            var v = val.getGroupV1().get();
            return s(name) + "{"  +
                    s("groupId", v.getGroupId()) + "," +
                    sa("members", v.getMembers().orNull()) + "," +
                    s("name", v.getName().orNull()) +
                    "}";
        }
        static String s(String name, boolean val) {
            return s(name) + val;
        }

        static String sl(String name, List<Long> val) {
            if (val == null) return sNull(name);
            StringBuilder res = new StringBuilder("[");
            if (val.size() != 0) {
                for (int i = 0; i < val.size() - 1; ++i) {
                    res.append(val.get(i));
                    res.append(",");
                }
                res.append(val.get(val.size() - 1));
            }
            res.append("]");
            return s(name) + res;
        }
        static String s(String name, List<String> val) {
            if (val == null) return sNull(name);
            StringBuilder res = new StringBuilder("[");
            if (val.size() != 0) {
                for (int i = 0; i < val.size() - 1; ++i) {
                    res.append(escaped(val.get(i)));
                    res.append(",");
                }
                res.append(escaped(val.get(val.size() - 1)));
            }
            res.append("]");
            return s(name) + res;
        }
        @Override
        public String toString() {
            //public final String sender;
            //public final Manager m;
            //public final Optional<SignalServiceDataMessage> message;
            //public final Optional<SignalServiceSyncMessage> syncMessage;
            return "{" + s("envelope") + "{"+
                    s("isFull", true) + "," +
                    //s("isReceipt", false) + "," +
                    s("sender", sender) + "," +
                    s("message", content.getDataMessage().orNull()) + "," +
                    s("receiptMessage", content.getReceiptMessage().orNull()) + "," +
                    s("callMessage", content.getCallMessage().orNull()) +","+
                    s("typingMessage", content.getTypingMessage().orNull()) +","+
                    s("syncMessage", content.getSyncMessage().orNull()) + //"," +
                    "}}";
        }
    }

    /*
    class MessageReceived {

        private final long timestamp;
        private final String sender;
        private final byte[] groupId;
        private final String message;
        private final List<String> attachments;

        public MessageReceived(String objectpath, long timestamp, String sender,
                               byte[] groupId, String message, List<String> attachments)/
                               * throws DBusException * /{
     *
//            super(objectpath, timestamp, sender, groupId, message, attachments);
            thiss.timestamp = timestamp;
            this.sender = sender;
            this.groupId = groupId;
            this.message = message;
            this.attachments = attachments;
        }

        public long getTimestamp() {
            return timestamp;
        }

        public String getSender() {
            return sender;
        }

        public byte[] getGroupId() {
            return groupId;
        }

        public String getMessage() {
            return message;
        }

        public List<String> getAttachments() {
            return attachments;
        }
    }

    class ReceiptReceived {

        private final long timestamp;
        private final String sender;

        public ReceiptReceived(String objectpath, long timestamp, String sender) /*throws DBusException * /{
//            super(objectpath, timestamp, sender);
            this.timestamp = timestamp;
            this.sender = sender;
        }

        public long getTimestamp() {
            return timestamp;
        }

        public String getSender() {
            return sender;
        }
    }

    class SyncMessageReceived {

        private final long timestamp;
        private final String source;
        private final String destination;
        private final byte[] groupId;
        private final String message;
        private final List<String> attachments;

        public SyncMessageReceived(String objectpath, long timestamp, String source,
                                   String destination, byte[] groupId, String message,
                                   List<String> attachments) /*throws DBusException * /{
//            super(objectpath, timestamp, source, destination, groupId, message, attachments);
            this.timestamp = timestamp;
            this.source = source;
            this.destination = destination;
            this.groupId = groupId;
            this.message = message;
            this.attachments = attachments;
        }

        public long getTimestamp() {
            return timestamp;
        }

        public String getSource() {
            return source;
        }

        public String getDestination() {
            return destination;
        }

        public byte[] getGroupId() {
            return groupId;
        }

        public String getMessage() {
            return message;
        }

        public List<String> getAttachments() {
            return attachments;
        }
    }*/
}
