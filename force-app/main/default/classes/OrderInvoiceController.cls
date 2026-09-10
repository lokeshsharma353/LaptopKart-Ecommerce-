// without sharing + WITH SYSTEM_MODE: this backs a Visualforce page rendered
// as a PDF for the Guest User (invoice download button, and the automatic
// invoice attached to the order-confirmation email in CheckoutController).
// Same reasoning as OrderService/PaymentService — sharing rule
// recalculation isn't guaranteed to have caught up yet for a record from
// the same checkout transaction, and PDF rendering must not fail because of
// that timing gap.
public without sharing class OrderInvoiceController {

    public Id orderId { get; private set; }
    public Order ord { get; private set; }
    public List<OrderItemView> lineItems { get; private set; }
    public Payment__c payment { get; private set; }
    public Order_Tracking__c tracking { get; private set; }
    public Contact customerContact { get; private set; }

    public OrderInvoiceController() {
        orderId = ApexPages.currentPage().getParameters().get('orderId');

        if (orderId == null) {
            return;
        }

        List<Order> orders = [
            SELECT Id, OrderNumber, CreatedDate, Status, TotalAmount, Total_Paid__c,
                   Payment_Status__c, ShippingStreet, ShippingCity, ShippingState,
                   ShippingPostalCode, ShippingCountry, AccountId, Account.Name
            FROM Order
            WHERE Id = :orderId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            return;
        }
        ord = orders[0];

        // The Account's own Name is the internal Lead-conversion "Company"
        // value (e.g. "John Doe (TechBasket Customer)") — not something a
        // real invoice should show as the customer's name. The Contact
        // created alongside it has the shopper's actual name and phone.
        if (ord.AccountId != null) {
            List<Contact> contacts = [
                SELECT Name, Phone, Email
                FROM Contact
                WHERE AccountId = :ord.AccountId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                customerContact = contacts[0];
            }
        }

        lineItems = new List<OrderItemView>();
        for (OrderItem item : [
            SELECT Product2.Name, Product2.ProductCode, Quantity, UnitPrice, TotalPrice
            FROM OrderItem
            WHERE OrderId = :orderId
            WITH SYSTEM_MODE
        ]) {
            OrderItemView view = new OrderItemView();
            view.productName = item.Product2.Name;
            view.productCode = item.Product2.ProductCode;
            view.quantity = item.Quantity;
            view.unitPrice = item.UnitPrice;
            view.totalPrice = item.TotalPrice;
            lineItems.add(view);
        }

        List<Payment__c> payments = [
            SELECT Payment_Method__c, Transaction_ID__c, Payment_Date__c, Payment_Status__c
            FROM Payment__c
            WHERE Order__c = :orderId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!payments.isEmpty()) {
            payment = payments[0];
        }

        List<Order_Tracking__c> trackings = [
            SELECT Tracking_NUmber__c, Delivery_Status__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c = :orderId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!trackings.isEmpty()) {
            tracking = trackings[0];
        }
    }

    /** True when a real Order was found for the ?orderId= page parameter — the VF page shows the invoice only when this is true. */
    public Boolean getHasOrder() {
        return ord != null;
    }

    // Real customer-facing name — falls back to the Account name only if,
    // for some reason, no Contact was found.
    public String getCustomerName() {
        if (customerContact != null && String.isNotBlank(customerContact.Name)) {
            return customerContact.Name;
        }
        return ord.Account != null ? ord.Account.Name : '';
    }

    /** The Order's shipping address, formatted as one display line. */
    public String getShippingAddress() {
        List<String> parts = new List<String>();
        if (String.isNotBlank(ord.ShippingStreet)) parts.add(ord.ShippingStreet);
        if (String.isNotBlank(ord.ShippingCity)) parts.add(ord.ShippingCity);
        if (String.isNotBlank(ord.ShippingState)) parts.add(ord.ShippingState);
        if (String.isNotBlank(ord.ShippingPostalCode)) parts.add(ord.ShippingPostalCode);
        if (String.isNotBlank(ord.ShippingCountry)) parts.add(ord.ShippingCountry);
        return String.join(parts, ', ');
    }

    /** The date this invoice is being viewed/generated (today), shown at the top of the invoice. */
    public Date getInvoiceDate() {
        return ord.CreatedDate.date();
    }

    /** Order total minus what's actually been paid so far. */
    public Decimal getBalanceDue() {
        Decimal paid = ord.Total_Paid__c == null ? 0 : ord.Total_Paid__c;
        Decimal total = ord.TotalAmount == null ? 0 : ord.TotalAmount;
        return total - paid;
    }

    // True when this order is being paid for in cash at delivery — the
    // invoice must never show a generated "Transaction ID" for this method,
    // since no electronic transaction actually happened yet.
    public Boolean getIsCashOnDelivery() {
        return payment != null && payment.Payment_Method__c == 'Cash';
    }

    /** True when this order was paid Online (as opposed to Cash on Delivery). */
    public Boolean getIsOnlinePayment() {
        return payment != null && !getIsCashOnDelivery();
    }

    // Friendly label for payment.Payment_Status__c ('Pending' until an
    // admin manually confirms it — see PaymentService — 'Successful' once
    // they have).
    public String getPaymentStatusLabel() {
        if (payment == null || String.isBlank(payment.Payment_Status__c)) {
            return 'Pending';
        }
        if (payment.Payment_Status__c == 'Successful') {
            return 'Paid';
        }
        if (payment.Payment_Status__c == 'Pending') {
            return 'Pending Confirmation';
        }
        return payment.Payment_Status__c;
    }

    // View model for one invoice line — Apex property access in Visualforce
    // can't reach into a query's parent-relationship fields the same way a
    // flat class can, so OrderItem is flattened into this on construction.
    public class OrderItemView {
        public String productName { get; set; }
        public String productCode { get; set; }
        public Decimal quantity { get; set; }
        public Decimal unitPrice { get; set; }
        public Decimal totalPrice { get; set; }
    }
}
