/*
  Copyright (C) 2015-2020 AsamK and contributors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
package org.asamk.signal;

import org.asamk.Error;
import org.asamk.signal.manager.*;
import org.asamk.signal.util.IOUtils;
import org.asamk.signal.util.SecurityProvider;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.jetbrains.annotations.NotNull;
import org.whispersystems.signalservice.api.SignalServiceMessageSender;
import org.whispersystems.signalservice.api.crypto.UntrustedIdentityException;
import org.whispersystems.signalservice.api.messages.SignalServiceAttachment;
import org.whispersystems.signalservice.api.messages.SignalServiceDataMessage;
import org.whispersystems.signalservice.api.messages.SignalServiceGroup;
import org.whispersystems.signalservice.api.push.SignalServiceAddress;
import org.whispersystems.signalservice.api.push.exceptions.AuthorizationFailedException;
import org.whispersystems.signalservice.api.push.exceptions.EncapsulatedExceptions;
import org.whispersystems.signalservice.api.push.exceptions.NetworkFailureException;
import org.whispersystems.signalservice.api.push.exceptions.UnregisteredUserException;
import org.whispersystems.signalservice.api.util.InvalidNumberException;
import org.whispersystems.signalservice.internal.configuration.SignalServiceConfiguration;

import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.security.InvalidKeyException;
import java.security.Security;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Scanner;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import static org.asamk.signal.util.ErrorUtils.handleAssertionError;

class Misc {
    public static Exception convertEncapsulatedExceptions(EncapsulatedExceptions e) {
        if (e.getNetworkExceptions().size() + e.getUnregisteredUserExceptions().size() + e.getUntrustedIdentityExceptions().size() == 1) {
            if (e.getNetworkExceptions().size() == 1) {
                NetworkFailureException n = e.getNetworkExceptions().get(0);
                return new Error.Failure("Network failure for \"" + n.getE164number() + "\": " + n.getMessage());
            } else if (e.getUnregisteredUserExceptions().size() == 1) {
                UnregisteredUserException n = e.getUnregisteredUserExceptions().get(0);
                return new Error.UnregisteredUser("Unregistered user \"" + n.getE164Number() + "\": " + n.getMessage());
            } else if (e.getUntrustedIdentityExceptions().size() == 1) {
                UntrustedIdentityException n = e.getUntrustedIdentityExceptions().get(0);
                return new Error.UntrustedIdentity("Untrusted Identity for \"" + n.getIdentifier() + "\": " + n.getMessage());
            }
        }

        StringBuilder message = new StringBuilder();
        message.append("Failed to send (some) messages:").append('\n');
        for (NetworkFailureException n : e.getNetworkExceptions()) {
            message.append("Network failure for \"").append(n.getE164number()).append("\": ").append(n.getMessage()).append('\n');
        }
        for (UnregisteredUserException n : e.getUnregisteredUserExceptions()) {
            message.append("Unregistered user \"").append(n.getE164Number()).append("\": ").append(n.getMessage()).append('\n');
        }
        for (UntrustedIdentityException n : e.getUntrustedIdentityExceptions()) {
            message.append("Untrusted Identity for \"").append(n.getIdentifier()).append("\": ").append(n.getMessage()).append('\n');
        }

        return new Error.Failure(message.toString());
    }
}

@SuppressWarnings("unused")
class ResultLong {
    long res;
    String error;
    boolean success;
    ResultLong(long res, String error, boolean success) {
        this.res = res;
        this.error = error;
        this.success = success;
    }
    ResultLong(Throwable err) {
        if (err == null) {
            this.error = "NÜLL ERROR!";
        } else {
            this.error = err.getMessage();
        }
        this.success = false;
    }
    ResultLong(long res) {
        this.res = res;
        this.success = true;
    }
    static ResultLong makeError(String s) { return new ResultLong(0, s, false); }

    public long getRes() { return res; }
    public boolean isSuccess() { return success; }
    public String getError() { return error; }
}

@SuppressWarnings("unused")
class NativeThread extends Thread {
    static /*final*/ Manager m;
    static NativeThread instance_ = null;
    public static NativeThread instance() { return instance_; }

    static SignalServiceDataMessage.Quote mkQuote(long id, String authorNum, @NotNull String text)
            throws InvalidNumberException {
        //if (text.equals("")) text = null;
        SignalServiceAddress qauthor = m.canonicalizeAndResolveSignalServiceAddress(authorNum);
        List<SignalServiceDataMessage.Quote.QuotedAttachment> qattachments = new ArrayList<>();
        return new SignalServiceDataMessage.Quote(id, qauthor, text, qattachments);
    }
    static SignalServiceDataMessage.Builder mkBuilder(String messageText, String[] attachments,
                                               boolean uploadAtt,
                                               SignalServiceDataMessage.Quote quote)//quote may be null
            throws IOException, AttachmentInvalidException {
        final SignalServiceDataMessage.Builder messageBuilder =
                SignalServiceDataMessage.newBuilder().withBody(messageText);
        if (attachments != null) {
            if (uploadAtt) {
                List<SignalServiceAttachment> attachmentStreams =
                        Utils.getSignalServiceAttachments(attachments);
                // Upload attachments here, so we only upload once even for multiple recipients
                SignalServiceMessageSender messageSender = m.getMessageSender();
                List<SignalServiceAttachment> attachmentPointers = new ArrayList<>(attachmentStreams.size());
                for (SignalServiceAttachment attachment : attachmentStreams) {
                    if (attachment.isStream()) {
                        attachmentPointers.add(messageSender.uploadAttachment(attachment.asStream()));
                    } else if (attachment.isPointer()) {
                        attachmentPointers.add(attachment.asPointer());
                    }
                }

                messageBuilder.withAttachments(attachmentPointers);
            } else {
                messageBuilder.withAttachments(Utils.getSignalServiceAttachments(attachments));
            }
        }
        if (quote != null)
            messageBuilder.withQuote(quote);
        return messageBuilder;
    }
    static ResultLong sendMessageNice(String messageText, String[] attachments, String recipient,
                               SignalServiceDataMessage.Quote quote) {//quote may be null
        try {
            var messageBuilder = mkBuilder(messageText, attachments, true, quote);
            var res = m.sendMessageLegacy(messageBuilder,
                    m.getSignalServiceAddresses(m.mkRecipients(recipient)));
            return new ResultLong(res);
        } catch (EncapsulatedExceptions e) {
            return new ResultLong(Misc.convertEncapsulatedExceptions(e));
        } catch (Throwable e) {
            return new ResultLong(e);
        }
    }

    public NativeThread(final Manager m) {
        NativeThread.m = m;
        instance_ = this;
    }

    public native void onStart();
    public native void loopImpl();
    public native void onStop();

    static void stopLoop() {
        //System.out.println("SHTAP!");
        instance().interrupt();
        instance().onStop();
        System.exit(0);
    }

    @Override
    public void run() {
        onStart();
        while (!interrupted()) {
            loopImpl();
        }
        m.running = false;
        //System.out.println("KONIEC");
    }

    public static ResultLong sendMessage(String message, String[] attachments, String destination) {
        return sendMessageNice(message, attachments, destination, null);
    }

    public static ResultLong sendMessageWithQuote(
            String message, String[] attachments, String destination,
            long qid, String qauthorNum, String qtext) {
        //var m = instance().m;

        try {
            return sendMessageNice(
                        message, attachments, destination, mkQuote(qid, qauthorNum, qtext));
        } catch (InvalidNumberException e) {
            return new ResultLong(e);
        }
    }
    public static ResultLong sendGroupMessage(String message, String[] attachments, byte[] groupId) {
        try {
            return new ResultLong(m.sendGroupMessage(message, attachments, groupId));
        } catch (EncapsulatedExceptions e) {
            return new ResultLong(Misc.convertEncapsulatedExceptions(e));
        } catch (Throwable e) {
            return new ResultLong(e);
        }
    }

    public static ResultLong sendGroupMessageWithQuote(
            String message, String[] attachments, byte[] groupId,
            long qid, String qauthorNum, String qtext) {
        try {
            final SignalServiceDataMessage.Builder messageBuilder =
                    SignalServiceDataMessage.newBuilder().
                    withBody(message);
            if (attachments != null) {
                messageBuilder.withAttachments(Utils.getSignalServiceAttachments(attachments));
            }
            if (groupId != null) {
                SignalServiceGroup group = SignalServiceGroup.newBuilder(SignalServiceGroup.Type.DELIVER)
                        .withId(groupId)
                        .build();
                messageBuilder.asGroupMessage(group);
            }

            final var g = m.getGroupForSending(groupId);

            messageBuilder.withExpiration(g.messageExpirationTime);
            messageBuilder.withQuote(mkQuote(qid, qauthorNum, qtext));
            return new ResultLong(
                    m.sendMessageLegacy(messageBuilder, g.getMembersWithout(m.account.getSelfAddress())));
            //TODO - this doesn't work
            /*
            var messageBuilder = i.mkBuilder(message, attachments, false,
                    i.mkQuote(qid, qauthorNum, qtext));

            return new ResultLong(i.m.sendMessageLegacy(messageBuilder, i.m.mkGroup(groupId)));*/
        } catch (EncapsulatedExceptions e) {
            return new ResultLong(Misc.convertEncapsulatedExceptions(e));
        } catch (Throwable e) {
            return new ResultLong(e);
        }
    }

    //we don't really return anything on success but i don't want to add a new class to jni
    public static ResultLong sendGroupMessageReaction(String emoji, boolean remove, String targetAuthor,
                                               long targetSentTimestamp, byte[] groupId) {
        try {
            return new ResultLong(m.sendGroupMessageReaction(emoji, remove,
                    targetAuthor, targetSentTimestamp, groupId));
        } catch (EncapsulatedExceptions e) {
            return new ResultLong(Misc.convertEncapsulatedExceptions(e));
        } catch (Throwable e) {
            return new ResultLong(e);
        }
    }
    public static ResultLong sendMessageReaction(String emoji, boolean remove, String targetAuthor,
                                          long targetSentTimestamp, String destination) {
        try {
            return new ResultLong(m.sendMessageReaction(emoji, remove, targetAuthor,
                       targetSentTimestamp,destination));
        } catch (EncapsulatedExceptions e) {
            return new ResultLong(Misc.convertEncapsulatedExceptions(e));
        } catch (Throwable e) {
            return new ResultLong(e);
        }
    }


    public static ResultLong requestSyncAll() {
        try {
            m.refreshPreKeys();

            m.requestSyncGroups();
            m.requestSyncContacts();
            m.requestSyncBlocked();
            m.requestSyncConfiguration();

            m.saveAccount();
            return new ResultLong(0);
        } catch (IOException e) {
            return new ResultLong(e);
        }
    }
