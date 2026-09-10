// Backs the internal Order Payment Dashboard Lightning page (not the public
// storefront) — read-only order/payment lookups for an internal user.
public with sharing class OrderPaymentController {

    /** Returns one Order's dashboard summary: account name, totals, status, and its tracking info if any exists. */
    @AuraEnabled(cacheable=true)
    public static OrderDetails getOrderDetails(Id orderId) {

        Order ord = [
            SELECT Id,
                   OrderNumber,
                   Account.Name,
                   TotalAmount,
                   Total_Paid__c,
                   Payment_Status__c,
                   Status,
                   CreatedDate
            FROM Order
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
        ];


        OrderDetails result = new OrderDetails();

        result.orderNumber = ord.OrderNumber;

        if (ord.Account != null) {
            result.accountName = ord.Account.Name;
        }

        result.orderAmount = ord.TotalAmount;

        result.totalPaid =
            ord.Total_Paid__c == null
                ? 0
                : ord.Total_Paid__c;

        result.paymentStatus =
            ord.Payment_Status__c;

        result.orderStatus = ord.Status;
        result.orderDate = ord.CreatedDate.date();

        // Order_Tracking__c is a separate object (created by the existing
        // OrderTrigger -> OrderTrackingService automation) — not every Order
        // necessarily has one yet, so this is a best-effort lookup.
        List<Order_Tracking__c> trackings = [
            SELECT Tracking_NUmber__c, Delivery_Status__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c = :orderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!trackings.isEmpty()) {
            result.deliveryStatus = trackings[0].Delivery_Status__c;
            result.trackingNumber = trackings[0].Tracking_NUmber__c;
            result.estimatedDelivery = trackings[0].Delivery_Date__c;
        }

        return result;
    }


    /** Returns every Payment__c linked to one Order, most recent first. */
    @AuraEnabled(cacheable=true)
    public static List<PaymentDetails> getPayments(
        Id orderId
    ) {

        List<PaymentDetails> results =
            new List<PaymentDetails>();

        for (Payment__c payment : [
            SELECT Id,
                   Name,
                   Amount__c,
                   Payment_Date__c,
                   Payment_Status__c,
                   Payment_Method__c,
                   Transaction_ID__c
            FROM Payment__c
            WHERE Order__c = :orderId
            WITH USER_MODE
            ORDER BY Payment_Date__c DESC
        ]) {

            PaymentDetails result =
                new PaymentDetails();

            result.id = payment.Id;
            result.paymentNumber = payment.Name;
            result.amount = payment.Amount__c;
            result.paymentDate = payment.Payment_Date__c;
            result.status = payment.Payment_Status__c;
            result.method = payment.Payment_Method__c;
            result.transactionId = payment.Transaction_ID__c;

            results.add(result);
        }

        return results;
    }


    // Dashboard Order data returned to the LWC.
    public class OrderDetails {

        @AuraEnabled
        public String orderNumber;

        @AuraEnabled
        public String accountName;

        @AuraEnabled
        public Decimal orderAmount;

        @AuraEnabled
        public Decimal totalPaid;

        @AuraEnabled
        public String paymentStatus;

        @AuraEnabled
        public String orderStatus;

        @AuraEnabled
        public Date orderDate;

        @AuraEnabled
        public String deliveryStatus;

        @AuraEnabled
        public String trackingNumber;

        @AuraEnabled
        public Date estimatedDelivery;
    }


    // Dashboard Payment data returned to the LWC.
    public class PaymentDetails {

        @AuraEnabled
        public Id id;

        @AuraEnabled
        public String paymentNumber;

        @AuraEnabled
        public Decimal amount;

        @AuraEnabled
        public Date paymentDate;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String method;

        @AuraEnabled
        public String transactionId;
    }
}
