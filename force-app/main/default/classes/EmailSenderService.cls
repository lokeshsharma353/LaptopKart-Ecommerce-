/** Applies the sender used for outgoing storefront email. */
public without sharing class EmailSenderService {

    // Only used as a display/reply-to address in email BODY text (e.g. "contact
    // us at support.laptopkart@gmail.com") — no longer set as the actual
    // envelope sender. See applySupportSender's own comment for why.
    public static final String SUPPORT_EMAIL = 'support.laptopkart@gmail.com';

    /**
     * Deliberately a no-op now. This used to call
     * message.setOrgWideEmailAddressId(...) to force every send through a
     * verified Org-Wide Email Address backed by a Gmail mailbox
     * (support.laptopkart@gmail.com) — that address reliably reported
     * successful acceptance while never actually reaching real inboxes
     * (confirmed by comparing against an early, genuinely-delivered order
     * email whose sender was Salesforce's own auto-generated
     * *.sfcustomeremail.com address, not the Gmail OWA). Leaving this method
     * as a no-op means every Messaging.SingleEmailMessage falls back to that
     * default Salesforce sender — which Salesforce authenticates (SPF/DKIM)
     * on its own domain, no OWA/DNS setup required — restoring the delivery
     * behavior from earlier in this project. Kept as a method (rather than
     * deleting every call site) so every email-sending class still compiles
     * unchanged and a real verified custom sender can be re-applied here in
     * one place later if one is ever properly domain-authenticated.
     */
    public static void applySupportSender(Messaging.SingleEmailMessage message) {
        // Intentionally does nothing — see comment above.
    }

    // Every transactional email send in this storefront (welcome, order
    // confirmation, payment confirmation, password reset) is wrapped in its
    // own try/catch so a mail hiccup can never block the actual checkout/
    // signup/reset flow — but until now that catch only wrote a debug line,
    // so a real failure (most likely this Developer Edition org's daily
    // external email cap being hit) was invisible to everyone, including the
    // admin. This creates a Task instead, so a failed send is at least
    // visible and followable-up-on rather than silently vanishing.
    public static void logEmailFailure(String emailType, String recipientEmail, String errorMessage) {
        try {
            Task failureTask = new Task();
            failureTask.Subject = 'Email failed to send: ' + emailType;
            failureTask.Description =
                'Recipient: ' + (String.isBlank(recipientEmail) ? '(unknown)' : recipientEmail) + '\n' +
                'Error: ' + errorMessage + '\n\n' +
                'This is usually this Developer Edition org\'s daily external email limit being ' +
                'reached (Setup > Email Administration, or System Overview for today\'s send count) ' +
                '— it resets at midnight. If the recipient genuinely needs this email, resend it manually.';
            failureTask.Status = 'Not Started';
            failureTask.Priority = 'High';
            failureTask.ActivityDate = Date.today();
            failureTask.OwnerId = getDefaultOwnerId();
            Database.insert(failureTask, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not even log the email failure as a Task: ' + e.getMessage());
        }
    }

    private static Id getDefaultOwnerId() {
        List<User> namedAdmin = [
            SELECT Id FROM User WHERE Username = 'lokesh@codleo.org' AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!namedAdmin.isEmpty()) {
            return namedAdmin[0].Id;
        }
        List<User> anyAdmin = [
            SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return anyAdmin.isEmpty() ? UserInfo.getUserId() : anyAdmin[0].Id;
    }
}
