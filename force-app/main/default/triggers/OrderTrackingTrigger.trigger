trigger OrderTrackingTrigger on Order_Tracking__c (after update) {

    // Send updated tracking records to the Handler.
    // Delivery-status email logic stays outside the trigger.
    OrderTrackingTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}
