trigger PaymentTrigger on Payment__c (
    before insert,
    before update,
    after insert,
    after update
) {

    // Validate successful payments before saving.
    // Prevent total payment from exceeding Order Amount.
    if (Trigger.isBefore) {

        PaymentTriggerHandler.validatePayments(
            Trigger.new,
            Trigger.oldMap
        );
    }

    // Recalculate Order payment totals after saving.
    // Updates Total Paid and Payment Status on Order.
    if (Trigger.isAfter) {

        PaymentTriggerHandler.handleAfterInsertOrUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}