// Salesforce's standard Experience Cloud boilerplate for asynchronous
// self-registration (creates the user via a background micro-batch job
// instead of synchronously) — NOT part of the custom LaptopKart storefront
// login system (see LoginCredentialsController for that). accountName/
// contactName/profileId below are placeholders and would need filling in.
public class MicrobatchSelfRegController {
    public String firstName {get; set;}
    public String lastName {get; set;}
    public String email {get; set;}
    public String communityNickname {get; set { communityNickname = value == null ? value : value.trim(); } }

    /** Reads the ?expid= URL parameter (which Experience Cloud site this registration is for) and sets it on Site. */
    public MicrobatchSelfRegController() {
        String expid = ApexPages.currentPage().getParameters().get('expid');
        if (expId != null) {
            Site.setExperienceId(expId);
        }
    }

    /** Queues an async external-user creation job and redirects to the self-reg confirmation page once queued. */
    public PageReference registerUser() {
        String userName = email;
        String accountName; // to be filled by customer
        String contactName; //to be filled by customer
        String profileId = null; //to be filled by customer
        String UUID;

        User u = new User();
        u.Username = userName;
        u.Email = email;
        u.FirstName = firstName;
        u.LastName = lastName;
        u.CommunityNickname = communityNickname;
        u.ProfileId = profileId;
        u.LocaleSidKey = 'en_US';
        u.TimeZoneSidKey = 'GMT';
        u.LanguageLocaleKey = 'en_US';
        u.EmailEncodingKey = 'UTF-8';

        Account acc = new Account();
        acc.Name = 'Account for ' + lastName;
        Contact c = new Contact();
        c.lastName = lastName;

        try {
            UUID =  Network.createExternalUserAsync(u, c,acc);
        } catch(Site.ExternalUserCreateException ex) {
            List<String> errors = ex.getDisplayMessages();
            for (String error : errors)  {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, error));
            }

            // This message is used for debugging. Do not display this in the UI to the end user.
            // It has the information around why the user creation failed.
            System.debug(ex.getMessage());
        }
        if (UUID != null) {
           PageReference page = System.Page.CommunitiesSelfRegConfirm;
           page.setRedirect(true);
           return page;
        }
        return null;
    }
}