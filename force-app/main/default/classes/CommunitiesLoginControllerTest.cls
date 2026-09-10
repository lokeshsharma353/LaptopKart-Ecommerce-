// Standard Salesforce test stub for CommunitiesLoginController (the
// boilerplate auth-forwarding controller, not the custom LaptopKart login).
@IsTest global with sharing class CommunitiesLoginControllerTest {
    @IsTest(SeeAllData=true) 
    global static void testCommunitiesLoginController () {
     	CommunitiesLoginController controller = new CommunitiesLoginController();
     	System.assertEquals(null, controller.forwardToAuthPage());       
    }    
}