/**
 * An apex page controller that exposes the site login functionality.
 * Salesforce's standard Sites boilerplate for native Salesforce logins —
 * NOT part of the custom LaptopKart storefront login system (see
 * LoginCredentialsController for that).
 */
global with sharing class SiteLoginController {
    global String username {get; set;}
    global String password {get; set;}

    /** Attempts a native Salesforce Site login with the username/password fields, redirecting to startURL on success. */
    global PageReference login() {
        String startUrl = System.currentPageReference().getParameters().get('startURL');
        return Site.login(username, password, startUrl);
    }

   	global SiteLoginController () {}
}