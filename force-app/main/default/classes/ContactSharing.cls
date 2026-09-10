// Not referenced anywhere in the app, and not currently deployable: it
// inserts a ContactShare row, which Salesforce only allows when Contact's
// org-wide default sharing is Private — this org's isn't, so this throws
// "Field is not writeable" if ever called or redeployed.
public class ContactSharing {

    /** Grants one User Read access to one Contact via a manual ContactShare row. Currently unusable — see class comment. */
    public static void shareContactWithUser(Id contactId, Id userId) {

        ContactShare cs = new ContactShare();

        cs.ContactId = contactId;
        cs.UserOrGroupId = userId;
        cs.ContactAccessLevel = 'Read';
        cs.RowCause = Schema.ContactShare.RowCause.Manual;

        insert cs;
    }
}