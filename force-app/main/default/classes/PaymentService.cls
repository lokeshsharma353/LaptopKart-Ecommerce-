
// without sharing: see OrderService — needs to see the just-created
// Payment__c and its parent Order for a real Guest checkout regardless of
// Guest Sharing Rule recalculation timing.
public without sharing class PaymentService {

    /** Rejects (via addError) any Payment__c marked Successful whose Order total-so-far would exceed the Order's Amount. */
    public static void validateSuccessfulPayments(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {

        Set<Id> orderIds = new Set<Id>();
        Set<Id> paymentIds = new Set<Id>();

        // Collect related Orders and current Payment IDs.
        // Sets prevent duplicate IDs during bulk processing.
        for (Payment__c payment : newPayments) {

            if (
                payment.Order__c != null &&
                payment.Payment_Status__c == 'Successful'
            ) {
                orderIds.add(payment.Order__c);
            }

            if (payment.Id != null) {
                paymentIds.add(payment.Id);
            }
        }

        if (orderIds.isEmpty()) {
            return;
        }


        // Get Order Amounts in one SOQL query.
        // No SOQL is placed inside the loop.
        // Amount_Payable__c (post-discount, post-GST, post-loyalty — see its
        // field description) is the real cap once a website order has gone
        // through OrderPricingService; TotalAmount alone (the raw product
        // sum) is only the right cap for an Order created outside that flow,
        // where Amount_Payable__c was never set.
        Map<Id, Decimal> orderAmountMap =
            new Map<Id, Decimal>();

        for (Order ord : [
            SELECT Id, TotalAmount, Amount_Payable__c
            FROM Order
            WHERE Id IN :orderIds
            WITH SYSTEM_MODE
        ]) {

            orderAmountMap.put(
                ord.Id,
                ord.Amount_Payable__c != null ? ord.Amount_Payable__c : ord.TotalAmount
            );
        }


        // Calculate existing successful Payment totals.
        // AggregateResult groups Payments by Order.
        Map<Id, Decimal> existingPaymentTotals =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Order__c OrderId,
                   SUM(Amount__c) TotalPaid
            FROM Payment__c
            WHERE Order__c IN :orderIds
            AND Payment_Status__c = 'Successful'
            AND Id NOT IN :paymentIds
            WITH SYSTEM_MODE
            GROUP BY Order__c
        ]) {

            Id orderId =
                (Id) result.get('OrderId');

            Decimal totalPaid =
                (Decimal) result.get('TotalPaid');

            existingPaymentTotals.put(
                orderId,
                totalPaid
            );
        }


        // Calculate totals for new or updated Payments.
        // Multiple Payments for the same Order are combined.
        Map<Id, Decimal> newPaymentTotals =
            new Map<Id, Decimal>();

        for (Payment__c payment : newPayments) {

            if (
                payment.Order__c == null ||
                payment.Payment_Status__c != 'Successful'
            ) {
                continue;
            }

            Decimal currentTotal = 0;

            if (
                newPaymentTotals.containsKey(
                    payment.Order__c
                )
            ) {
                currentTotal =
                    newPaymentTotals.get(
                        payment.Order__c
                    );
            }

            currentTotal += payment.Amount__c;

            newPaymentTotals.put(
                payment.Order__c,
                currentTotal
            );
        }


        // Check projected totals against Order Amount.
        // addError() rejects Payments that exceed the Order.
        for (Payment__c payment : newPayments) {

            if (
                payment.Order__c == null ||
                payment.Payment_Status__c != 'Successful'
            ) {
                continue;
            }

            Decimal existingTotal = 0;

            if (
                existingPaymentTotals.containsKey(
                    payment.Order__c
                )
            ) {
                existingTotal =
                    existingPaymentTotals.get(
                        payment.Order__c
                    );
            }

            Decimal newTotal =
                newPaymentTotals.get(
                    payment.Order__c
                );

            Decimal projectedTotal =
                existingTotal + newTotal;

            Decimal orderAmount =
                orderAmountMap.get(
                    payment.Order__c
                );

            if (
                orderAmount != null &&
                projectedTotal > orderAmount
            ) {

                payment.addError(
                    'Total payment cannot exceed Order Amount.'
                );
            }
        }
    }


    /** Recomputes each affected Order's Total_Paid__c and Payment_Status__c (Unpaid/Partially Paid/Fully Paid) from its Successful payments. */
    public static void calculateOrderPayments(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {

        Set<Id> orderIds = new Set<Id>();

        // Collect current and previously related Order IDs.
        // This also handles a Payment moved to another Order.
        for (Payment__c payment : newPayments) {

            if (payment.Order__c != null) {
                orderIds.add(payment.Order__c);
            }

            if (
                oldPaymentMap != null &&
                oldPaymentMap.containsKey(payment.Id)
            ) {

                Payment__c oldPayment =
                    oldPaymentMap.get(payment.Id);

                if (
                    oldPayment.Order__c != null &&
                    oldPayment.Order__c != payment.Order__c
                ) {
                    orderIds.add(
                        oldPayment.Order__c
                    );
                }
            }
        }

        if (orderIds.isEmpty()) {
            return;
        }


        // Get Order Amounts in one SOQL query.
        // The Map provides quick Order lookup.
        // Same Amount_Payable__c-first reasoning as validateSuccessfulPayments above.
        Map<Id, Decimal> orderAmountMap =
            new Map<Id, Decimal>();

        for (Order ord : [
            SELECT Id, TotalAmount, Amount_Payable__c
            FROM Order
            WHERE Id IN :orderIds
            WITH SYSTEM_MODE
        ]) {

            orderAmountMap.put(
                ord.Id,
                ord.Amount_Payable__c != null ? ord.Amount_Payable__c : ord.TotalAmount
            );
        }


        // Calculate only Successful Payment totals.
        // AggregateResult combines multiple Payments per Order.
        Map<Id, Decimal> paymentTotalsByOrder =
            new Map<Id, Decimal>();

        for (AggregateResult result : [
            SELECT Order__c OrderId,
                   SUM(Amount__c) TotalPaid
            FROM Payment__c
            WHERE Order__c IN :orderIds
            AND Payment_Status__c = 'Successful'
            WITH SYSTEM_MODE
            GROUP BY Order__c
        ]) {

            Id orderId =
                (Id) result.get('OrderId');

            Decimal totalPaid =
                (Decimal) result.get('TotalPaid');

            paymentTotalsByOrder.put(
                orderId,
                totalPaid
            );
        }


        List<Order> ordersToUpdate =
            new List<Order>();

        // Prepare Orders using only fields that need updating.
        // This avoids carrying unnecessary Order fields into DML.
        for (Id orderId : orderIds) {

            if (
                !orderAmountMap.containsKey(orderId)
            ) {
                continue;
            }

            Decimal totalPaid = 0;

            if (
                paymentTotalsByOrder.containsKey(
                    orderId
                )
            ) {
                totalPaid =
                    paymentTotalsByOrder.get(
                        orderId
                    );
            }

            Decimal orderAmount =
                orderAmountMap.get(
                    orderId
                );

            Order orderToUpdate =
                new Order(
                    Id = orderId
                );

            orderToUpdate.Total_Paid__c =
                totalPaid;


            // Set Payment Status based on Total Paid.
            // Status values follow the project requirement.
            if (totalPaid == 0) {

                orderToUpdate.Payment_Status__c =
                    'Unpaid';

            } else if (totalPaid < orderAmount) {

                orderToUpdate.Payment_Status__c =
                    'Partially Paid';

            } else if (totalPaid == orderAmount) {

                orderToUpdate.Payment_Status__c =
                    'Fully Paid';
            }

            ordersToUpdate.add(
                orderToUpdate
            );
        }


        // Update all affected Orders in one DML statement.
        // No DML is performed inside the loop.
        // AccessLevel.SYSTEM_MODE — see OrderService for why: the Order
        // license structurally cannot be granted Edit to a Guest User, so
        // this update would otherwise always be denied for a Guest-created
        // order. Strictly widens access, so it doesn't change behavior for
        // any other caller of this class.
        if (!ordersToUpdate.isEmpty()) {

            Database.update(ordersToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }


    // Sends the customer a "your order is confirmed" email the moment a
    // Payment__c's Payment_Status__c becomes 'Successful' — whether that
    // happens on INSERT (a Razorpay payment CheckoutController has already
    // re-verified with Razorpay before creating the record) or on a later
    // UPDATE (an admin manually confirming a Cash on Delivery payment, or
    // any other payment that started Pending). Either way this is the
    // real, verified signal that the order is genuinely paid for. Only
    // fires on payments that just became Successful, never on ones that
    // already were — editing some other field on an already-confirmed
    // payment won't re-send this email.
    public static void sendPaymentConfirmationEmails(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {

        Set<Id> orderIdsToNotify = new Set<Id>();

        for (Payment__c payment : newPayments) {

            Boolean justConfirmed =
                payment.Payment_Status__c == 'Successful' &&
                (oldPaymentMap == null ||
                 !oldPaymentMap.containsKey(payment.Id) ||
                 oldPaymentMap.get(payment.Id).Payment_Status__c != 'Successful');

            if (justConfirmed && payment.Order__c != null) {
                orderIdsToNotify.add(payment.Order__c);
            }
        }

        if (orderIdsToNotify.isEmpty()) {
            return;
        }

        List<Order> orders = [
            SELECT Id, OrderNumber, TotalAmount, AccountId,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   (SELECT Product2.Name, Quantity, UnitPrice FROM OrderItems)
            FROM Order
            WHERE Id IN :orderIdsToNotify
            WITH SYSTEM_MODE
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Order ord : orders) {
            if (ord.AccountId != null) {
                accountIds.add(ord.AccountId);
            }
        }

        // The customer's email lives on the Contact created during checkout
        // (Order has no email field of its own) — one Contact per Account
        // in this simple retail model, so a direct lookup is enough.
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

        Map<Id, Order_Tracking__c> trackingByOrder = new Map<Id, Order_Tracking__c>();
        for (Order_Tracking__c t : [
            SELECT Order__c, Tracking_NUmber__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c IN :orderIdsToNotify
            WITH SYSTEM_MODE
        ]) {
            trackingByOrder.put(t.Order__c, t);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Order ord : orders) {
            Contact con = contactByAccount.get(ord.AccountId);
            if (con == null || String.isBlank(con.Email)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { con.Email });
            mail.setSubject('Your LaptopKart Order #' + ord.OrderNumber + ' is Confirmed!');
            mail.setPlainTextBody(
                'Good news!\n\n' +
                'Your payment for Order #' + ord.OrderNumber + ' (Rs. ' +
                ord.TotalAmount.setScale(2) + ') has been confirmed.\n\n' +
                'Your order is now being prepared for shipment. You can check its ' +
                'progress anytime from Order History on the LaptopKart website.\n\n' +
                '- The LaptopKart Team'
            );
            // The full invoice content lives directly in this HTML body too
            // (not only in the best-effort PDF attachment below) — see
            // CheckoutController.buildConfirmationHtmlBody for why: the PDF
            // was found to render blank for Guest-context checkout emails,
            // confirmed to be a rendering-mechanism issue rather than a data
            // problem, so the email itself must never depend on it working.
            mail.setHtmlBody(buildPaymentConfirmationHtmlBody(con, ord, trackingByOrder.get(ord.Id)));
            mail.setSaveAsActivity(false);

            try {
                PageReference invoicePage = Page.OrderInvoice;
                invoicePage.getParameters().put('orderId', String.valueOf(ord.Id));
                Blob pdfBlob = Test.isRunningTest()
                    ? Blob.valueOf('Test invoice PDF')
                    : invoicePage.getContentAsPDF();

                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName('LaptopKart_Invoice_' + ord.OrderNumber + '.pdf');
                attachment.setBody(pdfBlob);
                attachment.setContentType('application/pdf');
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Invoice PDF attachment failed: ' + e.getMessage());
            }

            emails.add(mail);
        }

        if (emails.isEmpty()) {
            return;
        }

        // Isolated so an email hiccup (org daily limit, deliverability
        // settings) can never block the admin's own record save — the
        // Payment_Status__c change itself must always succeed regardless.
        // allOrNone=false so one bad address in a multi-order batch can
        // never take down every other customer's confirmation email with it
        // — same reasoning as AdminDashboardController.sendOfferEmail.
        try {
            List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);
            for (Integer i = 0; i < sendResults.size(); i++) {
                if (!sendResults[i].isSuccess()) {
                    String reason = !sendResults[i].getErrors().isEmpty() ? sendResults[i].getErrors()[0].getMessage() : 'Unknown error';
                    System.debug(LoggingLevel.WARN, 'Payment confirmation email failed for one recipient: ' + reason);
                    EmailSenderService.logEmailFailure('Payment Confirmation', emails[i].getToAddresses()[0], reason);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Payment confirmation email failed: ' + e.getMessage());
            EmailSenderService.logEmailFailure('Payment Confirmation (batch of ' + emails.size() + ')', null, e.getMessage());
        }
    }

    /**
     * Notifies a shopper when a payment becomes Failed or Refunded. Successful
     * payments retain the detailed invoice email sent by sendPaymentConfirmationEmails.
     * Only genuine status changes send an email, so editing a note or amount does not.
     */
    public static void sendPaymentIssueEmails(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentMap
    ) {
        Set<Id> paymentIdsToNotify = new Set<Id>();
        for (Payment__c payment : newPayments) {
            Payment__c oldPayment = oldPaymentMap == null ? null : oldPaymentMap.get(payment.Id);
            Boolean statusChanged = oldPayment == null || oldPayment.Payment_Status__c != payment.Payment_Status__c;
            if (statusChanged && (payment.Payment_Status__c == 'Failed' || payment.Payment_Status__c == 'Refunded')) {
                paymentIdsToNotify.add(payment.Id);
            }
        }
        if (paymentIdsToNotify.isEmpty()) {
            return;
        }

        List<Payment__c> payments = [
            SELECT Id, Amount__c, Payment_Status__c, Payment_Method__c, Transaction_ID__c,
                   Order__r.OrderNumber, Order__r.AccountId
            FROM Payment__c
            WHERE Id IN :paymentIdsToNotify
            WITH SYSTEM_MODE
        ];
        Set<Id> accountIds = new Set<Id>();
        for (Payment__c payment : payments) {
            if (payment.Order__r.AccountId != null) {
                accountIds.add(payment.Order__r.AccountId);
            }
        }

        Map<Id, Contact> contactByAccount = new Map<Id, Contact>();
        for (Contact contactRecord : [
            SELECT AccountId, Name, Email
            FROM Contact
            WHERE AccountId IN :accountIds AND Email != null
            WITH SYSTEM_MODE
        ]) {
            contactByAccount.put(contactRecord.AccountId, contactRecord);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Payment__c payment : payments) {
            Contact contactRecord = contactByAccount.get(payment.Order__r.AccountId);
            if (contactRecord == null || String.isBlank(contactRecord.Email)) {
                continue;
            }
            Boolean isRefund = payment.Payment_Status__c == 'Refunded';
            String heading = isRefund ? 'Payment Refunded' : 'Payment Failed';
            String message = isRefund
                ? 'Your payment refund has been recorded. Please allow your bank or payment provider time to process it.'
                : 'We could not complete your payment. Your order has not been marked as paid; please try again or contact support.';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { contactRecord.Email });
            mail.setSubject(heading + ' for LaptopKart Order #' + payment.Order__r.OrderNumber);
            mail.setPlainTextBody(
                'Hi ' + (contactRecord.Name == null ? '' : contactRecord.Name) + ',\n\n' +
                message + '\n\n' +
                'Order Number: ' + payment.Order__r.OrderNumber + '\n' +
                'Payment Method: ' + (payment.Payment_Method__c == null ? 'Not specified' : payment.Payment_Method__c) + '\n' +
                'Amount: Rs. ' + (payment.Amount__c == null ? '0.00' : String.valueOf(payment.Amount__c.setScale(2))) + '\n' +
                (String.isBlank(payment.Transaction_ID__c) ? '' : 'Transaction Reference: ' + payment.Transaction_ID__c + '\n') +
                '\n- The LaptopKart Team'
            );
            mail.setHtmlBody(
                '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                    '<h2 style="margin:0 0 8px;font-size:20px;color:' + (isRefund ? '#1a7a3a' : '#c0392b') + ';">' + heading + '</h2>' +
                    '<p style="color:#555555;font-size:14px;line-height:1.5;">Hi ' +
                        (contactRecord.Name == null ? '' : contactRecord.Name.escapeHtml4()) + ', ' + message.escapeHtml4() + '</p>' +
                    '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                        '<tr><td style="color:#666;padding:4px 0;">Order Number</td><td style="text-align:right;font-weight:bold;">' + payment.Order__r.OrderNumber + '</td></tr>' +
                        '<tr><td style="color:#666;padding:4px 0;">Payment Method</td><td style="text-align:right;">' +
                            (payment.Payment_Method__c == null ? 'Not specified' : payment.Payment_Method__c.escapeHtml4()) + '</td></tr>' +
                        '<tr><td style="color:#666;padding:4px 0;">Amount</td><td style="text-align:right;">&#8377; ' +
                            (payment.Amount__c == null ? '0.00' : String.valueOf(payment.Amount__c.setScale(2))) + '</td></tr>' +
                        (String.isBlank(payment.Transaction_ID__c) ? '' :
                            '<tr><td style="color:#666;padding:4px 0;">Transaction Reference</td><td style="text-align:right;">' + payment.Transaction_ID__c.escapeHtml4() + '</td></tr>') +
                    '</table><p>- The LaptopKart Team</p></div>'
            );
            mail.setSaveAsActivity(false);
            emails.add(mail);
        }
        if (emails.isEmpty()) {
            return;
        }
        try {
            Messaging.sendEmail(emails);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Payment issue email failed: ' + e.getMessage());
        }
    }

    // Builds a self-contained HTML invoice for the payment-confirmation
    // email body, mirroring buildConfirmationHtmlBody in CheckoutController.
    // @TestVisible so a test can assert on the real built content directly.
    @TestVisible
    private static String buildPaymentConfirmationHtmlBody(Contact con, Order ord, Order_Tracking__c tracking) {
        String itemRows = '';
        for (OrderItem line : ord.OrderItems) {
            itemRows +=
                '<tr><td style="padding:6px 0;border-bottom:1px solid #eeeeee;font-size:13px;color:#333333;">' +
                line.Quantity + ' x ' + line.Product2.Name.escapeHtml4() +
                ' - Rs. ' + line.UnitPrice.setScale(2) +
                '</td></tr>';
        }

        String shippingAddress = String.join(
            new List<String>{ ord.ShippingStreet, ord.ShippingCity, ord.ShippingState, ord.ShippingPostalCode, ord.ShippingCountry },
            ', '
        ).escapeHtml4();

        return
            '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                '<h2 style="margin:0 0 4px;font-size:20px;color:#1a7a3a;">Payment Confirmed!</h2>' +
                '<p style="color:#555555;font-size:14px;line-height:1.5;">' +
                    'Hi ' + (con.Name == null ? '' : con.Name.escapeHtml4()) + ', good news — your payment has been confirmed ' +
                    'and your order is now being prepared for shipment.' +
                '</p>' +
                '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Order Number</td>' +
                        '<td style="text-align:right;font-weight:bold;font-size:13px;">' + ord.OrderNumber + '</td></tr>' +
                    (tracking == null ? '' :
                        '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Tracking Number</td>' +
                            '<td style="text-align:right;font-size:13px;">' + tracking.Tracking_NUmber__c + '</td></tr>' +
                        '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Estimated Delivery</td>' +
                            '<td style="text-align:right;font-size:13px;">' +
                            (tracking.Delivery_Date__c == null ? '-' : tracking.Delivery_Date__c.format()) + '</td></tr>'
                    ) +
                '</table>' +
                '<h3 style="font-size:14px;margin:16px 0 8px;border-top:1px solid #eeeeee;padding-top:12px;">Items</h3>' +
                '<table style="width:100%;border-collapse:collapse;">' + itemRows + '</table>' +
                '<table style="width:100%;border-collapse:collapse;margin-top:8px;">' +
                    '<tr><td style="font-size:14px;font-weight:bold;padding-top:8px;">Order Total</td>' +
                        '<td style="text-align:right;font-size:14px;font-weight:bold;padding-top:8px;">' +
                        '&#8377; ' + ord.TotalAmount.setScale(2) + '</td></tr>' +
                '</table>' +
                '<h3 style="font-size:14px;margin:20px 0 6px;border-top:1px solid #eeeeee;padding-top:12px;">Shipping Address</h3>' +
                '<p style="font-size:13px;color:#333333;margin:0;">' + shippingAddress + '</p>' +
                '<p style="font-size:12px;color:#999999;margin-top:24px;">' +
                    'A PDF copy of this invoice is attached where possible. If you don\'t see it, ' +
                    'this email already has everything you need.' +
                '</p>' +
                '<p style="font-size:13px;color:#333333;margin-top:16px;">- The LaptopKart Team</p>' +
            '</div>';
    }
}