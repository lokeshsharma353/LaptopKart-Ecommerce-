trigger Product2Trigger on Product2 (after update) {

    // Send updated products to the Handler.
    // Stock-movement ledger logic stays outside the trigger.
    Product2TriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}
