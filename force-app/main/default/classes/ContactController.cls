// without sharing: a Guest visitor filling out the Contact Us form has no
// record access of their own — sending the notification email needs no
// sharing/CRUD context at all, so this mirrors CheckoutController's pattern.
public without sharing class ContactController {

    // The site's admin inbox — same address CheckoutController resolves via
    // DEFAULT_OWNER_USERNAME, hardcoded directly here since this doesn't need
    // to look up an actual User record (Salesforce login), just an inbox.
    private static final String ADMIN_EMAIL = 'lokesh@codleo.org';

    @AuraEnabled
    public static void submitMessage(String name, String email, String phone, String subject, String message) {

        if (String.isBlank(name) || String.isBlank(email) ||
            String.isBlank(subject) || String.isBlank(message)) {
            throw new AuraHandledException('Please fill in all fields.');
        }

        // The record in Contact_Us__c is the real, permanent copy of this
        // submission (visible/manageable by the admin in Setup regardless of
        // whether the notification email below ever arrives) — so this insert
        // is the one part of this method that must actually throw on failure,
        // unlike the best-effort email notification.
        Contact_Us__c ticket = new Contact_Us__c();
        ticket.Name__c = name;
        ticket.Email__c = email;
        ticket.Phone__c = phone;
        ticket.Subject__c = subject;
        ticket.Message__c = message;
        ticket.Status__c = 'New';
        ticket.Low_Medium_High_Urgent__c = 'Medium';
        ticket.Created_Date__c = Date.today();

        try {
            // AccessLevel.SYSTEM_MODE — a Guest visitor filling out this form
            // has no object permissions of their own on Contact_Us__c, same
            // reasoning as every other Guest-facing DML in this app
            // (Login_Credentials__c, the checkout pipeline, etc.).
            Database.insert(ticket, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('Could not send your message. Please try again later.');
        }

        // Best-effort admin notification email — isolated in its own
        // try/catch so a deliverability hiccup never hides the fact that the
        // message was actually saved above.
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { ADMIN_EMAIL });
            // Lets the admin just hit Reply in their email client to answer
            // the customer directly, without needing to copy the address.
            mail.setReplyTo(email);
            mail.setSenderDisplayName('LaptopKart Contact Form');
            mail.setSubject('[LaptopKart Contact] ' + subject);
            mail.setPlainTextBody(
                'New message from the LaptopKart Contact Us form:\n\n' +
                'Name: ' + name + '\n' +
                'Email: ' + email + '\n' +
                'Phone: ' + (String.isBlank(phone) ? '(not provided)' : phone) + '\n' +
                'Subject: ' + subject + '\n\n' +
                'Message:\n' + message
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Contact Us notification email failed: ' + e.getMessage());
        }
    }
}
