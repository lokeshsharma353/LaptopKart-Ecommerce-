// without sharing: a not-yet-authenticated site guest has no record access of
// their own before signing up or logging in, so checking for an existing
// email and reading/writing Account must run in system context — same
// reasoning used throughout this storefront's Guest-User-facing controllers
// (CheckoutController, RegistrationController, etc.).
//
// This is a lightweight, custom login system built on the standard Account
// object (Customer Account Detail record type) — NOT real Salesforce
// authentication (no Salesforce User is created, no real session/identity is
// established). "Being logged in" is tracked client-side by the LWC
// (authService) after a successful call here. Originally built on a separate
// Login_Credentials__c custom object; migrated onto Account so a shopper's
// login identity and their real Orders/Payments/Order Trackings — which
// already relate to Account via CheckoutController's Lead-conversion
// pipeline — live on the same record instead of two disconnected ones.
//
// Password_Text__c stores the password in plain text (by explicit request,
// so admins can view/look up a shopper's password directly on the record in
// Setup) — this is NOT the secure approach (a hash would be unrecoverable
// even to admins) and means anyone with read access to this object, or a
// data export/backup, can see every shopper's raw password.
public without sharing class LoginCredentialsController {

    private static final Integer MIN_PASSWORD_LENGTH = 8;

    // Cached per-transaction — getRecordTypeInfosByDeveloperName() is a
    // Schema call (no SOQL, no governor-limit cost), but there's no reason
    // to look it up more than once per request. Returns null (rather than
    // throwing) if the record type doesn't exist in a given org/sandbox, so
    // signup/checkout still work there — just without record-type
    // normalization — instead of hard-failing every signup.
    private static Id customerAccountDetailRTId;
    private static Id getCustomerAccountDetailRecordTypeId() {
        if (customerAccountDetailRTId == null) {
            Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Customer_Account_Details');
            customerAccountDetailRTId = (rtInfo != null) ? rtInfo.getRecordTypeId() : null;
        }
        return customerAccountDetailRTId;
    }

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
        String trimmedName = name.trim();
        String trimmedPhone = phone.trim();

        List<Account> existingLogin = [
            SELECT Id
            FROM Account
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existingLogin.isEmpty()) {
            throw new AuraHandledException('An account with this email already exists. Please log in instead.');
        }

        // A shopper may have already checked out as a guest under this email
        // before ever signing up — CheckoutController's Lead-conversion
        // pipeline would have already created a real Contact/Account for
        // them. Reuse that same Account (turning it into a full login
        // account) instead of creating a second, disconnected one that
        // would never show their existing Orders/Payments.
        List<Contact> existingContacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Id accountId;
        if (!existingContacts.isEmpty()) {
            accountId = existingContacts[0].AccountId;
            Account upgrade = new Account(Id = accountId);
            upgrade.Name = trimmedName;
            upgrade.Phone = trimmedPhone;
            upgrade.Email__c = normalizedEmail;
            upgrade.Password_Text__c = password;
            Id rtId = getCustomerAccountDetailRecordTypeId();
            if (rtId != null) {
                upgrade.RecordTypeId = rtId;
            }
            Database.update(upgrade, AccessLevel.SYSTEM_MODE);
        } else {
            Account newAccount = new Account();
            newAccount.Name = trimmedName;
            newAccount.Phone = trimmedPhone;
            newAccount.Email__c = normalizedEmail;
            newAccount.Password_Text__c = password;
            Id rtId = getCustomerAccountDetailRecordTypeId();
            if (rtId != null) {
                newAccount.RecordTypeId = rtId;
            }
            Database.insert(newAccount, AccessLevel.SYSTEM_MODE);
            accountId = newAccount.Id;

            Contact newContact = new Contact();
            newContact.LastName = trimmedName;
            newContact.Email = normalizedEmail;
            newContact.Phone = trimmedPhone;
            newContact.AccountId = accountId;
            Database.insert(newContact, AccessLevel.SYSTEM_MODE);
        }

        Account resultAccount = [
            SELECT Id, Name, Email__c, Phone, Profile_Photo__c
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        AccountSession session = new AccountSession();
        session.id = resultAccount.Id;
        session.name = resultAccount.Name;
        session.email = resultAccount.Email__c;
        session.phone = resultAccount.Phone;
        session.profilePhoto = resultAccount.Profile_Photo__c;
        sendAccountCreatedEmail(resultAccount);
        return session;
    }

    /** Sends a one-time welcome message after a shopper completes sign-up. */
    private static void sendAccountCreatedEmail(Account account) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { account.Email__c });
            mail.setSubject('Welcome to LaptopKart, ' + account.Name + '!');
            mail.setPlainTextBody(
                'Hi ' + account.Name + ',\n\n' +
                'Your LaptopKart account is ready. You can now sign in to view your orders and track deliveries.\n\n' +
                'Account email: ' + account.Email__c + '\n' +
                'Phone: ' + (String.isBlank(account.Phone) ? 'Not provided' : account.Phone) + '\n\n' +
                'For your security, we will never email your password.\n\n' +
                '- The LaptopKart Team'
            );
            mail.setHtmlBody(
                '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                    '<h2 style="margin:0 0 8px;font-size:20px;color:#1a7a3a;">Welcome to LaptopKart!</h2>' +
                    '<p style="color:#555555;font-size:14px;line-height:1.5;">Hi ' + account.Name.escapeHtml4() +
                    ', your account is ready. You can now sign in to view orders and track deliveries.</p>' +
                    '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                        '<tr><td style="color:#666;padding:4px 0;">Account email</td><td style="text-align:right;">' + account.Email__c.escapeHtml4() + '</td></tr>' +
                        '<tr><td style="color:#666;padding:4px 0;">Phone</td><td style="text-align:right;">' +
                            (String.isBlank(account.Phone) ? 'Not provided' : account.Phone.escapeHtml4()) + '</td></tr>' +
                    '</table>' +
                    '<p style="font-size:12px;color:#777;">For your security, we will never email your password.</p>' +
                    '<p>- The LaptopKart Team</p>' +
                '</div>'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Account-created email failed: ' + e.getMessage());
            EmailSenderService.logEmailFailure('Account Creation Welcome', account.Email__c, e.getMessage());
        }
    }

    /** Verifies email + password against Account.Email__c/Password_Text__c (case-insensitive email, case-sensitive password) and returns the account session, or throws a generic error for either a wrong password or an unknown email. */
    @AuraEnabled
    public static AccountSession logIn(String email, String password) {
        if (String.isBlank(email) || String.isBlank(password)) {
            throw new AuraHandledException('Please enter your email and password.');
        }

        String normalizedEmail = email.trim().toLowerCase();

        List<Account> matches = [
            SELECT Id, Name, Email__c, Phone, Password_Text__c, Profile_Photo__c
            FROM Account
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        // Same generic message whether the email doesn't exist or the
        // password is wrong — never reveals which emails are registered.
        // Password comparison uses String.equals() deliberately, NOT != —
        // Apex's == / != operators compare strings case-INsensitively by
        // default, which would silently accept a wrong-case password.
        if (matches.isEmpty() || String.isBlank(matches[0].Password_Text__c) || !matches[0].Password_Text__c.equals(password)) {
            throw new AuraHandledException('Invalid email or password.');
        }

        Account acc = matches[0];
        AccountSession session = new AccountSession();
        session.id = acc.Id;
        session.name = acc.Name;
        session.email = acc.Email__c;
        session.phone = acc.Phone;
        session.profilePhoto = acc.Profile_Photo__c;
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

        List<Account> matches = [
            SELECT Id, Name
            FROM Account
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
            (accountFound ? 'Account Name on file: ' + matches[0].Name + '\n' : '') +
            '\nMessage from shopper:\n' + (String.isBlank(message) ? '(none provided)' : message.trim());
        reminderTask.Status = 'Not Started';
        reminderTask.Priority = 'High';
        reminderTask.ActivityDate = Date.today();
        reminderTask.OwnerId = getDefaultOwnerId();
        if (accountFound) {
            reminderTask.WhatId = matches[0].Id;
        }

        Database.insert(reminderTask, AccessLevel.SYSTEM_MODE);

        sendPasswordResetReceivedEmail(normalizedEmail);
    }

    // Confirms receipt of a password-reset request straight to whatever
    // email was entered — sent regardless of whether accountFound is true,
    // with identical wording either way, so this email can never be used to
    // find out whether a given address has a LaptopKart account (same
    // non-disclosure reasoning as requestPasswordReset's generic Task and
    // logIn's generic error message). It never contains the password itself
    // — there is no automated reset link in this custom login system; an
    // admin follows up personally using the Task above.
    private static void sendPasswordResetReceivedEmail(String normalizedEmail) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { normalizedEmail });
            mail.setSubject('LaptopKart — Password Reset Request Received');
            mail.setPlainTextBody(
                'Hi,\n\n' +
                'We received a request to reset the password for the LaptopKart account associated ' +
                'with ' + normalizedEmail + '.\n\n' +
                'If this account exists, our support team will personally reach out within 24 hours ' +
                'to help you regain access — there is no automated reset link in our current system.\n\n' +
                'If you didn\'t request this, you can safely ignore this email.\n\n' +
                '- The LaptopKart Team'
            );
            mail.setHtmlBody(
                '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                    '<h2 style="margin:0 0 8px;font-size:20px;color:#1a7a3a;">Password Reset Request Received</h2>' +
                    '<p style="color:#555555;font-size:14px;line-height:1.5;">We received a request to reset the ' +
                    'password for the LaptopKart account associated with ' + normalizedEmail.escapeHtml4() + '.</p>' +
                    '<p style="color:#555555;font-size:14px;line-height:1.5;">If this account exists, our support ' +
                    'team will personally reach out within 24 hours to help you regain access.</p>' +
                    '<p style="font-size:12px;color:#777;">If you didn\'t request this, you can safely ignore this email.</p>' +
                    '<p>- The LaptopKart Team</p>' +
                '</div>'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Password-reset-received email failed: ' + e.getMessage());
            EmailSenderService.logEmailFailure('Password Reset Received', normalizedEmail, e.getMessage());
        }
    }

    // Mirrors the shopper's live cart (see cartService.js) onto their
    // Account record's Cart_Items__c field — called on every cart change
    // (add/remove/quantity change) and once right after login, so an admin
    // looking at the record always sees what's actually in the shopper's
    // cart, live. Deliberately best-effort: swallows any failure rather
    // than throwing, because this is a background mirror, not something
    // that should ever block or error out the shopping flow.
    @AuraEnabled
    public static void updateCartSnapshot(Id accountId, String cartSummary) {
        if (accountId == null) {
            return;
        }
        try {
            Database.update(
                new Account(
                    Id = accountId,
                    Cart_Items__c = cartSummary
                ),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cart snapshot mirror failed: ' + e.getMessage());
        }
    }

    // Records one row of permanent cart history (see Cart_Activity__c) every
    // time a shopper adds, removes, or clears something from their cart —
    // called alongside updateCartSnapshot by cartService.js. Cart_Items__c
    // above only ever shows the CURRENT cart; this is the permanent,
    // append-only log of every change that ever happened to it, one record
    // per action, timestamped by CreatedDate. Same best-effort reasoning as
    // updateCartSnapshot: never blocks or errors out the shopping flow.
    @AuraEnabled
    public static void logCartActivity(Id accountId, String action, String productName, Decimal quantity, Decimal price) {
        if (accountId == null || String.isBlank(action)) {
            return;
        }
        try {
            Cart_Activity__c activity = new Cart_Activity__c();
            activity.Account__c = accountId;
            activity.Action__c = action;
            activity.Product_Name__c = productName;
            activity.Quantity__c = quantity;
            activity.Price__c = price;
            Database.insert(activity, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cart activity log failed: ' + e.getMessage());
        }
    }

    // A resized JPEG data URI comfortably fits in a few tens of KB (see
    // Profile_Photo__c's own description) — this is a generous defensive
    // ceiling against something well past that, checked before the DML so a
    // shopper sees a clear error instead of an opaque field-too-long
    // failure. The field itself allows up to 131072 characters; this stays
    // safely under that.
    private static final Integer MAX_PROFILE_PHOTO_LENGTH = 120000;

    /**
     * Saves a shopper's profile photo — a data URI the client has already
     * resized/compressed (see techBasketMyAccount.js) — directly onto their
     * Account. Trusts the client-supplied accountId the same way every
     * other Account-mutating method in this class already does (this login
     * system has no real Salesforce session to check against instead — see
     * this class's own header comment).
     */
    @AuraEnabled
    public static void updateProfilePhoto(Id accountId, String photoDataUri) {
        if (accountId == null) {
            throw new AuraHandledException('You must be logged in to update your photo.');
        }
        if (String.isNotBlank(photoDataUri) && photoDataUri.length() > MAX_PROFILE_PHOTO_LENGTH) {
            throw new AuraHandledException('That image is too large. Please try a different photo.');
        }
        Database.update(
            new Account(Id = accountId, Profile_Photo__c = photoDataUri),
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Returns this customer's current loyalty point balance and their recent
     * ledger history (Loyalty_Point_Transaction__c — see LoyaltyService),
     * for the Rewards Wallet section of My Account. See Feature Expansion
     * Plan §2.7: "The customer should see the amount of money their points
     * can represent, not just an unexplained number" — pointsValueRupees
     * below is exactly that (1 point = ₹1, matching LoyaltyService).
     */
    @AuraEnabled
    public static LoyaltyWallet getLoyaltyWallet(Id accountId) {
        LoyaltyWallet wallet = new LoyaltyWallet();
        wallet.balance = 0;
        wallet.pointsValueRupees = 0;
        wallet.transactions = new List<LoyaltyTransactionSummary>();

        if (accountId == null) {
            return wallet;
        }

        List<Account> accounts = [
            SELECT Loyalty_Points_Balance__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (!accounts.isEmpty() && accounts[0].Loyalty_Points_Balance__c != null) {
            wallet.balance = accounts[0].Loyalty_Points_Balance__c.intValue();
            wallet.pointsValueRupees = wallet.balance;
        }

        for (Loyalty_Point_Transaction__c txn : [
            SELECT Id, Points__c, Type__c, Notes__c, Transaction_Date__c, Related_Order__r.OrderNumber
            FROM Loyalty_Point_Transaction__c
            WHERE Customer__c = :accountId
            WITH SYSTEM_MODE
            ORDER BY Transaction_Date__c DESC
            LIMIT 50
        ]) {
            LoyaltyTransactionSummary summary = new LoyaltyTransactionSummary();
            summary.id = txn.Id;
            summary.points = txn.Points__c == null ? 0 : txn.Points__c.intValue();
            summary.type = txn.Type__c;
            summary.notes = txn.Notes__c;
            summary.transactionDate = txn.Transaction_Date__c;
            summary.orderNumber = txn.Related_Order__r != null ? txn.Related_Order__r.OrderNumber : null;
            wallet.transactions.add(summary);
        }

        return wallet;
    }

    public class LoyaltyWallet {
        @AuraEnabled public Integer balance;
        @AuraEnabled public Integer pointsValueRupees;
        @AuraEnabled public List<LoyaltyTransactionSummary> transactions;
    }

    public class LoyaltyTransactionSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer points;
        @AuraEnabled public String type;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime transactionDate;
        @AuraEnabled public String orderNumber;
    }

    /**
     * Returns this shopper's saved delivery addresses (Saved_Address__c),
     * oldest first — the oldest one is treated as the default address, shown
     * with a "Default" badge in My Account's Saved Addresses section.
     */
    @AuraEnabled
    public static List<SavedAddress> getMyAddresses(Id accountId) {
        List<SavedAddress> result = new List<SavedAddress>();
        if (accountId == null) {
            return result;
        }
        for (Saved_Address__c addr : [
            SELECT Id, Line1__c, City__c, Phone__c
            FROM Saved_Address__c
            WHERE Account__c = :accountId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ]) {
            SavedAddress a = new SavedAddress();
            a.id = addr.Id;
            a.line1 = addr.Line1__c;
            a.city = addr.City__c;
            a.phone = addr.Phone__c;
            result.add(a);
        }
        return result;
    }

    /**
     * Creates or updates one of this shopper's saved addresses under their
     * own Account. A null addressId creates a new one; an existing id
     * updates it — but only after confirming that address actually belongs
     * to accountId, so a session can never edit another shopper's address by
     * guessing/reusing an id.
     */
    @AuraEnabled
    public static Id saveMyAddress(Id accountId, Id addressId, String line1, String city, String phone) {
        if (accountId == null) {
            throw new AuraHandledException('You must be logged in to save an address.');
        }

        Saved_Address__c addr;
        if (addressId != null) {
            List<Saved_Address__c> existing = [
                SELECT Id, Account__c FROM Saved_Address__c WHERE Id = :addressId WITH SYSTEM_MODE LIMIT 1
            ];
            if (existing.isEmpty() || existing[0].Account__c != accountId) {
                throw new AuraHandledException('Address not found.');
            }
            addr = existing[0];
        } else {
            addr = new Saved_Address__c(Account__c = accountId);
        }

        addr.Line1__c = line1;
        addr.City__c = city;
        addr.Phone__c = phone;
        Database.upsert(addr, AccessLevel.SYSTEM_MODE);
        return addr.Id;
    }

    /**
     * Deletes one of this shopper's saved addresses — verifies ownership
     * first, same reasoning as saveMyAddress.
     */
    @AuraEnabled
    public static void deleteMyAddress(Id accountId, Id addressId) {
        if (accountId == null || addressId == null) {
            return;
        }
        List<Saved_Address__c> existing = [
            SELECT Id, Account__c FROM Saved_Address__c WHERE Id = :addressId WITH SYSTEM_MODE LIMIT 1
        ];
        if (!existing.isEmpty() && existing[0].Account__c == accountId) {
            Database.delete(existing[0], AccessLevel.SYSTEM_MODE);
        }
    }

    public class SavedAddress {
        @AuraEnabled public Id id;
        @AuraEnabled public String line1;
        @AuraEnabled public String city;
        @AuraEnabled public String phone;
    }

    /**
     * Updates a shopper's own Name/Email/Phone from My Profile's "Edit"
     * form — mirrors signUp's validation (valid email format, no duplicate
     * email) since this is the only other place those fields can change
     * after sign-up. Also updates the linked Contact record created during
     * signUp/checkout so the two stay in sync — CheckoutController matches a
     * logged-in shopper's orders by Contact.AccountId, and the Contact's own
     * Name/Email/Phone should reflect the same edit.
     */
    @AuraEnabled
    public static AccountSession updateProfileInfo(Id accountId, String name, String email, String phone) {
        if (accountId == null) {
            throw new AuraHandledException('You must be logged in to update your profile.');
        }
        if (String.isBlank(name) || String.isBlank(email) || String.isBlank(phone)) {
            throw new AuraHandledException('Please fill in all fields.');
        }
        if (!Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', email.trim())) {
            throw new AuraHandledException('Please enter a valid email address.');
        }

        String normalizedEmail = email.trim().toLowerCase();
        String trimmedName = name.trim();
        String trimmedPhone = phone.trim();

        List<Account> emailClash = [
            SELECT Id FROM Account
            WHERE Email__c = :normalizedEmail AND Id != :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!emailClash.isEmpty()) {
            throw new AuraHandledException('Another account already uses this email address.');
        }

        Database.update(
            new Account(Id = accountId, Name = trimmedName, Email__c = normalizedEmail, Phone = trimmedPhone),
            AccessLevel.SYSTEM_MODE
        );

        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE AccountId = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (!contacts.isEmpty()) {
            Database.update(
                new Contact(Id = contacts[0].Id, LastName = trimmedName, Email = normalizedEmail, Phone = trimmedPhone),
                AccessLevel.SYSTEM_MODE
            );
        }

        Account resultAccount = [
            SELECT Id, Name, Email__c, Phone, Profile_Photo__c
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        AccountSession session = new AccountSession();
        session.id = resultAccount.Id;
        session.name = resultAccount.Name;
        session.email = resultAccount.Email__c;
        session.phone = resultAccount.Phone;
        session.profilePhoto = resultAccount.Profile_Photo__c;
        return session;
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
    // client-side as the "logged in" session. id is now an Account Id
    // (Customer Account Detail record type), not a Login_Credentials__c Id.
    public class AccountSession {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        // A "data:image/jpeg;base64,..." data URI, or null if the shopper
        // hasn't uploaded a profile photo yet — see Profile_Photo__c.
        @AuraEnabled public String profilePhoto;
    }
}
