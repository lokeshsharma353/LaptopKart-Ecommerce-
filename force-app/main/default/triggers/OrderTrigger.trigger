trigger OrderTrigger on Order (after update) {

    // Send updated Orders to the Handler.
    // Tracking logic stays outside the trigger.
    OrderTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
        
    );
}