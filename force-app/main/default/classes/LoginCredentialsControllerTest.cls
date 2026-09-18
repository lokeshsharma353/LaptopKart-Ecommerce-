@isTest
private class LoginCredentialsControllerTest {

    /** Signing up then logging in with the same email/password returns the same account. */
    @isTest
    static void signUpCreatesAccountAndAllowsLogin() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Test Shopper', 'shopper@example.com', '9999911111', 'SuperSecret123'
        );
        System.assertNotEquals(null, session.id, 'Sign-up should return a new record Id.');
        System.assertEquals('Test Shopper', session.name);
        System.assertEquals('shopper@example.com', session.email);

        Test.startTest();
        LoginCredentialsController.AccountSession loggedIn = LoginCredentialsController.logIn('shopper@example.com', 'SuperSecret123');
        Test.stopTest();

        System.assertEquals(session.id, loggedIn.id, 'Logging in with the correct credentials should return the same account.');
    }

    /** A second sign-up with the same email (any letter casing) is blocked as a duplicate. */
    @isTest
    static void signUpIsCaseInsensitiveOnEmailAndBlocksDuplicates() {
        LoginCredentialsController.signUp('First User', 'Dup@Example.com', '9999911111', 'SuperSecret123');

        Boolean blocked = false;
        try {
            LoginCredentialsController.signUp('Second User', 'dup@example.com', '9999922222', 'AnotherPass123');
        } catch (AuraHandledException e) {
            blocked = true;
        }
        System.assert(blocked, 'A second sign-up with the same email (any case) must be blocked.');

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Account WHERE Email__c = 'dup@example.com']
        );
    }

    /** Logging in with the correct email but wrong password is rejected. */
    @isTest
    static void logInRejectsWrongPassword() {
        LoginCredentialsController.signUp('Test Shopper', 'wrongpass@example.com', '9999911111', 'SuperSecret123');

        Boolean rejected = false;
        try {
            LoginCredentialsController.logIn('wrongpass@example.com', 'NotTheRightPassword');
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assert(rejected, 'Logging in with the wrong password must be rejected.');
    }

    /** Logging in with an email that was never signed up is rejected. */
    @isTest
    static void logInRejectsUnknownEmail() {
        Boolean rejected = false;
        try {
            LoginCredentialsController.logIn('nobody@example.com', 'WhateverPassword1');
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assert(rejected, 'Logging in with an email that was never signed up must be rejected.');
    }

    /** Sign-up rejects a blank name, blank phone, invalid email format, and a too-short (7-char) password; exactly 8 characters is accepted. */
    @isTest
    static void signUpValidatesRequiredFieldsEmailFormatAndPasswordLength() {
        Boolean blankNameRejected = false;
        try {
            LoginCredentialsController.signUp('', 'noname@example.com', '9999911111', 'SuperSecret123');
        } catch (AuraHandledException e) {
            blankNameRejected = true;
        }
        System.assert(blankNameRejected, 'A blank name must be rejected.');

        Boolean blankPhoneRejected = false;
        try {
            LoginCredentialsController.signUp('Test User', 'nophone@example.com', '', 'SuperSecret123');
        } catch (AuraHandledException e) {
            blankPhoneRejected = true;
        }
        System.assert(blankPhoneRejected, 'A blank phone must be rejected.');

        Boolean emailRejected = false;
        try {
            LoginCredentialsController.signUp('Test User', 'not-an-email', '9999911111', 'SuperSecret123');
        } catch (AuraHandledException e) {
            emailRejected = true;
        }
        System.assert(emailRejected, 'An invalid email format must be rejected.');

        Boolean passwordRejected = false;
        try {
            LoginCredentialsController.signUp('Test User', 'shortpass@example.com', '9999911111', 'short7x');
        } catch (AuraHandledException e) {
            passwordRejected = true;
        }
        System.assert(passwordRejected, 'A 7-character password (one under the minimum) must be rejected.');

        // Boundary: exactly 8 characters must be ACCEPTED, not rejected.
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Test User', 'exactly8@example.com', '9999911111', '8charpwd'
        );
        System.assertNotEquals(null, session.id, 'A password of exactly 8 characters must be accepted.');
    }

    /** Login accepts any casing of the email, but the password must match exactly (case-sensitive). */
    @isTest
    static void logInEmailIsCaseInsensitiveButPasswordIsCaseSensitive() {
        LoginCredentialsController.signUp('Case Test', 'CaseTest@Example.com', '9999911111', 'MyPassword1');

        // Email case must not matter for login — any casing should match.
        LoginCredentialsController.AccountSession lower = LoginCredentialsController.logIn('casetest@example.com', 'MyPassword1');
        LoginCredentialsController.AccountSession upper = LoginCredentialsController.logIn('CASETEST@EXAMPLE.COM', 'MyPassword1');
        System.assertNotEquals(null, lower.id);
        System.assertEquals(lower.id, upper.id, 'Login must work regardless of email casing.');

        // Password case DOES matter — a lowercased password must be rejected.
        Boolean rejected = false;
        try {
            LoginCredentialsController.logIn('casetest@example.com', 'mypassword1');
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assert(rejected, 'Password comparison must be case-sensitive.');
    }

    /** Sign-up trims stray leading/trailing whitespace off name/email/phone, and login trims the email the same way. */
    @isTest
    static void signUpAndLoginTrimSurroundingWhitespace() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            '  Trimmed Name  ', '  trim.test@example.com  ', '  9999911111  ', 'SuperSecret123'
        );
        System.assertEquals('Trimmed Name', session.name, 'Name should be trimmed before storage.');
        System.assertEquals('trim.test@example.com', session.email, 'Email should be trimmed and lowercased.');
        System.assertEquals('9999911111', session.phone, 'Phone should be trimmed before storage.');

        // Logging in with extra whitespace around the email must still work.
        LoginCredentialsController.AccountSession loggedIn = LoginCredentialsController.logIn('  trim.test@example.com  ', 'SuperSecret123');
        System.assertEquals(session.id, loggedIn.id, 'Login should trim whitespace from the email the same way sign-up does.');
    }

    /** The same account can log in repeatedly from independent calls ("another device"), always reaching the same account. */
    @isTest
    static void sameAccountCanLogInFromMultipleIndependentSessions() {
        // Simulates "another device": the backend has no concept of a single
        // active session per account — every logIn() call is stateless, so
        // the same email+password can succeed repeatedly and independently.
        // (The actual "logged in" state lives only in each browser's own
        // localStorage via authService — a separate device's storage can
        // never see or be affected by another device's, by browser design.)
        LoginCredentialsController.signUp('Multi Device', 'multidevice@example.com', '9999911111', 'DeviceLogin1');

        LoginCredentialsController.AccountSession deviceA = LoginCredentialsController.logIn('multidevice@example.com', 'DeviceLogin1');
        LoginCredentialsController.AccountSession deviceB = LoginCredentialsController.logIn('multidevice@example.com', 'DeviceLogin1');
        LoginCredentialsController.AccountSession deviceC = LoginCredentialsController.logIn('MultiDevice@Example.com', 'DeviceLogin1');

        System.assertEquals(deviceA.id, deviceB.id, '"Device B" logging in with the same credentials must reach the same account.');
        System.assertEquals(deviceA.id, deviceC.id, '"Device C" logging in with a different email casing must still reach the same account.');
        System.assertEquals(deviceA.name, deviceB.name);
        System.assertEquals(deviceA.phone, deviceB.phone);
    }

    /** Two different accounts' credentials never cross-authenticate each other. */
    @isTest
    static void multipleDistinctAccountsAreFullyIsolatedFromEachOther() {
        LoginCredentialsController.AccountSession accountA = LoginCredentialsController.signUp(
            'Account A', 'accountA@example.com', '9999911111', 'PasswordA1'
        );
        LoginCredentialsController.AccountSession accountB = LoginCredentialsController.signUp(
            'Account B', 'accountB@example.com', '9999922222', 'PasswordB1'
        );
        System.assertNotEquals(accountA.id, accountB.id);

        // A's password must not work for B's email, and vice versa.
        Boolean crossRejectedAB = false;
        try {
            LoginCredentialsController.logIn('accountB@example.com', 'PasswordA1');
        } catch (AuraHandledException e) {
            crossRejectedAB = true;
        }
        System.assert(crossRejectedAB, 'Account A\'s password must not log into Account B.');

        Boolean crossRejectedBA = false;
        try {
            LoginCredentialsController.logIn('accountA@example.com', 'PasswordB1');
        } catch (AuraHandledException e) {
            crossRejectedBA = true;
        }
        System.assert(crossRejectedBA, 'Account B\'s password must not log into Account A.');

        // Each account's own credentials still work correctly.
        LoginCredentialsController.AccountSession loginA = LoginCredentialsController.logIn('accountA@example.com', 'PasswordA1');
        LoginCredentialsController.AccountSession loginB = LoginCredentialsController.logIn('accountB@example.com', 'PasswordB1');
        System.assertEquals(accountA.id, loginA.id);
        System.assertEquals(accountB.id, loginB.id);
    }

    /** Blank credentials on login, and a whitespace-only email on sign-up, are both rejected. */
    @isTest
    static void signUpAndLoginRejectBlankOrWhitespaceOnlyCredentials() {
        Boolean blankLoginRejected = false;
        try {
            LoginCredentialsController.logIn('', '');
        } catch (AuraHandledException e) {
            blankLoginRejected = true;
        }
        System.assert(blankLoginRejected, 'Blank email/password on login must be rejected.');

        Boolean whitespaceEmailRejected = false;
        try {
            LoginCredentialsController.signUp('Test User', '   ', '9999911111', 'SuperSecret123');
        } catch (AuraHandledException e) {
            whitespaceEmailRejected = true;
        }
        System.assert(whitespaceEmailRejected, 'A whitespace-only email must be rejected as blank.');
    }

    /** A forgot-password request for a real account creates a Task recording the match and the shopper's message. */
    @isTest
    static void requestPasswordResetCreatesTaskForExistingAccount() {
        LoginCredentialsController.signUp('Forgot Test', 'forgot-existing@example.com', '9999911111', 'SuperSecret123');

        Test.startTest();
        LoginCredentialsController.requestPasswordReset('forgot-existing@example.com', '9999911111', 'I can\'t remember my password');
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, Description, Status, Priority, OwnerId FROM Task WHERE Subject = 'Password Reset Request - forgot-existing@example.com'];
        System.assertEquals(1, tasks.size(), 'A Task must be created for the reset request.');
        System.assert(tasks[0].Description.contains('Matching account found: Yes'), 'Task must record that a matching account was found.');
        System.assert(tasks[0].Description.contains('Forgot Test'), 'Task must include the account name on file.');
        System.assert(tasks[0].Description.contains('I can\'t remember my password'), 'Task must include the shopper\'s message.');
        System.assertEquals('Not Started', tasks[0].Status);
        System.assertEquals('High', tasks[0].Priority);
        System.assertNotEquals(null, tasks[0].OwnerId, 'Task must be assigned to an owner.');
    }

    /** A forgot-password request for an unregistered email still creates a Task (for the admin), without telling the caller the email wasn't found. */
    @isTest
    static void requestPasswordResetCreatesTaskEvenForUnknownEmailWithoutRevealingIt() {
        // The customer-facing behavior must not reveal whether the email is
        // registered (requestPasswordReset never throws for an unknown
        // email) — but the Task itself records the truth for the admin.
        LoginCredentialsController.requestPasswordReset('never-signed-up@example.com', '', '');

        List<Task> tasks = [SELECT Description FROM Task WHERE Subject = 'Password Reset Request - never-signed-up@example.com'];
        System.assertEquals(1, tasks.size(), 'A Task must still be created even when no account matches.');
        System.assert(tasks[0].Description.contains('Matching account found: No'), 'Task must record that no matching account was found.');
    }

    /** A forgot-password request rejects a blank or badly-formatted email. */
    @isTest
    static void requestPasswordResetValidatesEmail() {
        Boolean blankRejected = false;
        try {
            LoginCredentialsController.requestPasswordReset('', '', '');
        } catch (AuraHandledException e) {
            blankRejected = true;
        }
        System.assert(blankRejected, 'A blank email must be rejected.');

        Boolean invalidRejected = false;
        try {
            LoginCredentialsController.requestPasswordReset('not-an-email', '', '');
        } catch (AuraHandledException e) {
            invalidRejected = true;
        }
        System.assert(invalidRejected, 'An invalid email format must be rejected.');
    }

    /** A fresh sign-up has no profile photo yet; uploading one saves it, and a subsequent logIn returns the same photo. */
    @isTest
    static void updateProfilePhotoSavesAndPersistsAcrossLogin() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Photo Shopper', 'photo-shopper@example.com', '9999911111', 'SuperSecret123'
        );
        System.assertEquals(null, session.profilePhoto, 'A fresh sign-up must have no profile photo yet.');

        String photoDataUri = 'data:image/jpeg;base64,' + 'QQ'.repeat(2000);

        Test.startTest();
        LoginCredentialsController.updateProfilePhoto(session.id, photoDataUri);
        LoginCredentialsController.AccountSession loggedIn = LoginCredentialsController.logIn('photo-shopper@example.com', 'SuperSecret123');
        Test.stopTest();

        System.assertEquals(photoDataUri, loggedIn.profilePhoto, 'logIn must return the just-uploaded profile photo.');
    }

    /** An oversized photo payload is rejected before any DML runs, rather than failing with a raw field-too-long error. */
    @isTest
    static void updateProfilePhotoRejectsOversizedPayload() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Oversized Photo Shopper', 'oversized-photo@example.com', '9999911111', 'SuperSecret123'
        );
        String tooLarge = 'data:image/jpeg;base64,' + 'A'.repeat(130000);

        Boolean rejected = false;
        Test.startTest();
        try {
            LoginCredentialsController.updateProfilePhoto(session.id, tooLarge);
        } catch (AuraHandledException e) {
            rejected = true;
        }
        Test.stopTest();

        System.assert(rejected, 'An oversized photo payload must be rejected.');
        Account afterAttempt = [SELECT Profile_Photo__c FROM Account WHERE Id = :session.id];
        System.assertEquals(null, afterAttempt.Profile_Photo__c, 'The rejected photo must never be saved.');
    }

    /** A null accountId is rejected, same defensive guard every other Account-mutating method in this class already has. */
    @isTest
    static void updateProfilePhotoRejectsNullAccountId() {
        Boolean rejected = false;
        try {
            LoginCredentialsController.updateProfilePhoto(null, 'data:image/jpeg;base64,QQ==');
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assert(rejected, 'A null accountId must be rejected.');
    }

    /** Saving a new address (null addressId) creates it under the shopper's own Account, and it shows up in getMyAddresses. */
    @isTest
    static void saveMyAddressCreatesNewAddressUnderOwnAccount() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Address Shopper', 'address-shopper@example.com', '9999911111', 'SuperSecret123'
        );

        Test.startTest();
        Id newId = LoginCredentialsController.saveMyAddress(session.id, null, '221B Baker Street', 'Delhi', '9999911111');
        Test.stopTest();

        System.assertNotEquals(null, newId, 'saveMyAddress must return the new record id.');
        List<LoginCredentialsController.SavedAddress> addresses = LoginCredentialsController.getMyAddresses(session.id);
        System.assertEquals(1, addresses.size());
        System.assertEquals('221B Baker Street', addresses[0].line1);
        System.assertEquals(newId, addresses[0].id);
    }

    /** Passing an existing addressId updates that same record in place rather than creating a second one. */
    @isTest
    static void saveMyAddressUpdatesExistingAddressInPlace() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Update Address Shopper', 'update-address@example.com', '9999911111', 'SuperSecret123'
        );
        Id addressId = LoginCredentialsController.saveMyAddress(session.id, null, 'Old Line', 'Mumbai', '9999911111');

        Test.startTest();
        Id updatedId = LoginCredentialsController.saveMyAddress(session.id, addressId, 'New Line', 'Pune', '8888822222');
        Test.stopTest();

        System.assertEquals(addressId, updatedId, 'Updating an existing address must not create a new record.');
        List<LoginCredentialsController.SavedAddress> addresses = LoginCredentialsController.getMyAddresses(session.id);
        System.assertEquals(1, addresses.size(), 'There must still be exactly one saved address.');
        System.assertEquals('New Line', addresses[0].line1);
        System.assertEquals('Pune', addresses[0].city);
    }

    /** One shopper's session can never edit or delete another shopper's saved address, even by guessing/reusing its record Id. */
    @isTest
    static void savedAddressesAreIsolatedBetweenAccounts() {
        LoginCredentialsController.AccountSession ownerSession = LoginCredentialsController.signUp(
            'Owner Shopper', 'owner-shopper@example.com', '9999911111', 'SuperSecret123'
        );
        LoginCredentialsController.AccountSession otherSession = LoginCredentialsController.signUp(
            'Other Shopper', 'other-shopper@example.com', '9999922222', 'SuperSecret123'
        );
        Id ownerAddressId = LoginCredentialsController.saveMyAddress(ownerSession.id, null, 'Owner Street', 'Delhi', '9999911111');

        Test.startTest();
        Boolean editBlocked = false;
        try {
            LoginCredentialsController.saveMyAddress(otherSession.id, ownerAddressId, 'Hijacked Street', 'Nowhere', '0000000000');
        } catch (AuraHandledException e) {
            editBlocked = true;
        }
        LoginCredentialsController.deleteMyAddress(otherSession.id, ownerAddressId);
        Test.stopTest();

        System.assert(editBlocked, 'Editing another account\'s address by id must be blocked.');
        List<LoginCredentialsController.SavedAddress> ownerAddresses = LoginCredentialsController.getMyAddresses(ownerSession.id);
        System.assertEquals(1, ownerAddresses.size(), 'The owner\'s address must survive an unauthorized delete attempt from another account.');
        System.assertEquals('Owner Street', ownerAddresses[0].line1, 'The owner\'s address must be untouched by the unauthorized edit attempt.');
    }

    /** Deleting one's own address removes it, and getMyAddresses for a null/no-session account returns an empty list. */
    @isTest
    static void deleteMyAddressRemovesOwnAddress() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Delete Address Shopper', 'delete-address@example.com', '9999911111', 'SuperSecret123'
        );
        Id addressId = LoginCredentialsController.saveMyAddress(session.id, null, 'Temp Street', 'Chennai', '9999911111');

        Test.startTest();
        LoginCredentialsController.deleteMyAddress(session.id, addressId);
        Test.stopTest();

        System.assertEquals(0, LoginCredentialsController.getMyAddresses(session.id).size());
        System.assertEquals(0, LoginCredentialsController.getMyAddresses(null).size());
    }

    /** Updating profile info changes Name/Email/Phone on both the Account and its linked Contact, and a subsequent logIn uses the new email. */
    @isTest
    static void updateProfileInfoUpdatesAccountAndContactAndAllowsLoginWithNewEmail() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Old Name', 'old-email@example.com', '9999911111', 'SuperSecret123'
        );

        Test.startTest();
        LoginCredentialsController.AccountSession updated = LoginCredentialsController.updateProfileInfo(
            session.id, 'New Name', 'new-email@example.com', '8888822222'
        );
        LoginCredentialsController.AccountSession loggedIn = LoginCredentialsController.logIn('new-email@example.com', 'SuperSecret123');
        Test.stopTest();

        System.assertEquals('New Name', updated.name);
        System.assertEquals('new-email@example.com', updated.email);
        System.assertEquals('8888822222', updated.phone);
        System.assertEquals(session.id, loggedIn.id, 'Logging in with the new email must return the same account.');

        Contact linkedContact = [SELECT LastName, Email, Phone FROM Contact WHERE AccountId = :session.id LIMIT 1];
        System.assertEquals('New Name', linkedContact.LastName);
        System.assertEquals('new-email@example.com', linkedContact.Email);
        System.assertEquals('8888822222', linkedContact.Phone);
    }

    /** updateProfileInfo blocks changing to an email another account already uses, leaving the original account untouched. */
    @isTest
    static void updateProfileInfoBlocksDuplicateEmail() {
        LoginCredentialsController.signUp('First Shopper', 'first-shopper@example.com', '9999911111', 'SuperSecret123');
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Second Shopper', 'second-shopper@example.com', '9999922222', 'SuperSecret123'
        );

        Test.startTest();
        Boolean blocked = false;
        try {
            LoginCredentialsController.updateProfileInfo(session.id, 'Second Shopper', 'first-shopper@example.com', '9999922222');
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'Changing to an email already used by another account must be blocked.');
        Account unchanged = [SELECT Email__c FROM Account WHERE Id = :session.id];
        System.assertEquals('second-shopper@example.com', unchanged.Email__c, 'The original email must be unchanged after a blocked update.');
    }

    /** updateProfileInfo validates required fields and email format, and rejects a null accountId, same as the rest of this class. */
    @isTest
    static void updateProfileInfoValidatesInput() {
        LoginCredentialsController.AccountSession session = LoginCredentialsController.signUp(
            'Validate Shopper', 'validate-shopper@example.com', '9999911111', 'SuperSecret123'
        );

        Boolean blankBlocked = false;
        try {
            LoginCredentialsController.updateProfileInfo(session.id, '', 'validate-shopper@example.com', '9999911111');
        } catch (AuraHandledException e) {
            blankBlocked = true;
        }
        System.assert(blankBlocked, 'A blank name must be rejected.');

        Boolean badEmailBlocked = false;
        try {
            LoginCredentialsController.updateProfileInfo(session.id, 'Validate Shopper', 'not-an-email', '9999911111');
        } catch (AuraHandledException e) {
            badEmailBlocked = true;
        }
        System.assert(badEmailBlocked, 'An invalid email format must be rejected.');

        Boolean nullAccountBlocked = false;
        try {
            LoginCredentialsController.updateProfileInfo(null, 'Validate Shopper', 'validate-shopper@example.com', '9999911111');
        } catch (AuraHandledException e) {
            nullAccountBlocked = true;
        }
        System.assert(nullAccountBlocked, 'A null accountId must be rejected.');
    }
}
