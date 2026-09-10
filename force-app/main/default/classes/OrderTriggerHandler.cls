// without sharing: same reasoning as OrderService — this runs inside
// OrderTrigger, fired by CheckoutController's Order activation update, and
// needs to see the just-activated (or just-created) Order/tracking records
// for a real Guest checkout regardless of whether the criteria-based Guest
// Sharing Rule has recalculated yet within this transaction.
public without sharing class OrderTriggerHandler {

    /** Passes updated Orders to OrderTrackingService to create/update their Order_Tracking__c record. */
    public static void handleAfterUpdate(
        List<Order> newOrders,
        Map<Id, Order> oldOrderMap
    ) {

        OrderTrackingService.handleStatusChanges(
            newOrders,
            oldOrderMap
        );
    }
}