// Standard Salesforce test stub for ForgotPasswordController (the
// boilerplate forgot-password controller, not the custom LaptopKart one —
// see LoginCredentialsControllerTest for that).
@IsTest public with sharing class ForgotPasswordControllerTest {
  	 @IsTest(SeeAllData=true) public static void testForgotPasswordController() {
    	// Instantiate a new controller with all parameters in the page
    	ForgotPasswordController controller = new ForgotPasswordController();
    	controller.username = 'test@salesforce.com';     	
    
    	System.assertEquals(controller.forgotPassword(),null); 
    }
}