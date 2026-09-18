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

        // Release any coupon/loyalty-point redemption tied to an order that
        // was just cancelled before fulfillment — see Feature Expansion Plan
        // §1.6/§2.6 Case 1. Only ever runs for genuinely cancelled orders
        // (this method already scoped cancelledOrderIds to Activated ->
        // Cancelled above), so a Draft order that never redeemed anything
        // costs nothing extra here.
        if (!cancelledOrderIds.isEmpty()) {
            releaseRedemptionsForCancelledOrders(cancelledOrderIds);
        }
    }

    /** Restores loyalty points, releases the coupon slot, and restores stock for each just-cancelled order, best-effort. See §1.6/§2.6/§12. */
    private static void releaseRedemptionsForCancelledOrders(Set<Id> cancelledOrderIds) {
        for (Order ord : [
            SELECT Id, Points_Redeemed__c, Placed_By__c, AccountId
            FROM Order
            WHERE Id IN :cancelledOrderIds
            WITH SYSTEM_MODE
        ]) {
            DiscountService.releaseRedemptionForCancelledOrder(ord.Id);

            if (ord.Points_Redeemed__c != null && ord.Points_Redeemed__c > 0) {
                Id customerAccountId = ord.Placed_By__c != null ? ord.Placed_By__c : ord.AccountId;
                LoyaltyService.restoreRedeemedPoints(customerAccountId, ord.Points_Redeemed__c.intValue(), ord.Id);
            }
        }
        // Restores each order's purchased quantities back to
        // Product2.Stock_Quantity__c and logs a 'Cancellation'
        // Stock_Movement__c row per product — see InventoryService, the
        // single place every stock-changing event in the app now goes
        // through (mirrors the "Inventory & Vendor System" design).
        InventoryService.restoreStockForOrders(cancelledOrderIds);
    }

    /**
     * Handles an order being marked Returned (via requestReturn's flow —
     * see CheckoutController — followed by an admin setting Delivery_Status__c
     * to 'Returned' once the returned product is received): refunds the
     * order's most recent Successful payment, restores stock, releases the
     * coupon slot, restores any redeemed points, and reverses any points
     * already earned on delivery — proportional-to-the-order since this is a
     * full-order return, not a partial one. See Feature Expansion Plan §14.
     */
    public static void processReturnedOrders(
        List<Order_Tracking__c> newTrackings,
        Map<Id, Order_Tracking__c> oldTrackingMap
    ) {
        Set<Id> orderIdsToProcess = new Set<Id>();

        for (Order_Tracking__c tracking : newTrackings) {
            Order_Tracking__c oldTracking = (oldTrackingMap == null) ? null : oldTrackingMap.get(tracking.Id);
            Boolean justReturned =
                oldTracking != null &&
                oldTracking.Delivery_Status__c != 'Returned' &&
                tracking.Delivery_Status__c == 'Returned';

            if (justReturned && tracking.Order__c != null) {
                orderIdsToProcess.add(tracking.Order__c);
            }
        }

        if (orderIdsToProcess.isEmpty()) {
            return;
        }

        Map<Id, Order> orders = new Map<Id, Order>([
            SELECT Id, Points_Redeemed__c, Points_Earned__c, Placed_By__c, AccountId
            FROM Order
            WHERE Id IN :orderIdsToProcess
            WITH SYSTEM_MODE
        ]);

        // Refund the most recent Successful payment per order — same
        // "one relevant payment per order" pattern CheckoutController's
        // getOrders already uses for display.
        Map<Id, Payment__c> paymentToRefundByOrder = new Map<Id, Payment__c>();
        for (Payment__c payment : [
            SELECT Id, Order__c, Payment_Status__c
            FROM Payment__c
            WHERE Order__c IN :orderIdsToProcess
            AND Payment_Status__c = 'Successful'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!paymentToRefundByOrder.containsKey(payment.Order__c)) {
                paymentToRefundByOrder.put(payment.Order__c, payment);
            }
        }
        if (!paymentToRefundByOrder.isEmpty()) {
            List<Payment__c> toRefund = new List<Payment__c>();
            for (Payment__c payment : paymentToRefundByOrder.values()) {
                toRefund.add(new Payment__c(Id = payment.Id, Payment_Status__c = 'Refunded'));
            }
            // Triggers PaymentTriggerHandler -> PaymentService.sendPaymentIssueEmails,
            // which already sends the customer a "Payment Refunded" email —
            // no separate email needed here.
            Database.update(toRefund, AccessLevel.SYSTEM_MODE);
        }

        for (Order ord : orders.values()) {
            Id customerAccountId = ord.Placed_By__c != null ? ord.Placed_By__c : ord.AccountId;

            DiscountService.releaseRedemptionForCancelledOrder(ord.Id);

            if (ord.Points_Redeemed__c != null && ord.Points_Redeemed__c > 0) {
                LoyaltyService.restoreRedeemedPoints(customerAccountId, ord.Points_Redeemed__c.intValue(), ord.Id);
            }
            // Reverses points already earned when this order was delivered
            // (§2.6 Case 2: "reverse the points associated with the
            // refunded eligible amount" — a full return reverses all of it).
            if (ord.Points_Earned__c != null && ord.Points_Earned__c > 0) {
                LoyaltyService.reverseEarnedPoints(customerAccountId, ord.Points_Earned__c.intValue(), ord.Id);
            }
        }

        InventoryService.restoreStockForOrders(orderIdsToProcess);
    }

    // The four Delivery_Status__c values worth emailing the customer about.
    // 'Pending' is deliberately excluded — that's the record's starting
    // state, already covered by CheckoutController's own "order received"
    // email, not a status an admin ever transitions INTO.
    private static final Set<String> NOTIFY_STATUSES = new Set<String>{
        'Shipped', 'Out for Delivery', 'Delivered', 'Cancelled', 'Return Requested', 'Returned'
    };

    /**
     * Sends the customer a status-update email every time an admin moves
     * Delivery_Status__c forward (Shipped / Out for Delivery / Delivered /
     * Cancelled) — the same real-e-commerce lifecycle notifications
     * CheckoutController (order placed) and PaymentService (payment
     * confirmed) already cover for the earlier steps. Only fires on an
     * actual change into one of the NOTIFY_STATUSES values — saving the
     * record again without changing the status never re-sends anything.
     */
    public static void sendDeliveryStatusEmails(
        List<Order_Tracking__c> newTrackings,
        Map<Id, Order_Tracking__c> oldTrackingMap
    ) {

        Set<Id> trackingIdsToNotify = new Set<Id>();

        for (Order_Tracking__c tracking : newTrackings) {

            Order_Tracking__c oldTracking = (oldTrackingMap == null) ? null : oldTrackingMap.get(tracking.Id);

            Boolean statusJustChanged =
                oldTracking != null &&
                oldTracking.Delivery_Status__c != tracking.Delivery_Status__c;

            if (statusJustChanged && NOTIFY_STATUSES.contains(tracking.Delivery_Status__c)) {
                trackingIdsToNotify.add(tracking.Id);
            }
        }

        if (trackingIdsToNotify.isEmpty()) {
            return;
        }

        List<Order_Tracking__c> trackings = [
            SELECT Id, Delivery_Status__c, Tracking_NUmber__c, Delivery_Date__c,
                   Order__c, Order__r.OrderNumber, Order__r.AccountId
            FROM Order_Tracking__c
            WHERE Id IN :trackingIdsToNotify
            WITH SYSTEM_MODE
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Order_Tracking__c tracking : trackings) {
            if (tracking.Order__r.AccountId != null) {
                accountIds.add(tracking.Order__r.AccountId);
            }
        }

        // Same "one Contact per Account" lookup PaymentService already uses
        // for its own confirmation email — the customer's email lives on
        // the Contact created at checkout, not on the Order itself.
        Map<Id, Contact> contactByAccount = new Map<Id, Contact>();
        for (Contact con : [
            SELECT AccountId, Name, Email
            FROM Contact
            WHERE AccountId IN :accountIds
            AND Email != null
            WITH SYSTEM_MODE
        ]) {
            contactByAccount.put(con.AccountId, con);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Order_Tracking__c tracking : trackings) {
            Contact con = contactByAccount.get(tracking.Order__r.AccountId);
            if (con == null || String.isBlank(con.Email)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { con.Email });
            mail.setSubject(subjectFor(tracking.Delivery_Status__c, tracking.Order__r.OrderNumber));
            mail.setPlainTextBody(plainTextBodyFor(con, tracking));
            mail.setHtmlBody(buildDeliveryStatusHtmlBody(con, tracking));
            mail.setSaveAsActivity(false);
            emails.add(mail);
        }

        if (emails.isEmpty()) {
            return;
        }

        // Same isolation reasoning as PaymentService.sendPaymentConfirmationEmails
        // — an email hiccup must never block the admin's own record save.
        try {
            Messaging.sendEmail(emails);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Delivery status email failed: ' + e.getMessage());
        }
    }

    /**
     * Awards loyalty points the moment an Order_Tracking__c's
     * Delivery_Status__c first reaches 'Delivered' — see Feature Expansion
     * Plan §2.3 for why points are earned here rather than at checkout
     * (payment can still fail, or the order can still be cancelled, before
     * delivery). Reuses the same "did the status just change" detection as
     * sendDeliveryStatusEmails so awarding never double-fires from an
     * unrelated field edit on an already-Delivered tracking record.
     */
    public static void awardLoyaltyPointsOnDelivery(
        List<Order_Tracking__c> newTrackings,
        Map<Id, Order_Tracking__c> oldTrackingMap
    ) {
        Set<Id> orderIdsToAward = new Set<Id>();

        for (Order_Tracking__c tracking : newTrackings) {
            Order_Tracking__c oldTracking = (oldTrackingMap == null) ? null : oldTrackingMap.get(tracking.Id);
            Boolean justDelivered =
                oldTracking != null &&
                oldTracking.Delivery_Status__c != 'Delivered' &&
                tracking.Delivery_Status__c == 'Delivered';

            if (justDelivered && tracking.Order__c != null) {
                orderIdsToAward.add(tracking.Order__c);
            }
        }

        if (orderIdsToAward.isEmpty()) {
            return;
        }

        for (Order ord : [
            SELECT Id, Taxable_Amount__c, TotalAmount, Placed_By__c, AccountId
            FROM Order
            WHERE Id IN :orderIdsToAward
            WITH SYSTEM_MODE
        ]) {
            Id customerAccountId = ord.Placed_By__c != null ? ord.Placed_By__c : ord.AccountId;
            // Falls back to the raw TotalAmount for an Order that never went
            // through OrderPricingService (Taxable_Amount__c blank) — still
            // better than silently never awarding anything on such an order.
            Decimal eligibleAmount = ord.Taxable_Amount__c != null ? ord.Taxable_Amount__c : ord.TotalAmount;
            LoyaltyService.awardPointsForDeliveredOrder(customerAccountId, eligibleAmount, ord.Id);
        }
    }

    private static String subjectFor(String status, String orderNumber) {
        if (status == 'Shipped') {
            return 'Your LaptopKart Order #' + orderNumber + ' Has Shipped!';
        }
        if (status == 'Out for Delivery') {
            return 'Your LaptopKart Order #' + orderNumber + ' is Out for Delivery!';
        }
        if (status == 'Delivered') {
            return 'Your LaptopKart Order #' + orderNumber + ' Has Been Delivered!';
        }
        if (status == 'Return Requested') {
            return 'We\'ve Received Your Return Request for Order #' + orderNumber;
        }
        if (status == 'Returned') {
            return 'Your Return for Order #' + orderNumber + ' Has Been Processed';
        }
        return 'Your LaptopKart Order #' + orderNumber + ' Has Been Cancelled';
    }

    private static String messageFor(String status) {
        if (status == 'Shipped') {
            return 'Your order is on its way! It has just been shipped and is headed to you.';
        }
        if (status == 'Out for Delivery') {
            return 'Almost there! Your order is out for delivery and should arrive very soon.';
        }
        if (status == 'Delivered') {
            return 'Your order has been delivered. We hope you enjoy your new laptop!';
        }
        if (status == 'Return Requested') {
            return 'We\'ve received your return request and will review it shortly. We\'ll notify you once it\'s processed.';
        }
        if (status == 'Returned') {
            return 'Your return has been processed. Any eligible refund and loyalty point adjustments have been applied to your account.';
        }
        return 'Your order has been cancelled. If you weren\'t expecting this, please contact our support team.';
    }

    private static String plainTextBodyFor(Contact con, Order_Tracking__c tracking) {
        return
            'Hi ' + (con.Name == null ? '' : con.Name) + ',\n\n' +
            messageFor(tracking.Delivery_Status__c) + '\n\n' +
            'Order Number: ' + tracking.Order__r.OrderNumber + '\n' +
            (String.isBlank(tracking.Tracking_NUmber__c) ? '' : 'Tracking Number: ' + tracking.Tracking_NUmber__c + '\n') +
            (tracking.Delivery_Date__c == null ? '' : 'Estimated Delivery: ' + tracking.Delivery_Date__c.format() + '\n') +
            '\nYou can check your order anytime from Order History on the LaptopKart website.\n\n' +
            '- The LaptopKart Team';
    }

    // Mirrors PaymentService.buildPaymentConfirmationHtmlBody's styling so
    // every email this app sends looks like it comes from the same place.
    // @TestVisible so a test can assert on the real built content directly.
    @TestVisible
    private static String buildDeliveryStatusHtmlBody(Contact con, Order_Tracking__c tracking) {
        String status = tracking.Delivery_Status__c;
        String accentColor = (status == 'Cancelled') ? '#c0392b' : '#1a7a3a';

        return
            '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                '<h2 style="margin:0 0 4px;font-size:20px;color:' + accentColor + ';">' + status.escapeHtml4() + '</h2>' +
                '<p style="color:#555555;font-size:14px;line-height:1.5;">' +
                    'Hi ' + (con.Name == null ? '' : con.Name.escapeHtml4()) + ', ' + messageFor(status).escapeHtml4() +
                '</p>' +
                '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Order Number</td>' +
                        '<td style="text-align:right;font-weight:bold;font-size:13px;">' + tracking.Order__r.OrderNumber + '</td></tr>' +
                    (String.isBlank(tracking.Tracking_NUmber__c) ? '' :
                        '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Tracking Number</td>' +
                            '<td style="text-align:right;font-size:13px;">' + tracking.Tracking_NUmber__c.escapeHtml4() + '</td></tr>'
                    ) +
                    (tracking.Delivery_Date__c == null ? '' :
                        '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Estimated Delivery</td>' +
                            '<td style="text-align:right;font-size:13px;">' + tracking.Delivery_Date__c.format() + '</td></tr>'
                    ) +
                '</table>' +
                '<p style="font-size:13px;color:#333333;margin-top:16px;">' +
                    'You can check your order anytime from Order History on the LaptopKart website.' +
                '</p>' +
                '<p style="font-size:13px;color:#333333;margin-top:16px;">- The LaptopKart Team</p>' +
            '</div>';
    }
}
