// Duplicate of ContactSharing.cls (earlier practice attempt at the same
// thing) — not referenced anywhere, and unusable for the same reason: see
// ContactSharing's class comment.
public class contactSharingClass {
    /** Grants one User Read access to one Contact via a manual ContactShare row. Currently unusable — see class comment. */
    public static void shareContactWithUser(Id ContactId, Id UserId) {

        ContactShare cs = new ContactShare();
        cs.ContactId = ContactId;  //'003bm00001kEQpHAAW'
        cs.UserOrGroupId = UserId; //'005bm00000UGI4XAAX'
        cs.ContactAccessLevel = 'Read';
        cs.RowCause = Schema.ContactShare.RowCause.Manual;

        insert cs;
    }
}