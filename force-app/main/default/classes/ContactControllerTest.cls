@isTest
private class ContactControllerTest {

    // A Guest visitor submitting the Contact Us form has no record access of
    // their own — this proves the same identity real production traffic
    // uses, same reasoning as CheckoutControllerTest.
    private static User getGuestUser() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
    }


    /** A full Contact Us submission saves every field, defaulting Status to New and priority to Medium. */
    @isTest
    static void submitMessageSavesFullTicketWithDefaults() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            Test.startTest();
            ContactController.submitMessage(
                'Jane Shopper', 'jane@example.com', '9998887777',
                'Where is my order?', 'It has been 6 days and I have not received it.'
            );
            Test.stopTest();
        }

        Contact_Us__c ticket = [
            SELECT Name__c, Email__c, Phone__c, Subject__c, Message__c,
                   Status__c, Low_Medium_High_Urgent__c, Created_Date__c
            FROM Contact_Us__c
            WHERE Email__c = 'jane@example.com'
            LIMIT 1
        ];

        System.assertEquals('Jane Shopper', ticket.Name__c, 'Name should be saved.');
        System.assertEquals('9998887777', ticket.Phone__c, 'Phone should be saved.');
        System.assertEquals('Where is my order?', ticket.Subject__c, 'Subject should be saved.');
        System.assertEquals('It has been 6 days and I have not received it.', ticket.Message__c, 'Message should be saved.');
        System.assertEquals('New', ticket.Status__c, 'New tickets should default to New status.');
        System.assertEquals('Medium', ticket.Low_Medium_High_Urgent__c, 'New tickets should default to Medium priority.');
        System.assertEquals(Date.today(), ticket.Created_Date__c, 'Created date should be set to today.');
    }


    /** Submitting the form without a phone number still saves the ticket, leaving Phone blank. */
    @isTest
    static void submitMessageWorksWithoutOptionalPhone() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            Test.startTest();
            ContactController.submitMessage(
                'No Phone Customer', 'nophone@example.com', null,
                'General question', 'Do you have a physical store?'
            );
            Test.stopTest();
        }

        Contact_Us__c ticket = [
            SELECT Phone__c FROM Contact_Us__c WHERE Email__c = 'nophone@example.com' LIMIT 1
        ];
        System.assertEquals(null, ticket.Phone__c, 'Phone should remain blank when not provided.');
    }


    /** A blank name, email, subject, or message is each rejected, and no ticket is created. */
    @isTest
    static void submitMessageRejectsMissingRequiredFields() {
        Boolean threwOnBlankName = false;
        try {
            ContactController.submitMessage('', 'a@example.com', null, 'Subject', 'Message');
        } catch (AuraHandledException e) {
            threwOnBlankName = true;
        }
        System.assert(threwOnBlankName, 'Blank name must be rejected.');

        Boolean threwOnBlankEmail = false;
        try {
            ContactController.submitMessage('Name', '', null, 'Subject', 'Message');
        } catch (AuraHandledException e) {
            threwOnBlankEmail = true;
        }
        System.assert(threwOnBlankEmail, 'Blank email must be rejected.');

        Boolean threwOnBlankSubject = false;
        try {
            ContactController.submitMessage('Name', 'a@example.com', null, '', 'Message');
        } catch (AuraHandledException e) {
            threwOnBlankSubject = true;
        }
        System.assert(threwOnBlankSubject, 'Blank subject must be rejected.');

        Boolean threwOnBlankMessage = false;
        try {
            ContactController.submitMessage('Name', 'a@example.com', null, 'Subject', '');
        } catch (AuraHandledException e) {
            threwOnBlankMessage = true;
        }
        System.assert(threwOnBlankMessage, 'Blank message must be rejected.');

        System.assertEquals(0, [SELECT COUNT() FROM Contact_Us__c], 'No ticket should be created for an invalid submission.');
    }


    /** Two separate form submissions create two separate, independent tickets. */
    @isTest
    static void submitMessageAllowsMultipleIndependentSubmissions() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            Test.startTest();
            ContactController.submitMessage('Customer One', 'one@example.com', null, 'Subject One', 'Message One');
            ContactController.submitMessage('Customer Two', 'two@example.com', null, 'Subject Two', 'Message Two');
            Test.stopTest();
        }

        System.assertEquals(2, [SELECT COUNT() FROM Contact_Us__c], 'Both independent submissions should be saved as separate tickets.');
    }
}
