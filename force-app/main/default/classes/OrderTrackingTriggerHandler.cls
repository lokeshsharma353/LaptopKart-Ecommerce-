// without sharing: see OrderService — same trigger-chain sharing gap, this
// time for Order_Tracking__c updated directly by an admin (Shipped / Out
// for Delivery / Delivered / Cancelled), not created off an Order change.
public without sharing class OrderTrackingTriggerHandler {

    /** Sends the customer a delivery-status email, awards loyalty points on delivery, and processes refund/reversal when an admin moves Delivery_Status__c forward. */
    public static void handleAfterUpdate(
        List<Order_Tracking__c> newTrackings,
        Map<Id, Order_Tracking__c> oldTrackingMap
    ) {
        OrderTrackingService.sendDeliveryStatusEmails(newTrackings, oldTrackingMap);
        OrderTrackingService.awardLoyaltyPointsOnDelivery(newTrackings, oldTrackingMap);
        OrderTrackingService.processReturnedOrders(newTrackings, oldTrackingMap);
    }
}