//    void requestSyncGroups() throws IOException;
//    void requestSyncContacts() throws IOException;
//    void requestSyncBlocked() throws IOException;
//    void requestSyncConfiguration() throws IOException;
    /*
    *
                                    *
    public void setContactName(String number, String name) throws InvalidNumberException;
    // Change the expiration timer for a contact
    public void setExpirationTimer(String number, int messageExpirationTimer) throws IOException, InvalidNumberException {
    //Change the expiration timer for a group
    public void setExpirationTimer(byte[] groupId, int messageExpirationTimer);

     * //Upload the sticker pack from path.
     *
     * //@param path Path can be a path to a manifest.json file or to a zip file that contains a manifest.json file
    //@return if successful, returns the URL to install the sticker pack in the signal app
    public String uploadStickerPack(String path) throws IOException, StickerPackInvalidException;
    *
    * */
}

@SuppressWarnings("unused")
public class Main {

//    public static void init(String user){}
//    public static void onSigint(){}
//    public static void onMessageReceived(String json){}
//    public static void log(String val){}

    public static native void init(String user);
    public static native void onSigint();
    public static native void onMessageReceived(String json);
    public static native void log(String val);
    public static native void err(String val);

    static {
        System.loadLibrary("sclid");
        //var a = System.getProperty("user.dir");

        //System.load(a+"/libsclid.so");
    }

