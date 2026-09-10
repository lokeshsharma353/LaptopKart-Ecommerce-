/**
 * An apex page controller that exposes the change password functionality.
 * Salesforce's standard Sites/Communities boilerplate for native Salesforce
 * logins — NOT part of the custom LaptopKart storefront login system (see
 * LoginCredentialsController for that).
 */
public with sharing class ChangePasswordController {
    public String oldPassword {get; set;}
    public String newPassword {get; set;}
    public String verifyNewPassword {get; set;}

    /** Attempts the password change via Site.changePassword() using the three fields above. */
    public PageReference changePassword() {
        return Site.changePassword(newPassword, verifyNewPassword, oldpassword);
    }
    
   	public ChangePasswordController() {}
}