// Runs without sharing: a not-yet-authenticated site guest has no record access
// of their own, so checking for an existing Contact by email and creating the
// new Account/Contact/User must run in system context. Every write here is
// deliberately narrow (see registerUser) rather than a general-purpose bypass.
public without sharing class RegistrationController {

    // Customer Community Login User — the member profile registered for the
    // TechBasket site (Setup > Digital Experiences > Administration > Members).
    private static final Id CUSTOMER_PROFILE_ID = '00ebm00000MXCKUAA5';

    // Creates a real Salesforce login for a new TechBasket customer. Salesforce
    // stores and hashes the password itself (Site.createExternalUser) — this
    // class never sees or stores it beyond passing it straight through.
    //
    // Duplicate handling:
    //  - An email with an existing User already registered -> blocked.
    //  - An email matching an existing Contact with no User yet (e.g. created
    //    by an admin in Salesforce directly) -> that real Contact/Account is
    //    reused for the new login instead of creating a duplicate.
    //  - No match at all -> a new Account + Contact is created.
    @AuraEnabled
    public static void registerUser(RegistrationInput input) {

        if (
            String.isBlank(input.email) ||
            String.isBlank(input.password) ||
            String.isBlank(input.lastName)
        ) {
            throw new AuraHandledException('Please fill in all required fields.');
        }

        if (input.password.length() < 8) {
            throw new AuraHandledException('Password must be at least 8 characters.');
        }

        if (![SELECT Id FROM User WHERE Username = :input.email LIMIT 1].isEmpty()) {
            throw new AuraHandledException(
                'An account with this email already exists. Please log in instead.'
            );
        }

        List<Contact> existingContacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = :input.email
            LIMIT 1
        ];

        Id accountId;
        Id contactId;

        if (!existingContacts.isEmpty()) {
            contactId = existingContacts[0].Id;
            accountId = existingContacts[0].AccountId;
        } else {
            Account acc = new Account(Name = input.lastName + ' Household');
            insert acc;

            Contact con = new Contact(
                FirstName = input.firstName,
                LastName = input.lastName,
                Email = input.email,
                Phone = input.phone,
                AccountId = acc.Id
            );
            insert con;

            accountId = acc.Id;
            contactId = con.Id;
        }

        User newUser = new User();
        newUser.Username = input.email;
        newUser.Email = input.email;
        newUser.FirstName = input.firstName;
        newUser.LastName = input.lastName;
        newUser.Alias = generateAlias(input.firstName, input.lastName);
        newUser.CommunityNickname = generateNickname(input.email);
        newUser.ProfileId = CUSTOMER_PROFILE_ID;
        newUser.ContactId = contactId;
        newUser.TimeZoneSidKey = 'Asia/Kolkata';
        newUser.LocaleSidKey = 'en_US';
        newUser.EmailEncodingKey = 'UTF-8';
        newUser.LanguageLocaleKey = 'en_US';

        try {
            Site.createExternalUser(newUser, accountId, input.password, false);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create your account: ' + e.getMessage());
        }

        if (newUser.Id == null) {
            throw new AuraHandledException('Unable to create your account. Please try again.');
        }

        try {
            System.setPassword(newUser.Id, input.password);
        } catch (Exception e) {
            // User was created — password set failed. Non-fatal: user can reset via email.
        }
    }


    // Alias must be 8 characters or fewer and unique-ish; derived from the name.
    private static String generateAlias(String firstName, String lastName) {
        String base = ((firstName == null ? '' : firstName) + (lastName == null ? '' : lastName));
        base = base.replaceAll('[^a-zA-Z0-9]', '');
        if (String.isBlank(base)) {
            base = 'user';
        }
        String alias = base.length() > 5 ? base.substring(0, 5) : base;
        alias += String.valueOf(Math.mod(Crypto.getRandomInteger(), 1000));
        return alias.length() > 8 ? alias.substring(0, 8) : alias;
    }


    // CommunityNickname must be unique per site; derived from the email plus a
    // random suffix to avoid collisions between similar addresses.
    private static String generateNickname(String email) {
        String base = email.substringBefore('@').replaceAll('[^a-zA-Z0-9]', '');
        if (String.isBlank(base)) {
            base = 'user';
        }
        return base + String.valueOf(Math.mod(Crypto.getRandomInteger(), 100000));
    }


    // Sign-up form payload from the LWC.
    public class RegistrationInput {

        @AuraEnabled
        public String firstName;

        @AuraEnabled
        public String lastName;

        @AuraEnabled
        public String email;

        @AuraEnabled
        public String phone;

        @AuraEnabled
        public String password;
    }
}