    static String[] tryFindArgs() {
        File f = new File(IOUtils.getDataHomeDir() + "/signal-cli/data");
        var l = f.list();
        if (l == null) return null;
        String[] res = Arrays.stream(l).filter((x)->!x.endsWith(".d")&& x.startsWith("+")).toArray(String[]::new);
        if (res.length != 1) return null;
        return res;
    }
    public static void main(String[] args) {
        Runtime.getRuntime().addShutdownHook(new Thread(Main::onSigint));
        if (args.length == 0) {
            args = tryFindArgs();
        }

        if (args == null || args.length != 1) {
            System.err.println("just give the username");
            return;
        }
        System.out.println("Please wait for a few seconds.");
        init(args[0]);
        installSecurityProviderWorkaround();

        int res = quickHandleCommands(args[0]);
        System.exit(res);
    }

    public static int quickHandleCommands(final Manager m) {
//        System.out.println(String.format("4 manager COMMANDS? %s",  new Date().getTime()));
        //DBusConnection conn = null;
        NativeThread t = new NativeThread(m);
        try {
            t.start();

            try {
                m.receiveMessages(1, TimeUnit.HOURS, false, false,
                            new JsonDbusReceiveMessageHandler(m));

//                System.out.println("</receive>");
                return 0;
            } catch (IOException e) {
                System.err.println("Error while receiving messages: " + e.getMessage());
                return 3;
            } catch (AssertionError e) {
                handleAssertionError(e);
                return 1;
            }
        } finally {
//            System.out.println("Interrupt");
            //t.stopLoop();
            NativeThread.stopLoop();

            //if (conn != null) {
            //    conn.disconnect();
            //}
        }
    }
    // I ain't doin' any of that in java
    public static native void generateQR(String code);
    public static native void stopGenerate();

