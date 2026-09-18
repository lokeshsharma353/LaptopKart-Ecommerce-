// without sharing + SYSTEM_MODE: same reasoning as CheckoutController — this
// runs as the Site Guest User with no record access of its own.
public without sharing class WelcomeLeadController {

    private static final String ADMIN_EMAIL = EmailSenderService.SUPPORT_EMAIL;
    private static final String DEFAULT_OWNER_USERNAME = 'lokesh@codleo.org';

    // Creates a marketing Lead from the homepage welcome popup and notifies
    // the admin. Deliberately a separate, lighter-weight path from
    // CheckoutController's Lead — this is a top-of-funnel "just browsing,
    // here's my email" capture, not a completed order, so it stays a plain
    // Lead rather than being converted to a Contact/Opportunity.
    @AuraEnabled
    public static void submitWelcomeLead(String name, String email, String laptopType) {

        if (String.isBlank(name) || String.isBlank(email)) {
            throw new AuraHandledException('Please enter your name and email.');
        }

        Id defaultOwnerId = getDefaultOwnerId();

        Lead newLead = new Lead();
        newLead.LastName = name;
        newLead.Company = name + ' (Website Lead)';
        newLead.Email = email;
        newLead.LeadSource = 'Website Welcome Popup';
        newLead.Status = 'Open - Not Contacted';
        // Required picklist on Lead in this org — see CheckoutController for
        // the same default; a retail/marketing lead doesn't map cleanly to
        // IT/HR/Finance/etc.
        newLead.Department__c = 'Sales';
        if (String.isNotBlank(laptopType)) {
            newLead.Description = 'Interested in: ' + laptopType;
        }
        // Owned by the running Guest User first so the insert itself is
        // never blocked by the Guest cross-reference restriction (see
        // CheckoutController), then reassigned to the admin below so it's
        // visible in their own list views immediately.
        newLead.OwnerId = UserInfo.getUserId();

        Database.DMLOptions dmo = new Database.DMLOptions();
        dmo.DuplicateRuleHeader.AllowSave = true;

        try {
            Database.insert(newLead, dmo, AccessLevel.SYSTEM_MODE);
            Database.update(
                new Lead(Id = newLead.Id, OwnerId = defaultOwnerId),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            throw new AuraHandledException('Could not save your details. Please try again.');
        }

        sendAdminNotification(name, email, laptopType);
    }

    /** Best-effort email to the admin summarizing the new welcome-popup Lead; failures are swallowed so they never block the Lead save. */
    private static void sendAdminNotification(String name, String email, String laptopType) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { ADMIN_EMAIL });
            mail.setSenderDisplayName('LaptopKart Welcome Form');
            mail.setSubject('New website lead: ' + name);
            mail.setPlainTextBody(
                'A new visitor filled out the LaptopKart welcome form.\n\n' +
                'Name: ' + name + '\n' +
                'Email: ' + email + '\n' +
                'Looking for: ' + (String.isBlank(laptopType) ? 'Not specified' : laptopType)
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Welcome lead admin email failed: ' + e.getMessage());
        }
    }

    /** Looks up the admin User this Lead gets reassigned to (by username, else any System Administrator, else the running user). */
    private static Id getDefaultOwnerId() {
        List<User> namedAdmin = [
            SELECT Id FROM User
            WHERE Username = :DEFAULT_OWNER_USERNAME AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!namedAdmin.isEmpty()) {
            return namedAdmin[0].Id;
        }
        List<User> anyAdmin = [
            SELECT Id FROM User
            WHERE Profile.Name = 'System Administrator' AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return anyAdmin.isEmpty() ? UserInfo.getUserId() : anyAdmin[0].Id;
    }
}
