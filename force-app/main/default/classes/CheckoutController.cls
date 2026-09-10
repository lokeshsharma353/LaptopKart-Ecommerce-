public without sharing class CheckoutController {

    // Runs the full order pipeline for a completed TechBasket checkout:
    // Lead -> converted Account/Contact/Opportunity -> Opportunity Closed Won
    // (which the existing OrderTrigger -> OrderService automation turns into a
    // real Order + OrderItems) -> Order activated (existing OrderTrigger ->
    // OrderTrackingService creates the Order_Tracking__c record) -> Payment__c
    // (existing PaymentTrigger -> PaymentService validates it and recalculates
    // the Order's payment totals). Prices are looked up server-side from the
    // Standard Price Book — cart prices from the browser are never trusted.
    // Takes the payload as a raw JSON string and deserializes it manually,
    // rather than accepting a strongly-typed CheckoutInput parameter directly.
    // Salesforce's automatic @AuraEnabled parameter binding for a
    // List<InnerClass> field (items) was unreliably arriving null/empty for
    // Guest/Site users on this org, even though the exact same JSON
    // deserializes correctly with JSON.deserialize() — confirmed by direct
    // testing. A single String parameter sidesteps that binding path entirely.
    @AuraEnabled
    public static OrderResult submitOrder(String inputJson) {

        CheckoutInput input;
        try {
            input = (CheckoutInput) JSON.deserialize(inputJson, CheckoutInput.class);
        } catch (Exception e) {
            throw new AuraHandledException('Could not read your order details. Please try again.');
        }

        if (input == null || input.items == null || input.items.isEmpty()) {
            throw new AuraHandledException('Your cart is empty.');
        }

        Id standardPricebookId = [
            SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
        ].Id;

        // Website checkout runs as whoever is browsing — the Guest User for an
        // unauthenticated shopper. Every record below is deliberately created
        // and owned by that SAME running user throughout the transaction (not
        // reassigned to the admin until the very end): Guest Users are denied
        // "cross-reference" access to any record they don't themselves own or
        // have sharing visibility into — confirmed directly, and this specific
        // restriction is NOT bypassed by AccessLevel.SYSTEM_MODE, unlike plain
        // object permissions. Assigning ownership to the admin up front would
        // mean the Guest User creating the Order could never legally link it
        // to "its own" Account, since it wouldn't be able to see that Account
        // at all. Ownership is reassigned to the admin in one final step once
        // every cross-reference has already been resolved.
        Id defaultOwnerId = getDefaultOwnerId();


        // STEP 1: Lead
        Lead newLead = new Lead();
        newLead.LastName = input.customerName;
        newLead.Company = input.customerName + ' (LaptopKart Customer)';
        newLead.Email = input.customerEmail;
        newLead.Phone = input.customerPhone;
        newLead.LeadSource = 'TechBasket Website';
        newLead.Status = 'Open - Not Contacted';
        // Department__c is a required picklist on Lead in this org (IT/HR/Finance/
        // Sales/...) that doesn't map cleanly to a retail customer — defaulting to
        // "Sales" since this Lead exists because of a purchase.
        newLead.Department__c = 'Sales';
        // Explicitly forced to the actual running user (confirmed via debug
        // log to be UserInfo.getUserId() itself — the real Guest User for an
        // anonymous shopper). Leaving OwnerId unset and relying on the
        // AccessLevel.SYSTEM_MODE insert below to "default" it turned out to
        // silently assign ownership to someone else entirely (observed: the
        // admin), meaning the running user never actually owned the record it
        // had just created — which is exactly what triggers Salesforce's
        // Guest User cross-reference restriction on every later step that
        // links back to it. Forcing it here guarantees the running user is
        // the real owner throughout, so it can legally reference its own
        // records; see STEP 10 for the final reassignment to the admin.
        newLead.OwnerId = UserInfo.getUserId();

        // Every DML statement below runs with AccessLevel.SYSTEM_MODE — the DML
        // equivalent of the WITH SYSTEM_MODE already used on this class's SOQL.
        // The Guest User License structurally cannot be granted Edit rights on
        // Opportunity/Order/Order_Tracking__c (confirmed directly: Salesforce
        // rejects even an attempt to grant that permission with "The user
        // license doesn't allow the permission"), so plain `update` statements
        // running as the Guest User would always be denied. SYSTEM_MODE bypasses
        // the running user's own object permissions entirely for this DML
        // (though not the separate Guest cross-reference restriction above).
        //
        // DuplicateRuleHeader.AllowSave = true — a returning customer checking
        // out again with the same name/email is completely normal for a real
        // storefront and must be allowed, not blocked by Salesforce's default
        // Lead duplicate rule.
        Database.DMLOptions leadDmo = new Database.DMLOptions();
        leadDmo.DuplicateRuleHeader.AllowSave = true;
        Database.insert(newLead, leadDmo, AccessLevel.SYSTEM_MODE);


        // STEP 2: Convert Lead -> Account / Contact / Opportunity, explicitly
        // owned by the running user for the same reason as the Lead above.
        //
        // A returning customer (same email as a previous order) triggers
        // Salesforce's Account/Contact duplicate rule if LeadConvert tries to
        // create fresh records for them — unlike the Lead duplicate rule
        // above, Database.LeadConvert has no DuplicateRuleHeader option to
        // bypass this. The correct fix isn't to bypass it though: attach this
        // order's new Opportunity to their EXISTING Account/Contact instead,
        // which is also just correct behavior for a repeat customer. The
        // Guest User Sharing Rules already grant the Guest User read access
        // to any Account/Contact matching the TechBasket criteria regardless
        // of current owner, so referencing an admin-owned existing one here
        // is safe.
        List<Contact> existingContacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = :input.customerEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(newLead.Id);
        lc.setConvertedStatus('Closed - Converted');
        lc.setDoNotCreateOpportunity(false);
        lc.setOwnerId(UserInfo.getUserId());
        lc.setOpportunityName(
            'TechBasket Order - ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss')
        );
        if (!existingContacts.isEmpty()) {
            lc.setContactId(existingContacts[0].Id);
            lc.setAccountId(existingContacts[0].AccountId);
        }

        Database.LeadConvertResult lcr = Database.convertLead(lc, false);

        // convertLead(lc, false) does NOT throw on failure — it returns a
        // result with isSuccess()=false instead, which was previously going
        // unchecked and surfacing as a confusing downstream NullPointer-style
        // error ("Id not specified") several steps later instead of the real
        // cause. Surface the actual reason now (most likely scenario: a
        // Contact/Account duplicate rule blocking the conversion, separate
        // from the Lead duplicate rule already bypassed above).
        if (!lcr.isSuccess()) {
            List<String> errorMessages = new List<String>();
            for (Database.Error err : lcr.getErrors()) {
                errorMessages.add(err.getMessage());
            }
            throw new AuraHandledException(
                'Could not process your details: ' + String.join(errorMessages, ' ')
            );
        }

        Id accountId = lcr.getAccountId();
        Id contactId = lcr.getContactId();
        Id opportunityId = lcr.getOpportunityId();


        // STEP 3: Assign the Standard Price Book so line items can be added
        Database.update(
            new Opportunity(Id = opportunityId, Pricebook2Id = standardPricebookId),
            AccessLevel.SYSTEM_MODE
        );


        // STEP 4: Opportunity line items, priced from the real PricebookEntry —
        // never from whatever price the browser's cart happened to send.
        Set<Id> productIds = new Set<Id>();
        for (CartLineInput line : input.items) {
            productIds.add(line.productId);
        }

        Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, Product2.Name, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id IN :productIds
            AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            entryByProduct.put(entry.Product2Id, entry);
        }

        List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
        // Kept alongside lineItems purely to build the confirmation email body
        // (product names aren't queryable back off an OpportunityLineItem
        // without another round trip) — see sendConfirmationEmail.
        List<String> emailLines = new List<String>();

        for (CartLineInput line : input.items) {

            PricebookEntry entry = entryByProduct.get(line.productId);

            if (entry == null) {
                continue;
            }

            OpportunityLineItem item = new OpportunityLineItem();
            item.OpportunityId = opportunityId;
            item.PricebookEntryId = entry.Id;
            item.Quantity = line.quantity;
            item.UnitPrice = entry.UnitPrice;

            lineItems.add(item);
            emailLines.add(
                line.quantity + ' x ' + entry.Product2.Name +
                ' - Rs. ' + entry.UnitPrice.setScale(2)
            );
        }

        if (lineItems.isEmpty()) {
            throw new AuraHandledException(
                'None of the items in your cart are currently available.'
            );
        }

        Database.insert(lineItems, AccessLevel.SYSTEM_MODE);


        // STEP 5: Close the Opportunity Won. This update (not the earlier insert)
        // is what fires OpportunityTrigger -> OrderService.createOrders(), so the
        // full field set is included here for that existing handler to read.
        Database.update(
            new Opportunity(
                Id = opportunityId,
                AccountId = accountId,
                Pricebook2Id = standardPricebookId,
                StageName = 'Closed Won',
                CloseDate = Date.today()
            ),
            AccessLevel.SYSTEM_MODE
        );


        // STEP 6: Find the Order OrderService just created for this Opportunity.
        Order newOrder = [
            SELECT Id, OrderNumber, TotalAmount
            FROM Order
            WHERE AccountId = :accountId
            AND Status = 'Draft'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];


        // STEP 7: Set the real shipping address on the Order, and activate it in
        // the same update — activating fires OrderTrigger -> OrderTrackingService,
        // which creates the Order_Tracking__c record.
        Order orderUpdate = new Order(Id = newOrder.Id, Status = 'Activated');

        orderUpdate.ShippingStreet = input.shippingStreet;
        orderUpdate.ShippingCity = input.shippingCity;
        orderUpdate.ShippingState = input.shippingState;
        orderUpdate.ShippingPostalCode = input.shippingPostalCode;
        orderUpdate.ShippingCountry = input.shippingCountry;
        // Marks this Order as website-originated so a criteria-based Guest
        // User Sharing Rule (Website_Order__c = true) can grant the Guest
        // User read access to it — Guest User Sharing Rules in this org only
        // support criteria, not "owned by", and Description (Long Text Area)
        // isn't a supported criteria field type, so a plain Checkbox field
        // exists purely to be a matchable value.
        orderUpdate.Website_Order__c = true;

        try {
            Database.update(orderUpdate, AccessLevel.SYSTEM_MODE);
        } catch (DmlException e) {
            // State and Country Picklists are enabled in this org, so
            // ShippingState/ShippingCountry must exactly match a real picklist
            // value — free-text input that doesn't (e.g. a typo, or a state
            // name entered in the wrong format) would otherwise roll back the
            // entire order, even though it's already been created. Retry
            // without state/country so the order still completes; street,
            // city and postal code (plain text fields) are unaffected.
            Order orderUpdateRetry = new Order(Id = newOrder.Id, Status = 'Activated');
            orderUpdateRetry.ShippingStreet = input.shippingStreet;
            orderUpdateRetry.ShippingCity = input.shippingCity;
            orderUpdateRetry.ShippingPostalCode = input.shippingPostalCode;
            orderUpdateRetry.Website_Order__c = true;
            Database.update(orderUpdateRetry, AccessLevel.SYSTEM_MODE);
        }


        // STEP 8: Supplement the tracking record with a tracking number and an
        // estimated delivery date — the existing automation only sets Delivery
        // Status. A real carrier integration is a separate future connection.
        Order_Tracking__c tracking = [
            SELECT Id, Delivery_Status__c
            FROM Order_Tracking__c
            WHERE Order__c = :newOrder.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        tracking.Tracking_NUmber__c =
            'TRK' + String.valueOf(Datetime.now().getTime());
        tracking.Delivery_Date__c = Date.today().addDays(5);

        Database.update(tracking, AccessLevel.SYSTEM_MODE);


        // STEP 9: Record the payment. Amount is the real Order.TotalAmount
        // (product lines only — shipping/tax have no OrderItem representation
        // in this schema, so they stay frontend-only display concepts). The
        // existing PaymentTrigger validates and recalculates payment totals.
        Payment__c payment = new Payment__c();
        payment.Order__c = newOrder.Id;
        payment.Amount__c = newOrder.TotalAmount;
        payment.Payment_Date__c = Date.today();
        // Starts Pending regardless of payment method — Online is a
        // self-reported UTR with no gateway to verify it against, and Cash
        // on Delivery hasn't actually been collected yet either. An admin
        // manually reviews and changes this to 'Successful' once they've
        // confirmed the payment (checked the UTR against their own UPI
        // account, etc.) — see PaymentService.sendPaymentConfirmationEmails,
        // which fires the customer's "your order is confirmed" email at
        // that exact moment, not here.
        payment.Payment_Status__c = 'Pending';
        payment.Payment_Method__c = input.paymentMethod;
        // The UTR the shopper typed in after paying via the QR code is the
        // real transaction reference for an online payment — there's no
        // gateway API here to verify it against, so it's trusted at face
        // value (the admin reconciles it against their own UPI account); a
        // generated placeholder covers Cash on Delivery, which has no UTR.
        payment.Transaction_ID__c = String.isNotBlank(input.utrNumber)
            ? input.utrNumber
            : 'TXN' + String.valueOf(Datetime.now().getTime());
        // See STEP 1 for why this is forced explicitly rather than left to
        // default under AccessLevel.SYSTEM_MODE.
        payment.OwnerId = UserInfo.getUserId();

        Database.insert(payment, AccessLevel.SYSTEM_MODE);


        // STEP 9.5: Best-effort order-confirmation email to the address the
        // shopper typed into the shipping form. Wrapped so a deliverability
        // problem (org email limits, a Guest-context sending restriction)
        // never rolls back an otherwise-successful order.
        sendConfirmationEmail(input, newOrder, tracking, emailLines);


        // STEP 10: Now that every cross-reference has been resolved (the
        // Guest User could see and link its own records throughout), reassign
        // ownership of everything to the admin in one final pass. This is a
        // plain field update on records the running user already has full
        // access to — not a new cross-reference — so SYSTEM_MODE covers it
        // the same way it covers every other update in this method.
        List<SObject> toReassign = new List<SObject>{
            new Account(Id = accountId, OwnerId = defaultOwnerId),
            new Contact(Id = contactId, OwnerId = defaultOwnerId),
            new Opportunity(Id = opportunityId, OwnerId = defaultOwnerId),
            new Order(Id = newOrder.Id, OwnerId = defaultOwnerId),
            new Order_Tracking__c(Id = tracking.Id, OwnerId = defaultOwnerId),
            new Payment__c(Id = payment.Id, OwnerId = defaultOwnerId)
        };
        Database.update(toReassign, AccessLevel.SYSTEM_MODE);


        OrderResult result = new OrderResult();
        result.orderId = newOrder.Id;
        result.orderNumber = newOrder.OrderNumber;
        result.trackingNumber = tracking.Tracking_NUmber__c;
        result.deliveryDate = tracking.Delivery_Date__c;
        result.totalAmount = newOrder.TotalAmount;

        return result;
    }


    // Sends the order-confirmation email. Isolated in its own try/catch so a
    // failure here (email deliverability settings, org daily limits) can
    // never undo the order that was just successfully created.
    private static void sendConfirmationEmail(
        CheckoutInput input,
        Order newOrder,
        Order_Tracking__c tracking,
        List<String> emailLines
    ) {
        try {
            String body =
                'Hi ' + input.customerName + ',\n\n' +
                'Thank you for your order! We have received it and are now confirming your ' +
                'payment. You will get another email the moment it is confirmed.\n\n' +
                'Order Number: ' + newOrder.OrderNumber + '\n' +
                'Order Total: Rs. ' + newOrder.TotalAmount.setScale(2) + '\n' +
                'Payment Method: ' + input.paymentMethod + '\n' +
                'Tracking Number: ' + tracking.Tracking_NUmber__c + '\n' +
                'Estimated Delivery: ' + tracking.Delivery_Date__c.format() + '\n\n' +
                'Items:\n' + String.join(emailLines, '\n') + '\n\n' +
                'Shipping Address:\n' +
                input.shippingStreet + ', ' + input.shippingCity + ', ' +
                input.shippingState + ' ' + input.shippingPostalCode + ', ' +
                input.shippingCountry + '\n\n' +
                '- The LaptopKart Team';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            // Sent to whatever email the shopper actually typed into the
            // shipping form — never the admin's own address — with the
            // admin CC'd so they see every order notification as it happens,
            // with the exact same confirmation/invoice the customer got.
            mail.setToAddresses(new String[] { input.customerEmail });
            mail.setCcAddresses(new String[] { ADMIN_NOTIFICATION_EMAIL });
            // Deliberately NOT "...is Confirmed" — payment hasn't been
            // confirmed by an admin yet at this point (see
            // PaymentService.sendPaymentConfirmationEmails for that email).
            mail.setSubject('We\'ve Received Your LaptopKart Order #' + newOrder.OrderNumber);
            mail.setPlainTextBody(body);
            // The full invoice content lives directly in this HTML body too
            // (not only in the PDF attachment below) — the PDF attachment
            // was found to render blank for Guest-User-originated checkout
            // emails specifically (a Salesforce Guest-context PDF-rendering
            // limitation, confirmed not to be a data-visibility problem: see
            // OrderInvoiceControllerTest, which proves the same query the
            // PDF uses returns full, correct data when run as the Guest
            // User). The email itself must never depend on that PDF working.
            mail.setHtmlBody(buildConfirmationHtmlBody(input, newOrder, tracking, emailLines));
            mail.setSaveAsActivity(false);

            // Attach the same PDF invoice the "Download Invoice" button on
            // Order Confirmation generates (OrderInvoice VF page rendered as
            // PDF) as a best-effort bonus — isolated in its own try/catch,
            // nested inside the outer one, since the HTML body above already
            // guarantees the customer has the real invoice information
            // regardless of whether this succeeds.
            try {
                PageReference invoicePage = Page.OrderInvoice;
                invoicePage.getParameters().put('orderId', newOrder.Id);
                Blob pdfBlob = Test.isRunningTest()
                    ? Blob.valueOf('Test invoice PDF')
                    : invoicePage.getContentAsPDF();

                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName('LaptopKart_Invoice_' + newOrder.OrderNumber + '.pdf');
                attachment.setBody(pdfBlob);
                attachment.setContentType('application/pdf');
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Invoice PDF attachment failed: ' + e.getMessage());
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Order confirmation email failed: ' + e.getMessage());
        }
    }


    // Builds a self-contained HTML invoice for the confirmation email body —
    // every value comes from the same inputs the plain-text body and the PDF
    // attachment use, so this can never disagree with either. escapeHtml4()
    // on every free-text/user-entered value to stay XSS-safe.
    // @TestVisible so a test can assert on the real built content directly,
    // rather than only proving sendConfirmationEmail doesn't throw.
    @TestVisible
    private static String buildConfirmationHtmlBody(
        CheckoutInput input,
        Order newOrder,
        Order_Tracking__c tracking,
        List<String> emailLines
    ) {
        String itemRows = '';
        for (String line : emailLines) {
            itemRows +=
                '<tr><td style="padding:6px 0;border-bottom:1px solid #eeeeee;font-size:13px;color:#333333;">' +
                line.escapeHtml4() +
                '</td></tr>';
        }

        String shippingAddress =
            input.shippingStreet.escapeHtml4() + ', ' + input.shippingCity.escapeHtml4() + ', ' +
            input.shippingState.escapeHtml4() + ' ' + input.shippingPostalCode.escapeHtml4() + ', ' +
            input.shippingCountry.escapeHtml4();

        return
            '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                '<h2 style="margin:0 0 4px;font-size:20px;">Thank you, ' + input.customerName.escapeHtml4() + '!</h2>' +
                '<p style="color:#555555;font-size:14px;line-height:1.5;">' +
                    'We\'ve received your order and are confirming your payment. ' +
                    'You\'ll get another email the moment it\'s approved.' +
                '</p>' +
                '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Order Number</td>' +
                        '<td style="text-align:right;font-weight:bold;font-size:13px;">' + newOrder.OrderNumber + '</td></tr>' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Payment Method</td>' +
                        '<td style="text-align:right;font-size:13px;">' + input.paymentMethod.escapeHtml4() + '</td></tr>' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Tracking Number</td>' +
                        '<td style="text-align:right;font-size:13px;">' + tracking.Tracking_NUmber__c + '</td></tr>' +
                    '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Estimated Delivery</td>' +
                        '<td style="text-align:right;font-size:13px;">' + tracking.Delivery_Date__c.format() + '</td></tr>' +
                '</table>' +
                '<h3 style="font-size:14px;margin:16px 0 8px;border-top:1px solid #eeeeee;padding-top:12px;">Items</h3>' +
                '<table style="width:100%;border-collapse:collapse;">' + itemRows + '</table>' +
                '<table style="width:100%;border-collapse:collapse;margin-top:8px;">' +
                    '<tr><td style="font-size:14px;font-weight:bold;padding-top:8px;">Order Total</td>' +
                        '<td style="text-align:right;font-size:14px;font-weight:bold;padding-top:8px;">' +
                        '&#8377; ' + newOrder.TotalAmount.setScale(2) + '</td></tr>' +
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


    // Cancels an Order placed through the website. Only Draft/Activated
    // orders can be cancelled; updating Status to Cancelled reuses the
    // existing OrderTrigger -> OrderTrackingService automation, which marks
    // the matching Order_Tracking__c Delivery_Status__c as Cancelled too —
    // the same automation chain submitOrder relies on, just run in reverse.
    @AuraEnabled
    public static void cancelOrder(Id orderId) {

        if (orderId == null) {
            throw new AuraHandledException('No order specified.');
        }

        List<Order> orders = [
            SELECT Id, Status
            FROM Order
            WHERE Id = :orderId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (orders.isEmpty()) {
            throw new AuraHandledException('Order not found.');
        }

        if (orders[0].Status == 'Cancelled') {
            throw new AuraHandledException('This order is already cancelled.');
        }

        Database.update(
            new Order(Id = orderId, Status = 'Cancelled'),
            AccessLevel.SYSTEM_MODE
        );
    }


    // Looks up every website order for a shopper by the email they used at
    // checkout — unlike getOrders(orderIds), this doesn't depend on this
    // specific browser's localStorage still holding the order ids, so a
    // shopper's full order history follows their email across browsers/
    // devices. Scoped to Website_Order__c = true so it can never surface an
    // Order that didn't come through this checkout flow.
    @AuraEnabled
    public static List<OrderSummary> getOrdersByEmail(String email) {

        if (String.isBlank(email)) {
            return new List<OrderSummary>();
        }

        Set<Id> accountIds = new Set<Id>();
        for (Contact con : [
            SELECT AccountId
            FROM Contact
            WHERE Email = :email
            AND AccountId != null
            WITH SYSTEM_MODE
        ]) {
            accountIds.add(con.AccountId);
        }

        if (accountIds.isEmpty()) {
            return new List<OrderSummary>();
        }

        List<Id> orderIds = new List<Id>();
        for (Order ord : [
            SELECT Id
            FROM Order
            WHERE AccountId IN :accountIds
            AND Website_Order__c = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            orderIds.add(ord.Id);
        }

        return getOrders(orderIds);
    }


    // Returns full order details (items, totals, tracking) for the given Order
    // Ids. Used by Order Confirmation/History/Tracking. Real login isn't wired
    // up yet, so the LWC currently remembers which order Ids belong to this
    // browser locally and asks for exactly those — nothing here trusts that
    // list for anything beyond "which records to look up."
    @AuraEnabled
    public static List<OrderSummary> getOrders(List<Id> orderIds) {

        List<OrderSummary> summaries = new List<OrderSummary>();

        if (orderIds == null || orderIds.isEmpty()) {
            return summaries;
        }

        Map<Id, Order_Tracking__c> trackingByOrder = new Map<Id, Order_Tracking__c>();
        for (Order_Tracking__c tracking : [
            SELECT Order__c, Tracking_NUmber__c, Delivery_Status__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c IN :orderIds
            WITH SYSTEM_MODE
        ]) {
            trackingByOrder.put(tracking.Order__c, tracking);
        }

        // Most recent Payment__c per Order — an Order could in principle
        // have more than one (e.g. a retry), so this takes the latest one
        // to represent "how this order was paid for" on the summary.
        Map<Id, Payment__c> paymentByOrder = new Map<Id, Payment__c>();
        for (Payment__c payment : [
            SELECT Order__c, Payment_Method__c, Transaction_ID__c
            FROM Payment__c
            WHERE Order__c IN :orderIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!paymentByOrder.containsKey(payment.Order__c)) {
                paymentByOrder.put(payment.Order__c, payment);
            }
        }

        for (Order ord : [
            SELECT Id, OrderNumber, CreatedDate, Status, TotalAmount,
                   Total_Paid__c, Payment_Status__c,
                   ShippingStreet, ShippingCity, ShippingState,
                   ShippingPostalCode, ShippingCountry,
                   (SELECT Product2Id, Product2.Name, Quantity, UnitPrice, TotalPrice
                    FROM OrderItems)
            FROM Order
            WHERE Id IN :orderIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {

            OrderSummary summary = new OrderSummary();
            summary.orderId = ord.Id;
            summary.orderNumber = ord.OrderNumber;
            summary.orderDate = ord.CreatedDate.date();
            summary.status = ord.Status;
            summary.totalAmount = ord.TotalAmount;
            summary.totalPaid = ord.Total_Paid__c;
            summary.paymentStatus = ord.Payment_Status__c;
            summary.shippingAddressLine = formatAddress(ord);

            Order_Tracking__c tracking = trackingByOrder.get(ord.Id);
            if (tracking != null) {
                summary.trackingNumber = tracking.Tracking_NUmber__c;
                summary.deliveryStatus = tracking.Delivery_Status__c;
                summary.deliveryDate = tracking.Delivery_Date__c;
            }

            Payment__c payment = paymentByOrder.get(ord.Id);
            if (payment != null) {
                summary.paymentMethod = payment.Payment_Method__c;
                summary.transactionId = payment.Transaction_ID__c;
            }

            summary.items = new List<OrderLineSummary>();
            for (OrderItem line : ord.OrderItems) {
                OrderLineSummary lineSummary = new OrderLineSummary();
                lineSummary.productId = line.Product2Id;
                lineSummary.productName = line.Product2.Name;
                lineSummary.quantity = line.Quantity.intValue();
                lineSummary.unitPrice = line.UnitPrice;
                lineSummary.lineTotal = line.TotalPrice;
                summary.items.add(lineSummary);
            }

            summaries.add(summary);
        }

        return summaries;
    }


    // Inbox that gets CC'd on every order confirmation email so the admin
    // is notified the moment a real order comes in.
    private static final String ADMIN_NOTIFICATION_EMAIL = 'lokesh@codleo.org';

    // The main admin user — every record the website's checkout pipeline
    // creates (Lead/Account/Contact/Opportunity/Order/Order_Tracking__c/
    // Payment__c) is owned by this user so it shows up immediately in the
    // admin's own Enterprise Order Management views, regardless of who was
    // actually browsing (Guest User or a logged-in customer). Matched by
    // username rather than "oldest System Administrator", since orgs can have
    // more than one admin user (e.g. a default org-setup user created before
    // the real admin) and CreatedDate order would pick the wrong one.
    private static final String DEFAULT_OWNER_USERNAME = 'lokesh@codleo.org';

    /** Looks up the admin User (by DEFAULT_OWNER_USERNAME, else any System Administrator, else the running user) that every checkout-created record ends up owned by. */
    private static Id getDefaultOwnerId() {
        List<User> namedAdmin = [
            SELECT Id FROM User
            WHERE Username = :DEFAULT_OWNER_USERNAME AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!namedAdmin.isEmpty()) {
            return namedAdmin[0].Id;
        }

        List<User> anyAdmin = [
            SELECT Id FROM User
            WHERE Profile.Name = 'System Administrator' AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return anyAdmin.isEmpty() ? UserInfo.getUserId() : anyAdmin[0].Id;
    }


    /** Joins an Order's non-blank shipping address fields into one comma-separated display line. */
    private static String formatAddress(Order ord) {

        List<String> parts = new List<String>();

        if (String.isNotBlank(ord.ShippingStreet)) {
            parts.add(ord.ShippingStreet);
        }
        if (String.isNotBlank(ord.ShippingCity)) {
            parts.add(ord.ShippingCity);
        }
        if (String.isNotBlank(ord.ShippingState)) {
            parts.add(ord.ShippingState);
        }
        if (String.isNotBlank(ord.ShippingPostalCode)) {
            parts.add(ord.ShippingPostalCode);
        }
        if (String.isNotBlank(ord.ShippingCountry)) {
            parts.add(ord.ShippingCountry);
        }

        return String.join(parts, ', ');
    }


    // Checkout payload sent from the LWC Payment page.
    public class CheckoutInput {

        @AuraEnabled
        public String customerName;

        @AuraEnabled
        public String customerEmail;

        @AuraEnabled
        public String customerPhone;

        @AuraEnabled
        public String paymentMethod;

        // Shipping address fields are flat on this class (not a nested object)
        // deliberately — a nested ShippingAddressInput object sitting alongside
        // the items array caused the LWR site's request serializer to mangle
        // the payload before it reached Apex, so items arrived empty/null even
        // though the browser's cart genuinely had items. Flat fields avoid the
        // nested-object shape entirely.
        @AuraEnabled
        public String shippingStreet;

        @AuraEnabled
        public String shippingCity;

        @AuraEnabled
        public String shippingState;

        @AuraEnabled
        public String shippingPostalCode;

        @AuraEnabled
        public String shippingCountry;

        @AuraEnabled
        public List<CartLineInput> items;

        // The UPI transaction reference (UTR) the shopper typed in after
        // paying via the QR code on the Payment page — set only when
        // paymentMethod is 'Online'.
        @AuraEnabled
        public String utrNumber;
    }


    // One cart line. Only productId/quantity are trusted from the client.
    public class CartLineInput {

        @AuraEnabled
        public Id productId;

        @AuraEnabled
        public Integer quantity;
    }


    // Result handed back to Order Confirmation/History/Tracking.
    public class OrderResult {

        @AuraEnabled
        public Id orderId;

        @AuraEnabled
        public String orderNumber;

        @AuraEnabled
        public String trackingNumber;

        @AuraEnabled
        public Date deliveryDate;

        @AuraEnabled
        public Decimal totalAmount;
    }


    // One order, as returned by getOrders(), for Confirmation/History/Tracking.
    public class OrderSummary {

        @AuraEnabled
        public Id orderId;

        @AuraEnabled
        public String orderNumber;

        @AuraEnabled
        public Date orderDate;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public Decimal totalAmount;

        @AuraEnabled
        public Decimal totalPaid;

        @AuraEnabled
        public String paymentStatus;

        @AuraEnabled
        public String shippingAddressLine;

        @AuraEnabled
        public String trackingNumber;

        @AuraEnabled
        public String deliveryStatus;

        @AuraEnabled
        public Date deliveryDate;

        @AuraEnabled
        public String paymentMethod;

        @AuraEnabled
        public String transactionId;

        @AuraEnabled
        public List<OrderLineSummary> items;
    }


    // One Order line within an OrderSummary.
    public class OrderLineSummary {

        @AuraEnabled
        public Id productId;

        @AuraEnabled
        public String productName;

        @AuraEnabled
        public Integer quantity;

        @AuraEnabled
        public Decimal unitPrice;

        @AuraEnabled
        public Decimal lineTotal;
    }
}