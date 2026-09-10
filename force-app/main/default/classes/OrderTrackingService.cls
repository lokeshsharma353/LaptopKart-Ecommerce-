// without sharing: see OrderService — same trigger-chain sharing gap,
// this time for Order_Tracking__c queried/created off the Order.
public without sharing class OrderTrackingService {

    /** Creates an Order_Tracking__c (status 'Pending') when an Order is activated, or marks it 'Cancelled' when the Order is cancelled. */
    public static void handleStatusChanges(
        List<Order> newOrders,
        Map<Id, Order> oldOrderMap
    ) {

        // Store Orders whose status changed as required.
        // Sets prevent duplicate Order IDs.
        Set<Id> activatedOrderIds = new Set<Id>();
        Set<Id> cancelledOrderIds = new Set<Id>();

        for (Order newOrder : newOrders) {

            Order oldOrder = oldOrderMap.get(newOrder.Id);

            // Detect Draft → Activated.
            if (
                oldOrder.Status == 'Draft' &&
                newOrder.Status == 'Activated'
            ) {
                activatedOrderIds.add(newOrder.Id);
            }

            // Detect Activated → Cancelled.
            if (
                oldOrder.Status == 'Activated' &&
                newOrder.Status == 'Cancelled'
            ) {
                cancelledOrderIds.add(newOrder.Id);
            }
        }

        // Stop if no required status changes occurred.
        if (
            activatedOrderIds.isEmpty() &&
            cancelledOrderIds.isEmpty()
        ) {
            return;
        }


        // Get existing tracking records.
        // Used to prevent duplicate tracking records.
        Set<Id> allOrderIds = new Set<Id>();
        allOrderIds.addAll(activatedOrderIds);
        allOrderIds.addAll(cancelledOrderIds);

        Map<Id, Order_Tracking__c> trackingByOrder =
            new Map<Id, Order_Tracking__c>();

        for (Order_Tracking__c tracking : [
            SELECT Id,
                   Order__c,
                   Delivery_Status__c
            FROM Order_Tracking__c
            WHERE Order__c IN :allOrderIds
            WITH SYSTEM_MODE
        ]) {

            trackingByOrder.put(
                tracking.Order__c,
                tracking
            );
        }


        List<Order_Tracking__c> trackingToCreate =
            new List<Order_Tracking__c>();

        List<Order_Tracking__c> trackingToUpdate =
            new List<Order_Tracking__c>();


        // Create tracking for newly Activated Orders.
        // Do nothing if a tracking record already exists.
        for (Id orderId : activatedOrderIds) {

            if (!trackingByOrder.containsKey(orderId)) {

                Order_Tracking__c tracking =
                    new Order_Tracking__c();

                tracking.Order__c = orderId;
                tracking.Delivery_Status__c = 'Pending';
                // See OrderService for why this is forced explicitly rather
                // than left to default under AccessLevel.SYSTEM_MODE.
                tracking.OwnerId = UserInfo.getUserId();

                trackingToCreate.add(tracking);
            }
        }


        // Update existing tracking when Order is Cancelled.
        // Delivery Status becomes Cancelled.
        for (Id orderId : cancelledOrderIds) {

            if (trackingByOrder.containsKey(orderId)) {

                Order_Tracking__c tracking =
                    trackingByOrder.get(orderId);

                tracking.Delivery_Status__c = 'Cancelled';

                trackingToUpdate.add(tracking);
            }
        }


        // Create all tracking records in one DML operation.
        // No DML is performed inside the loop.
        // AccessLevel.SYSTEM_MODE — see OrderService for why: this can run as
        // an Experience Cloud Guest User, which is denied cross-reference
        // access to the parent Order otherwise. Strictly widens access, so it
        // doesn't change behavior for any other caller of this class.
        if (!trackingToCreate.isEmpty()) {
            Database.insert(trackingToCreate, AccessLevel.SYSTEM_MODE);
        }

        // Update all tracking records in one DML operation.
        // Keeps the implementation bulkified.
        if (!trackingToUpdate.isEmpty()) {
            Database.update(trackingToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }
}