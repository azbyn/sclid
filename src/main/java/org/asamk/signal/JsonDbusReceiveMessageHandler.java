package org.asamk.signal;

import org.asamk.Signal;
import org.asamk.signal.manager.Manager;
import org.whispersystems.signalservice.api.messages.SignalServiceAttachment;
import org.whispersystems.signalservice.api.messages.SignalServiceContent;
import org.whispersystems.signalservice.api.messages.SignalServiceDataMessage;
import org.whispersystems.signalservice.api.messages.SignalServiceEnvelope;

import java.util.ArrayList;
import java.util.List;

public class JsonDbusReceiveMessageHandler implements Manager.ReceiveMessageHandler
        /*extends JsonReceiveMessageHandler*/ {
    final Manager m;

    //private final DBusConnection conn;

//    private final String objectPath;

    public JsonDbusReceiveMessageHandler(Manager m/*, final String objectPath*/) {
        this.m = m;
        //super(m);
        //this.conn = conn;
//        this.objectPath = objectPath;
    }

    /*static void sendReceivedMessageToDbus(SignalServiceEnvelope envelope, SignalServiceContent content,
                                          /*DBusConnection conn, final String objectPath,* / Manager m) {
        /*
        if (envelope.isReceipt()) {
            try {
                conn.sendMessage(new Signal.ReceiptReceived(
                        objectPath,
                        envelope.getTimestamp(),
                        !envelope.isUnidentifiedSender() && envelope.hasSource() ? envelope.getSourceE164().get() : content.getSender().getNumber().get()
                ));
            } catch (DBusException e) {
                e.printStackTrace();
            }
        } else * /
//        System.out.println("RECEIVE MESSAGE DBUS");

    }*/

    static public List<String> getAttachments(SignalServiceDataMessage message, Manager m) {
        List<String> attachments = new ArrayList<>();
        if (message.getAttachments().isPresent()) {
            for (SignalServiceAttachment attachment : message.getAttachments().get()) {
                if (attachment.isPointer()) {
//                    Main.log(String.format("the filename '%s'",
//                            attachment.asPointer().getFileName().or("")));
                    attachments.add(m.getAttachmentFile(attachment.asPointer())
                            .getAbsolutePath());
                }
            }
        }
        return attachments;
    }

    @Override
    public void handleMessage(SignalServiceEnvelope envelope, SignalServiceContent content,
                              Throwable exception) {
//        super.handleMessage(envelope, content, exception);
//        System.out.println("FULLLLLLLL AHA");
        if (content != null) {
            String sender = envelope.isUnidentifiedSender() || !envelope.hasSource()
                    ? content.getSender().getNumber().get()
                    : envelope.getSourceE164().get();
            var fm = new Signal.FullMessage(
                    content,
                    sender,
                    m
            );
//            System.out.println("FULLLLLLLL MESSAGE");
            Main.onMessageReceived(fm.toString());
        }
        //sendReceivedMessageToDbus(envelope, content, m);
    }
}
