// without sharing: see OrderService — same trigger-chain sharing gap,
// this time for the Payment__c trigger fired by CheckoutController's
// Payment insert.
public without sharing class PaymentTriggerHandler {

    /** Marks Payment__c records Successful/Failed and validates them via PaymentService. */
    public static void validatePayments(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {

        PaymentService.validateSuccessfulPayments(
            newPayments,
            oldPaymentMap
        );
    }


    /** Recalculates Order totals and sends the customer the appropriate payment-status email. */
    public static void handleAfterInsertOrUpdate(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {

        PaymentService.calculateOrderPayments(
            newPayments,
            oldPaymentMap
        );

        PaymentService.sendPaymentConfirmationEmails(
            newPayments,
            oldPaymentMap
        );
        PaymentService.sendPaymentIssueEmails(
            newPayments,
            oldPaymentMap
        );
    }
}
