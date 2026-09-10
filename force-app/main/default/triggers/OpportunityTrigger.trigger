trigger OpportunityTrigger on Opportunity(after update) {


		// OpprtunityClosedWonHandler.updateAccountDetails(Trigger.New,Trigger.oldMap);
OpportunityTriggerHandler.handleAfterUpdate(
    Trigger.new,
    Trigger.oldMap
);

	
}