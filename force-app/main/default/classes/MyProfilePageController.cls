/**
 * An apex class that updates portal user details.
   Guest users are never able to access this page.
 */
public with sharing class MyProfilePageController {

    private User user;
    private boolean isEdit = false;

    /** The logged-in portal user's own record, as loaded/reloaded by the constructor or cancel(). */
    public User getUser() {
        return user;
    }

    /** Loads the current user's profile fields; blocks Guest users from ever reaching this page. */
    public MyProfilePageController() {
        user = [SELECT id, email, username, usertype, communitynickname, timezonesidkey, languagelocalekey, firstname, lastname, phone, title,
                street, city, country, postalcode, state, localesidkey, mobilephone, extension, fax, contact.email
                FROM User
                WHERE id = :UserInfo.getUserId()];
        // guest users should never be able to access this page
        if (user.usertype == 'GUEST') {
            throw new NoAccessException();
        }
    }

    /** True while the profile form is in edit mode (fields become editable in the page). */
    public Boolean getIsEdit() {
        return isEdit;
    }

    /** Switches the page into edit mode. */
    public void edit() {
        isEdit=true;
    }

    /** Saves the edited User fields and exits edit mode; validation errors are shown on the page. */
    public void save() {
        try {
            update user;
            isEdit=false;
        } catch(DmlException e) {
            ApexPages.addMessages(e);
        }
    }

    /** Navigates to the Change Password Visualforce page. */
    public PageReference changePassword() {
        return Page.ChangePassword;
    }

    /** Discards any unsaved edits by re-loading the User record fresh, and exits edit mode. */
    public void cancel() {
        isEdit=false;
        user = [SELECT id, email, username, communitynickname, timezonesidkey, languagelocalekey, firstname, lastname, phone, title,
                street, city, country, postalcode, state, localesidkey, mobilephone, extension, fax, contact.email
                FROM User
                WHERE id = :UserInfo.getUserId()];
    }
}