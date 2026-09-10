/**
 * An apex page controller that exposes the site forgot password functionality.
 * Salesforce's standard Sites/Communities boilerplate for native Salesforce
 * logins — NOT part of the custom LaptopKart storefront login system (whose
 * own forgot-password flow is LoginCredentialsController.requestPasswordReset,
 * which creates a Task instead of using this Site.forgotPassword() email flow).
 */
public with sharing class ForgotPasswordController {
    public String username {get; set;}

    public ForgotPasswordController() {}

    /** Triggers Salesforce's built-in forgot-password email via Site.forgotPassword(), then redirects to the confirmation page. */
  	public PageReference forgotPassword() {
  		boolean success = Site.forgotPassword(username);
  		PageReference pr = Page.ForgotPasswordConfirm;
  		pr.setRedirect(true);
  		
  		if (success) {  			
  			return pr;
  		}
  		return null;
  	}
}