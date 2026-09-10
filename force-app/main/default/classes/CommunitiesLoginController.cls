/**
 * An apex page controller that exposes the site login functionality.
 * Salesforce's standard Experience Cloud boilerplate — NOT part of the
 * custom LaptopKart storefront login system (see LoginCredentialsController
 * for that).
 */
global with sharing class CommunitiesLoginController {

    global CommunitiesLoginController () {}

    /** Forwards the visitor to the community's configured auth/login page on page load. */
    global PageReference forwardToAuthPage() {
    	String startUrl = System.currentPageReference().getParameters().get('startURL');
    	String displayType = System.currentPageReference().getParameters().get('display');
        return Network.forwardToAuthPage(startUrl, displayType);
    }
}