    private static int link(ProvisioningManager m) {
        String host = "a linux box, idk, can't get the hostname";
        try {
            var v = InetAddress.getLocalHost().getHostName();
            if (v != null && !v.isEmpty())
                host = v;
        } catch (IOException e) {
            System.err.println("`hostname` failed");
        }
        final String deviceName = "sclid on "+host;

        try {
            var linkUri = m.getDeviceLinkUri();

            var t = new Thread(() -> generateQR(linkUri));
            t.start();
            //log(deviceName);
            String username = m.finishDeviceLink(deviceName);
            System.out.println("Associated with: " + username);
            t.interrupt();
            stopGenerate();
        } catch (TimeoutException e) {
            System.err.println("Link request timed out, please try again.");
            return 3;
        } catch (IOException e) {
            System.err.println("Link request error: " + e.getMessage());
            return 3;
        } catch (AssertionError e) {
            handleAssertionError(e);
            return 1;
        } catch (UserAlreadyExists e) {
            System.err.println("The user " + e.getUsername() + " already exists\nDelete \"" +
                    e.getFileName() + "\" before trying again.");
            return 1;
        } catch (org.whispersystems.libsignal.InvalidKeyException e) {
            e.printStackTrace();
            return 2;
        }
        return 0;
    }

    private static int quickHandleCommands(String username) {
        String dataPath = IOUtils.getDataHomeDir() + "/signal-cli";
        String dataFile = dataPath+"/data/"+username;
        //log(String.format("datapath: '%s'", dataPath));
        //var f = new File(dataPath);
        //log(String.format("\\exists = %s",f.exists()));
        if (!(new File(dataFile).exists())) {
            System.out.print(
                    String.format("Config file for '%s' doesn't exist. Do you want to create one? (y/n): ",
                            username));
            //todo

            //sigh
            var val = (new Scanner(System.in)).nextLine().trim();

            if (!val.startsWith("y")) {
                System.out.println("User declined. Exiting.");
                return 0;
            }
            final SignalServiceConfiguration serviceConfiguration =
                    ServiceConfig.createDefaultServiceConfiguration(BaseConfig.USER_AGENT);
            ProvisioningManager pm = new ProvisioningManager(dataPath, serviceConfiguration,
                    BaseConfig.USER_AGENT);
            var res = link(pm);
            if (res != 0) return res;;
        }
        //String dataPath = getDefaultDataPath();

        final SignalServiceConfiguration serviceConfiguration =
                ServiceConfig.createDefaultServiceConfiguration(BaseConfig.USER_AGENT);

        Manager manager;
        try {
            manager = Manager.init(username, dataPath, serviceConfiguration, BaseConfig.USER_AGENT);
        } catch (Throwable e) {
            System.err.println("Error loading state file: " + e.getMessage());
            return 2;
        }

        try (Manager m = manager) {
            try {
                m.checkAccountState();
            } catch (AuthorizationFailedException e) {
                // Register command should still be possible, if current authorization fails
                System.err.println("Authorization failed, was the number registered elsewhere?");
                return 2;
            } catch (IOException e) {
                System.err.println("Error while checking account: " + e.getMessage());
                return 2;
            }

            return quickHandleCommands(m);
        } catch (IOException e) {
            e.printStackTrace();
            return 3;
        }
    }

    public static void installSecurityProviderWorkaround() {
        // Register our own security provider
        Security.insertProviderAt(new SecurityProvider(), 1);
        Security.addProvider(new BouncyCastleProvider());
    }
    /*
     * Uses $XDG_DATA_HOME/signal-cli if it exists, or if none of the legacy directories exist:
     * - $HOME/.config/signal
     * - $HOME/.config/textsecure
     *
     * @return the data directory to be used by signal-cli.
     *
    private static String getDefaultDataPath() {
        String dataPath = IOUtils.getDataHomeDir() + "/signal-cli";
        if (new File(dataPath).exists()) {
            return dataPath;
        }

        String legacySettingsPath = System.getProperty("user.home") + "/.config/signal";
        if (new File(legacySettingsPath).exists()) {
            return legacySettingsPath;
        }

        legacySettingsPath = System.getProperty("user.home") + "/.config/textsecure";
        if (new File(legacySettingsPath).exists()) {
            return legacySettingsPath;
        }

        return dataPath;
    }*/
}
