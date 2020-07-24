package org.asamk;

public interface Error {

    class AttachmentInvalid extends Exception {

        public AttachmentInvalid(final String message) {
            super(message);
        }
    }

    class Failure extends Exception {

        public Failure(final String message) {
            super(message);
        }
    }

    class GroupNotFound extends Exception {

        public GroupNotFound(final String message) {
            super(message);
        }
    }

    class InvalidNumber extends Exception {

        public InvalidNumber(final String message) {
            super(message);
        }
    }

    class UnregisteredUser extends Exception {

        public UnregisteredUser(final String message) {
            super(message);
        }
    }

    class UntrustedIdentity extends Exception {

        public UntrustedIdentity(final String message) {
            super(message);
        }
    }
}
