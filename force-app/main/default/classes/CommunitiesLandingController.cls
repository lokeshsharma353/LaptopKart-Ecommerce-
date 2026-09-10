/**
 * An apex page controller that takes the user to the right start page based
 * on credentials or lack thereof. Salesforce's standard Experience Cloud
 * boilerplate — not part of the custom LaptopKart storefront.
 */
public with sharing class CommunitiesLandingController {

    /** Forwards to the community's real landing page (login or home) on page load. */
    public PageReference forwardToStartPage() {
        return Network.communitiesLanding();
    }
    
    public CommunitiesLandingController() {}
}