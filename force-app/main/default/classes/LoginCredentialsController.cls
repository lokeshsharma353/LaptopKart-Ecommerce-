// without sharing: a not-yet-authenticated site guest has no record access of
// their own before signing up or logging in, so checking for an existing
// email and reading/writing Login_Credentials__c must run in system context —
// same reasoning used throughout this storefront's Guest-User-facing
// controllers (CheckoutController, RegistrationController, etc.).
//
// This is a lightweight, custom login system built on Login_Credentials__c —
// NOT real Salesforce authentication (no Salesforce User is created, no real
// session/identity is established). "Being logged in" is tracked client-side
// by the LWC (authService) after a successful call here.
//
// Password_Text__c stores the password in plain text (by explicit request,
// so admins can view/look up a shopper's password directly on the record in
// Setup) — this is NOT the secure approach (a hash would be unrecoverable
// even to admins) and means anyone with read access to this object, or a
// data export/backup, can see every shopper's raw password.
public without sharing class LoginCredentialsController {

    private static final Integer MIN_PASSWORD_LENGTH = 8;

    // Takes four plain String parameters rather than a wrapper class —
    // this LWR site's webruntime/api/apex/execute RPC layer was found (via
    // a live diagnostic build) to deliver every field of a nested custom
    // Apex class parameter as null, even though the client genuinely sent
    // real values; flat primitive parameters deserialize correctly (as
    // proven by logIn below, which never had this problem), so this method
    // avoids the wrapper entirely instead of fighting the RPC layer.
    @AuraEnabled
    public static AccountSession signUp(String name, String email, String phone, String password) {
        if (
            String.isBlank(name) ||
            String.isBlank(email) ||
            String.isBlank(phone) ||
            String.isBlank(password)
        ) {
            throw new AuraHandledException('Please fill in all fields.');
        }

        if (!Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', email.trim())) {
            throw new AuraHandledException('Please enter a valid email address.');
        }

        if (password.length() < MIN_PASSWORD_LENGTH) {
            throw new AuraHandledException('Password must be at least ' + MIN_PASSWORD_LENGTH + ' characters.');
        }

        String normalizedEmail = email.trim().toLowerCase();

        List<Login_Credentials__c> existing = [
            SELECT Id
            FROM Login_Credentials__c
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            throw new AuraHandledException('An account with this email already exists. Please log in instead.');
        }

        Login_Credentials__c cred = new Login_Credentials__c();
        cred.Name__c = name.trim();
        cred.Email__c = normalizedEmail;
        cred.Phone__c = phone.trim();
        cred.Password_Text__c = password;

        Database.insert(cred, AccessLevel.SYSTEM_MODE);

        AccountSession session = new AccountSession();
        session.id = cred.Id;
        session.name = cred.Name__c;
        session.email = cred.Email__c;
        session.phone = cred.Phone__c;
        return session;
    }

    /** Verifies email + password against Login_Credentials__c (case-insensitive email, case-sensitive password) and returns the account session, or throws a generic error for either a wrong password or an unknown email. */
    @AuraEnabled
    public static AccountSession logIn(String email, String password) {
        if (String.isBlank(email) || String.isBlank(password)) {
            throw new AuraHandledException('Please enter your email and password.');
        }

        String normalizedEmail = email.trim().toLowerCase();

        List<Login_Credentials__c> matches = [
            SELECT Id, Name__c, Email__c, Phone__c, Password_Text__c
            FROM Login_Credentials__c
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        // Same generic message whether the email doesn't exist or the
        // password is wrong — never reveals which emails are registered.
        // Password comparison uses String.equals() deliberately, NOT != —
        // Apex's == / != operators compare strings case-INsensitively by
        // default, which would silently accept a wrong-case password.
        if (matches.isEmpty() || !matches[0].Password_Text__c.equals(password)) {
            throw new AuraHandledException('Invalid email or password.');
        }

        Login_Credentials__c cred = matches[0];
        AccountSession session = new AccountSession();
        session.id = cred.Id;
        session.name = cred.Name__c;
        session.email = cred.Email__c;
        session.phone = cred.Phone__c;
        return session;
    }

    // There's no real password-reset mechanism here (no email-a-reset-link
    // flow — this isn't real Salesforce authentication, see the class
    // header). Instead, a shopper who forgot their password submits their
    // email/phone/a short message, and this simply creates a Task for an
    // admin to follow up with them directly (look up their password in
    // Password_Text__c and tell them, or help however makes sense). Never
    // reveals whether the email matches a real account — that's recorded in
    // the Task's Description for the admin to see, not surfaced to the
    // shopper, same reasoning as logIn's generic error message.
    @AuraEnabled
    public static void requestPasswordReset(String email, String phone, String message) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Please enter the email on your account.');
        }
        if (!Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', email.trim())) {
            throw new AuraHandledException('Please enter a valid email address.');
        }

        String normalizedEmail = email.trim().toLowerCase();

        List<Login_Credentials__c> matches = [
            SELECT Id, Name__c
            FROM Login_Credentials__c
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Boolean accountFound = !matches.isEmpty();

        Task reminderTask = new Task();
        reminderTask.Subject = 'Password Reset Request - ' + normalizedEmail;
        reminderTask.Description =
            'A shopper requested help recovering their LaptopKart account password.\n\n' +
            'Email: ' + normalizedEmail + '\n' +
            'Phone: ' + (String.isBlank(phone) ? '(not provided)' : phone.trim()) + '\n' +
            'Matching account found: ' + (accountFound ? 'Yes' : 'No') + '\n' +
            (accountFound ? 'Account Name on file: ' + matches[0].Name__c + '\n' : '') +
            '\nMessage from shopper:\n' + (String.isBlank(message) ? '(none provided)' : message.trim());
        reminderTask.Status = 'Not Started';
        reminderTask.Priority = 'High';
        reminderTask.ActivityDate = Date.today();
        reminderTask.OwnerId = getDefaultOwnerId();

        Database.insert(reminderTask, AccessLevel.SYSTEM_MODE);
    }

    // Mirrors the shopper's live cart (see cartService.js) onto their
    // Login_Credentials__c record's Cart_Items__c field — called on every
    // cart change (add/remove/quantity change) and once right after login,
    // so an admin looking at the record always sees what's actually in the
    // shopper's cart, live. Deliberately best-effort: swallows any failure
    // rather than throwing, because this is a background mirror, not
    // something that should ever block or error out the shopping flow.
    @AuraEnabled
    public static void updateCartSnapshot(Id loginCredentialsId, String cartSummary) {
        if (loginCredentialsId == null) {
            return;
        }
        try {
            Database.update(
                new Login_Credentials__c(
                    Id = loginCredentialsId,
                    Cart_Items__c = cartSummary
                ),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cart snapshot mirror failed: ' + e.getMessage());
        }
    }

    // Records one row of cart history (see Cart_Activity__c) every time a
    // shopper adds, removes, or clears something from their cart — called
    // alongside updateCartSnapshot by cartService.js. Cart_Items__c above
    // only ever shows the CURRENT cart; this is the permanent, append-only
    // log of every change that ever happened to it, one record per action,
    // timestamped by CreatedDate. Same best-effort reasoning as
    // updateCartSnapshot: never blocks or errors out the shopping flow.
    @AuraEnabled
    public static void logCartActivity(Id loginCredentialsId, String action, String productName, Decimal quantity, Decimal price) {
        if (loginCredentialsId == null || String.isBlank(action)) {
            return;
        }
        try {
            Cart_Activity__c activity = new Cart_Activity__c();
            activity.Login_Credentials__c = loginCredentialsId;
            activity.Action__c = action;
            activity.Product_Name__c = productName;
            activity.Quantity__c = quantity;
            activity.Price__c = price;
            Database.insert(activity, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cart activity log failed: ' + e.getMessage());
        }
    }

    // Same admin-resolution pattern as CheckoutController.getDefaultOwnerId —
    // duplicated rather than shared, since that method is private to a
    // different class and this is only a few lines.
    private static Id getDefaultOwnerId() {
        List<User> namedAdmin = [
            SELECT Id FROM User
            WHERE Username = 'lokesh@codleo.org' AND IsActive = true
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

    // Returned to the LWC after a successful sign-up or login — never
    // includes the password, salt, or hash. This is what authService stores
    // client-side as the "logged in" session.
    public class AccountSession {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
    }
}
