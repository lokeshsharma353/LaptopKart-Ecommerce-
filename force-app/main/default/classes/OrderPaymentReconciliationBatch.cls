// Scheduled nightly (see OrderPaymentReconciliationScheduler) to recheck
// every not-fully-paid Activated Order and refresh its Total_Paid__c /
// Payment_Status__c from actual Successful Payment__c records — a safety
// net in case the real-time PaymentTriggerHandler update was ever missed.
public class OrderPaymentReconciliationBatch
    implements Database.Batchable<SObject> {

    // Find Activated Orders that are not fully paid.
    // These Orders need payment reconciliation.
    public Database.QueryLocator start(
        Database.BatchableContext bc
    ) {

        return Database.getQueryLocator([
            SELECT Id, TotalAmount, Total_Paid__c, Payment_Status__c
            FROM Order
            WHERE Status = 'Activated'
            AND Payment_Status__c != 'Fully Paid'
        ]);
    }


    // Recalculate successful Payments for the Orders in this batch.
    // AggregateResult handles multiple Payments per Order.
    public void execute(
        Database.BatchableContext bc,
        List<Order> orders
    ) {

        Set<Id> orderIds = new Set<Id>();

        // Collect Order IDs from the current batch scope.
        // Set prevents duplicate Order IDs.
        for (Order ord : orders) {
            orderIds.add(ord.Id);
        }


        // Calculate successful Payment totals by Order.
        // One aggregate query handles all Orders in the scope.
        Map<Id, Decimal> paymentTotals =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Order__c OrderId,
                   SUM(Amount__c) TotalPaid
            FROM Payment__c
            WHERE Order__c IN :orderIds
            AND Payment_Status__c = 'Successful'
            GROUP BY Order__c
        ]) {

            Id orderId =
                (Id) result.get('OrderId');

            Decimal totalPaid =
                (Decimal) result.get('TotalPaid');

            paymentTotals.put(
                orderId,
                totalPaid
            );
        }


        List<Order> ordersToUpdate =
            new List<Order>();

        // Recalculate each Order's payment values.
        // Only the required Order fields are updated.
        for (Order ord : orders) {

            Decimal totalPaid = 0;

            if (paymentTotals.containsKey(ord.Id)) {
                totalPaid = paymentTotals.get(ord.Id);
            }

            Order orderToUpdate =
                new Order(Id = ord.Id);

            orderToUpdate.Total_Paid__c =
                totalPaid;


            // Set Payment Status according to total successful payments.
            // Values are Unpaid, Partially Paid, or Fully Paid.
            if (totalPaid == 0) {

                orderToUpdate.Payment_Status__c =
                    'Unpaid';

            } else if (totalPaid < ord.TotalAmount) {

                orderToUpdate.Payment_Status__c =
                    'Partially Paid';

            } else if (totalPaid == ord.TotalAmount) {

                orderToUpdate.Payment_Status__c =
                    'Fully Paid';
            }

            ordersToUpdate.add(orderToUpdate);
        }


        // Update all Orders in one DML operation.
        // No DML is performed inside the loop.
        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }


    // Runs after the batch finishes.
    // No additional processing is required by the requirement.
    public void finish(
        Database.BatchableContext bc
    ) {
    }
}