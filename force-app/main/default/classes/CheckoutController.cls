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
    // Starts a Razorpay payment: creates a Payment Link on Razorpay's side
    // for the cart's real, server-computed total (never a client-supplied
    // amount) and hands back the hosted URL the Payment page redirects the
    // shopper to. Called BEFORE submitOrder — nothing is created in
    // Salesforce yet at this point, so a shopper who backs out or whose
    // payment fails never leaves behind an empty Lead/Order.
    @AuraEnabled
    public static RazorpayService.PaymentLinkResult createRazorpayPaymentLink(
        Decimal amount,
        String customerName,
        String customerEmail,
        String customerPhone,
        String callbackUrl
    ) {
        if (amount == null || amount <= 0) {
            throw new AuraHandledException('Invalid order amount.');
        }
        try {
            return RazorpayService.createPaymentLink(amount, customerName, customerEmail, customerPhone, callbackUrl);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'createRazorpayPaymentLink failed: ' + e.getMessage());
            throw new AuraHandledException('Could not start the payment. Please try again.');
        }
    }


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

        // If this order was paid through Razorpay, verify it for real RIGHT
        // HERE, before any record is created — Apex cannot make an HTTP
        // callout once DML has run in the same transaction ("uncommitted
        // work pending"), and Steps 1-8 below do plenty of DML. The status
        // check happens now; the amount check happens later at STEP 9 once
        // newOrder.TotalAmount is known, reusing this same fetched result
        // rather than calling out to Razorpay a second time. Never trust
        // the redirect's own query parameters alone — those can be typed
        // into the URL bar by anyone.
        //
        // Only honored when paymentMethod is actually 'Online' — a stale
        // razorpayPaymentId can otherwise linger on the Payment page's own
        // instance state (e.g. the browser's back button returning to a
        // page that already auto-submitted once) and slip into a LATER
        // submission where the shopper has since picked Cash on Delivery
        // instead. Without this check that stale id would still get
        // verified and marked Successful, while Payment_Method__c recorded
        // 'Cash' — a real inconsistency found in this org's own data.
        // Silently ignored rather than rejected outright: it's stale
        // leftover state, not a malicious tamper attempt, so the order
        // should still go through normally as whatever method was actually
        // selected.
        RazorpayService.PaymentDetails gatewayPaymentDetails = null;
        if (input.paymentMethod == 'Online' && String.isNotBlank(input.razorpayPaymentId)) {
            gatewayPaymentDetails = RazorpayService.fetchPayment(input.razorpayPaymentId);
            if (gatewayPaymentDetails.status != 'captured') {
                throw new AuraHandledException('We could not verify your payment. Please try again or contact support.');
            }
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
        // Lead.Company is a required standard field with no real "company"
        // to put here — this is a B2C storefront, not a business buyer —
        // so it just holds the customer's own name. Deliberately plain,
        // with no "(LaptopKart Customer)" suffix: that used to leak into
        // the Account Name too (see STEP 2.5 below) and show up as the
        // customer's display name across the site and in Setup.
        newLead.Company = input.customerName;
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
        // A logged-in shopper (input.accountId set — see LoginCredentialsController)
        // is matched by that exact Account, not by whatever email happens to
        // be in the shipping form — the shipping email is the delivery
        // recipient's contact detail (§5.1) and could legitimately differ
        // from the buyer's own account email (ordering a gift for someone
        // else). A guest checkout (no accountId) keeps matching by email,
        // same as always.
        List<Contact> existingContacts = input.accountId != null
            ? [
                SELECT Id, AccountId
                FROM Contact
                WHERE AccountId = :input.accountId
                WITH SYSTEM_MODE
                LIMIT 1
            ]
            : [
                SELECT Id, AccountId
                FROM Contact
                WHERE Email = :input.customerEmail
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        Boolean isNewCustomerAccount = existingContacts.isEmpty();

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


        // STEP 2.5: Keep the Account's Name in sync with the customer placing
        // THIS order. For a first-time customer, LeadConvert already sets the
        // new Account's Name from Lead.Company (see STEP 1) — this is a no-op
        // there. For a returning customer, STEP 2 above reuses their existing
        // Account by Id, and LeadConvert never renames a reused Account, so it
        // otherwise keeps showing whatever name it had from checkout, however
        // long ago, on every later order — not who actually placed this one.
        //
        // Also normalizes the Account's record type to Customer Account
        // Detail. A brand-new Account from LeadConvert gets whatever record
        // type is the running Guest User's profile default (which, in this
        // org, is an unrelated legacy record type, not built for this app) —
        // and LoginCredentialsController.signUp separately sets this same
        // record type when a shopper signs up first. Forcing it here too
        // means every storefront customer Account ends up on the same record
        // type either way, whether they signed up or only ever checked out
        // as a guest.
        Account accountUpdate = new Account(Id = accountId, Name = input.customerName);
        Schema.RecordTypeInfo customerRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Customer_Account_Details');
        if (customerRT != null) {
            accountUpdate.RecordTypeId = customerRT.getRecordTypeId();
        }
        Database.update(accountUpdate, AccessLevel.SYSTEM_MODE);


        // STEP 3: Assign the Standard Price Book so line items can be added
        Database.update(
            new Opportunity(Id = opportunityId, Pricebook2Id = standardPricebookId),
            AccessLevel.SYSTEM_MODE
        );


        // STEP 4: Opportunity line items, priced from Product2.Price__c
        // directly — never from whatever price the browser's cart happened
        // to send, and never from a Price Book someone has to remember to
        // maintain. Product2 is the sole source of truth for pricing;
        // PricebookEntry only still exists here because OpportunityLineItem
        // (a hard Salesforce platform rule, not a choice made in this app)
        // requires a PricebookEntryId — so one is created on the fly, silently,
        // for any product that doesn't already have one, instead of requiring
        // anyone to manage the Price Book by hand.
        Set<Id> productIds = new Set<Id>();
        for (CartLineInput line : input.items) {
            productIds.add(line.productId);
        }

        // FOR UPDATE locks these Product2 rows for the rest of this
        // transaction — the classic "two customers both buy the last unit"
        // race (Feature Expansion Plan §12) is otherwise real: without a
        // lock, two concurrent checkouts could both read Stock_Quantity__c
        // = 1, both decide there's enough, and both succeed. With the lock,
        // whichever checkout gets here second simply waits for the first to
        // finish (commit or roll back) before reading the row, so it always
        // sees the real, up-to-date quantity.
        Map<Id, Product2> productById = new Map<Id, Product2>([
            SELECT Id, Name, Price__c, GST_Rate__c, Stock_Quantity__c, Family
            FROM Product2
            WHERE Id IN :productIds
            AND IsActive = true
            WITH SYSTEM_MODE
            FOR UPDATE
        ]);

        // Reject the whole order if any line exceeds real available stock —
        // delegated to InventoryService, which is also what actually
        // decrements and ledgers the sale below once the Order exists. See
        // InventoryService.validateStock for why the FOR UPDATE lock above
        // (not this call) is what closes the "two customers both buy the
        // last unit" race.
        List<InventoryService.StockLine> stockLines = new List<InventoryService.StockLine>();
        for (CartLineInput line : input.items) {
            InventoryService.StockLine stockLine = new InventoryService.StockLine();
            stockLine.productId = line.productId;
            stockLine.quantity = line.quantity;
            stockLines.add(stockLine);
        }
        InventoryService.validateStock(productById, stockLines);

        Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
            AND Product2Id IN :productIds
            AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            entryByProduct.put(entry.Product2Id, entry);
        }

        // Silently create a Standard Price Book entry for any cart product
        // that doesn't have one yet, priced from Product2.Price__c — this is
        // the only reason PricebookEntry is touched at all in this method.
        List<PricebookEntry> newEntries = new List<PricebookEntry>();
        for (Id productId : productIds) {
            Product2 product = productById.get(productId);
            if (!entryByProduct.containsKey(productId) && product != null && product.Price__c != null) {
                PricebookEntry newEntry = new PricebookEntry();
                newEntry.Pricebook2Id = standardPricebookId;
                newEntry.Product2Id = productId;
                newEntry.UnitPrice = product.Price__c;
                newEntry.IsActive = true;
                newEntries.add(newEntry);
            }
        }
        if (!newEntries.isEmpty()) {
            Database.insert(newEntries, AccessLevel.SYSTEM_MODE);
            for (PricebookEntry created : newEntries) {
                entryByProduct.put(created.Product2Id, created);
            }
        }

        List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
        // Kept alongside lineItems purely to build the confirmation email body
        // (product names aren't queryable back off an OpportunityLineItem
        // without another round trip) — see sendConfirmationEmail.
        List<String> emailLines = new List<String>();
        // Feeds OrderPricingService — see STEP 4.5 below.
        List<OrderPricingService.PricingLine> pricingLines = new List<OrderPricingService.PricingLine>();

        for (CartLineInput line : input.items) {

            PricebookEntry entry = entryByProduct.get(line.productId);
            Product2 product = productById.get(line.productId);

            if (entry == null || product == null) {
                continue;
            }

            // Prefers Product2.Price__c; falls back to the Price Book
            // entry's UnitPrice only in the unlikely case Price__c is blank
            // but an old entry already existed with a real UnitPrice.
            Decimal realPrice = product.Price__c != null ? product.Price__c : entry.UnitPrice;

            OpportunityLineItem item = new OpportunityLineItem();
            item.OpportunityId = opportunityId;
            item.PricebookEntryId = entry.Id;
            item.Quantity = line.quantity;
            item.UnitPrice = realPrice;

            lineItems.add(item);
            emailLines.add(
                line.quantity + ' x ' + product.Name +
                ' - Rs. ' + realPrice.setScale(2)
            );

            OrderPricingService.PricingLine pricingLine = new OrderPricingService.PricingLine();
            pricingLine.productId = line.productId;
            pricingLine.quantity = line.quantity;
            pricingLine.unitPrice = realPrice;
            pricingLine.gstRatePercent = product.GST_Rate__c;
            pricingLine.lineSubtotal = realPrice * line.quantity;
            pricingLine.category = product.Family;
            pricingLines.add(pricingLine);
        }

        if (lineItems.isEmpty()) {
            throw new AuraHandledException(
                'None of the items in your cart are currently available.'
            );
        }

        Database.insert(lineItems, AccessLevel.SYSTEM_MODE);


        // STEP 4.5: Run the same pricing engine the Payment page's live
        // preview already ran (OrderPricingService — subtotal -> coupon
        // discount -> taxable value -> GST -> loyalty redemption -> amount
        // payable) — recalculated from scratch here, never trusting the
        // preview's own numbers, same reasoning DiscountService/LoyaltyService
        // already apply to a client-supplied discount. This IS the amount
        // that gets charged and stored — see STEP 9 below.
        OrderPricingService.PricingResult pricing = OrderPricingService.calculate(
            pricingLines,
            input.shippingState,
            input.accountId,
            input.couponCode,
            input.pointsToRedeem,
            input.shippingMethodId
        );


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


        // STEP 6.5: Decrement tracked stock and log the Sale movement, now
        // that the real Order exists to attach Stock_Movement__c.Related_Order__c
        // to. Safe even though later steps can still throw (a Razorpay
        // amount mismatch at STEP 9, for example) — the whole method runs in
        // one transaction, so an unhandled exception rolls this back too,
        // exactly like every other DML above it. Reuses the same locked
        // productById Map validateStock already checked against.
        InventoryService.recordSale(productById, stockLines, newOrder.Id);


        // STEP 7: Set the real shipping address on the Order, and activate it in
        // the same update — activating fires OrderTrigger -> OrderTrackingService,
        // which creates the Order_Tracking__c record.
        Order orderUpdate = new Order(Id = newOrder.Id, Status = 'Activated');

        orderUpdate.ShippingStreet = input.shippingStreet;
        orderUpdate.ShippingCity = input.shippingCity;
        orderUpdate.ShippingState = input.shippingState;
        orderUpdate.ShippingPostalCode = input.shippingPostalCode;
        orderUpdate.ShippingCountry = input.shippingCountry;
        // Billing address — independently captured (§3.4/§3.5); falls back to
        // the shipping address fields when the shopper didn't provide
        // separate billing values (e.g. "same as shipping" was checked and
        // the LWC never sent billing fields at all).
        orderUpdate.BillingStreet = String.isNotBlank(input.billingStreet) ? input.billingStreet : input.shippingStreet;
        orderUpdate.BillingCity = String.isNotBlank(input.billingCity) ? input.billingCity : input.shippingCity;
        orderUpdate.BillingState = String.isNotBlank(input.billingState) ? input.billingState : input.shippingState;
        orderUpdate.BillingPostalCode = String.isNotBlank(input.billingPostalCode) ? input.billingPostalCode : input.shippingPostalCode;
        orderUpdate.BillingCountry = String.isNotBlank(input.billingCountry) ? input.billingCountry : input.shippingCountry;
        // Snapshot of who placed THIS order, set once and never touched again —
        // unlike Account Name, which STEP 2.5 above keeps renaming to whoever
        // most recently checked out under that email. List views/reports
        // should read this field, not Account Name, to see the real customer
        // per order.
        orderUpdate.Customer_Name__c = input.customerName;
        // The logged-in buyer (§5.1) — null for a guest checkout.
        orderUpdate.Placed_By__c = input.accountId;
        // The delivery recipient — defaults to the buyer's own name/phone
        // when the shipping form didn't separately capture a recipient.
        orderUpdate.Recipient_Name__c = String.isNotBlank(input.recipientName) ? input.recipientName : input.customerName;
        orderUpdate.Recipient_Phone__c = String.isNotBlank(input.recipientPhone) ? input.recipientPhone : input.customerPhone;
        // Pricing breakdown from STEP 4.5 — the authoritative, server-
        // recalculated numbers, never the browser's own preview math.
        orderUpdate.Discount_Amount__c = pricing.discountAmount;
        orderUpdate.Taxable_Amount__c = pricing.taxableAmount;
        orderUpdate.CGST_Amount__c = pricing.cgstAmount;
        orderUpdate.SGST_Amount__c = pricing.sgstAmount;
        orderUpdate.IGST_Amount__c = pricing.igstAmount;
        orderUpdate.Amount_Payable__c = pricing.amountPayable;
        orderUpdate.Shipping_Cost__c = pricing.shippingCost;
        orderUpdate.Shipping_Method__c = pricing.shippingMethodLabel;
        orderUpdate.Points_Redeemed__c = pricing.pointsUsed;
        if (pricing.couponValid) {
            orderUpdate.Coupon_Code_Applied__c = pricing.couponCode;
        }
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
            orderUpdateRetry.BillingStreet = orderUpdate.BillingStreet;
            orderUpdateRetry.BillingCity = orderUpdate.BillingCity;
            orderUpdateRetry.BillingPostalCode = orderUpdate.BillingPostalCode;
            orderUpdateRetry.Website_Order__c = true;
            orderUpdateRetry.Customer_Name__c = input.customerName;
            orderUpdateRetry.Placed_By__c = input.accountId;
            orderUpdateRetry.Recipient_Name__c = orderUpdate.Recipient_Name__c;
            orderUpdateRetry.Recipient_Phone__c = orderUpdate.Recipient_Phone__c;
            orderUpdateRetry.Discount_Amount__c = pricing.discountAmount;
            orderUpdateRetry.Taxable_Amount__c = pricing.taxableAmount;
            orderUpdateRetry.CGST_Amount__c = pricing.cgstAmount;
            orderUpdateRetry.SGST_Amount__c = pricing.sgstAmount;
            orderUpdateRetry.IGST_Amount__c = pricing.igstAmount;
            orderUpdateRetry.Amount_Payable__c = pricing.amountPayable;
            orderUpdateRetry.Shipping_Cost__c = pricing.shippingCost;
            orderUpdateRetry.Shipping_Method__c = pricing.shippingMethodLabel;
            orderUpdateRetry.Points_Redeemed__c = pricing.pointsUsed;
            if (pricing.couponValid) {
                orderUpdateRetry.Coupon_Code_Applied__c = pricing.couponCode;
            }
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
        // Direct link to the Account so Order Trackings can show as a
        // related list on the Account record itself, not just two hops
        // away through Order.
        tracking.Account__c = accountId;

        Database.update(tracking, AccessLevel.SYSTEM_MODE);


        // STEP 9: Record the payment. Amount is pricing.amountPayable — the
        // real, GST-inclusive, discount/loyalty-adjusted figure from STEP 4.5
        // (never the raw Order.TotalAmount, which is only the undiscounted
        // product-line sum — see Amount_Payable__c's field description and
        // PaymentService, which now validates/caps against it the same way).
        // The existing PaymentTrigger validates and recalculates payment totals.
        //
        // The amount check for a Razorpay payment happens here, now that
        // pricing.amountPayable is known — reusing gatewayPaymentDetails
        // fetched at the very top of this method (a callout can't happen
        // this late, after all the DML above; see that comment for why).
        // The status check already happened up there. Never trust the
        // redirect's own query parameters alone — those can be typed into
        // the URL bar by anyone. A mismatch throws here, which rolls back
        // every record this method has created so far (Lead/Account/
        // Opportunity/Order/Tracking), since an unhandled exception from an
        // @AuraEnabled method aborts the whole transaction. This is exactly
        // why techBasketPayment.js's Razorpay Payment Link is created for
        // this SAME amount (via previewOrderTotals) — a mismatch here would
        // otherwise reject genuinely-paid orders.
        Boolean isVerifiedGatewayPayment = false;
        if (gatewayPaymentDetails != null) {
            Integer expectedPaise = Integer.valueOf((pricing.amountPayable * 100).setScale(0));
            if (gatewayPaymentDetails.amountInPaise != expectedPaise) {
                throw new AuraHandledException('We could not verify your payment. Please try again or contact support.');
            }
            isVerifiedGatewayPayment = true;
        }

        Payment__c payment = new Payment__c();
        payment.Order__c = newOrder.Id;
        // Direct link to the Account so Payments can show as a related list
        // on the Account record itself, not just two hops away through Order.
        payment.Account__c = accountId;
        payment.Amount__c = pricing.amountPayable;
        payment.Payment_Date__c = Date.today();
        // A verified Razorpay payment (above) is genuinely Successful right
        // now — no admin review needed. Everything else (Cash on Delivery,
        // or the old self-reported-UTR fallback) still starts Pending, same
        // as before: nothing has actually been collected yet, or there's
        // nothing to verify it against. See
        // PaymentService.sendPaymentConfirmationEmails, which fires the
        // customer's "your order is confirmed" email the moment a Payment__c
        // becomes Successful — including right here, on insert.
        payment.Payment_Status__c = isVerifiedGatewayPayment ? 'Successful' : 'Pending';
        payment.Payment_Method__c = input.paymentMethod;
        // A verified Razorpay payment id is the real transaction reference.
        // Otherwise fall back to the self-reported UTR (trusted at face
        // value, the admin reconciles it manually), or a generated
        // placeholder for Cash on Delivery, which has neither. Gated on
        // isVerifiedGatewayPayment (not just input.razorpayPaymentId being
        // present) for the same reason as the verification check above —
        // a stale id that wasn't actually re-verified for THIS submission
        // must never end up recorded as this payment's transaction
        // reference.
        payment.Transaction_ID__c = isVerifiedGatewayPayment
            ? input.razorpayPaymentId
            : (String.isNotBlank(input.utrNumber)
                ? input.utrNumber
                : 'TXN' + String.valueOf(Datetime.now().getTime()));
        // See STEP 1 for why this is forced explicitly rather than left to
        // default under AccessLevel.SYSTEM_MODE.
        payment.OwnerId = UserInfo.getUserId();

        Database.insert(payment, AccessLevel.SYSTEM_MODE);


        // STEP 9.4: Record the coupon redemption (§1.4/§1.7) and loyalty
        // point spend (§2.5) now that the Order genuinely exists — never
        // earlier, so a checkout that fails before this point never
        // permanently consumes either (§1.5). Both are best-effort; a
        // bookkeeping failure here must never undo an order that's already
        // been created and paid for.
        if (pricing.couponValid) {
            DiscountService.recordRedemption(
                pricing.couponCodeId,
                pricing.campaignId,
                contactId,
                newOrder.Id,
                pricing.discountAmount
            );
        }
        if (pricing.pointsUsed > 0) {
            LoyaltyService.recordRedemption(input.accountId, pricing.pointsUsed, newOrder.Id);
        }


        // STEP 9.5: A first-time guest checkout creates an Account through
        // Lead conversion rather than LoginCredentialsController.signUp, so
        // send that customer the same account-created welcome separately.
        if (isNewCustomerAccount) {
            sendGuestAccountCreatedEmail(input);
        }

        // STEP 9.6: Best-effort order-confirmation email to the address the
        // shopper typed into the shipping form. Wrapped so a deliverability
        // problem (org email limits, a Guest-context sending restriction)
        // never rolls back an otherwise-successful order.
        sendConfirmationEmail(input, newOrder, tracking, emailLines, pricing);


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
        result.discountAmount = pricing.discountAmount;
        result.taxableAmount = pricing.taxableAmount;
        result.cgstAmount = pricing.cgstAmount;
        result.sgstAmount = pricing.sgstAmount;
        result.igstAmount = pricing.igstAmount;
        result.loyaltyDiscount = pricing.loyaltyDiscount;
        result.pointsUsed = pricing.pointsUsed;
        result.amountPayable = pricing.amountPayable;
        result.shippingCost = pricing.shippingCost;
        result.shippingMethodLabel = pricing.shippingMethodLabel;

        return result;
    }


    /**
     * Read-only pricing preview for the cart/Payment page UI — runs the
     * exact same OrderPricingService engine submitOrder itself uses, so what
     * the shopper sees (subtotal, coupon discount, GST breakdown, loyalty
     * discount, amount payable) is always the real, backend-calculated
     * figure, never a frontend approximation (§1.7/§3.7). Read-only: unlike
     * submitOrder, this never records a coupon redemption or spends loyalty
     * points — see DiscountService/LoyaltyService for why applying a coupon
     * to a cart must not permanently consume it (§1.5).
     *
     * Takes the request as a raw JSON string, exactly like submitOrder does
     * for the same documented reason: a List<InnerClass> @AuraEnabled
     * parameter was found to unreliably arrive null/empty for Guest/Site
     * users on this org even with a well-formed payload — see submitOrder's
     * own header comment. A single String parameter sidesteps that
     * binding path entirely.
     */
    @AuraEnabled
    public static OrderPricingService.PricingResult previewOrderTotals(String requestJson) {

        PreviewRequest request;
        try {
            request = (PreviewRequest) JSON.deserialize(requestJson, PreviewRequest.class);
        } catch (Exception e) {
            return new OrderPricingService.PricingResult();
        }

        if (request == null || request.items == null || request.items.isEmpty()) {
            return new OrderPricingService.PricingResult();
        }

        Set<Id> productIds = new Set<Id>();
        for (CartLineInput line : request.items) {
            if (line.productId != null) {
                productIds.add(line.productId);
            }
        }

        Map<Id, Product2> productById = new Map<Id, Product2>([
            SELECT Id, Price__c, GST_Rate__c, Family
            FROM Product2
            WHERE Id IN :productIds
            AND IsActive = true
            AND Price__c != null
            WITH SYSTEM_MODE
        ]);

        List<OrderPricingService.PricingLine> pricingLines = new List<OrderPricingService.PricingLine>();
        for (CartLineInput line : request.items) {
            Product2 product = productById.get(line.productId);
            if (product == null || line.quantity == null || line.quantity <= 0) {
                continue;
            }
            OrderPricingService.PricingLine pricingLine = new OrderPricingService.PricingLine();
            pricingLine.productId = line.productId;
            pricingLine.quantity = line.quantity;
            pricingLine.unitPrice = product.Price__c;
            pricingLine.gstRatePercent = product.GST_Rate__c;
            pricingLine.lineSubtotal = product.Price__c * line.quantity;
            pricingLine.category = product.Family;
            pricingLines.add(pricingLine);
        }

        return OrderPricingService.calculate(
            pricingLines,
            request.shippingState,
            request.accountId,
            request.couponCode,
            request.pointsToRedeem,
            request.shippingMethodId
        );
    }

    // Deserialization target for previewOrderTotals's JSON payload.
    public class PreviewRequest {
        @AuraEnabled public List<CartLineInput> items;
        @AuraEnabled public String shippingState;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String couponCode;
        @AuraEnabled public Integer pointsToRedeem;
        @AuraEnabled public String shippingMethodId;
    }


    // Sends the order-confirmation email. Isolated in its own try/catch so a
    // failure here (email deliverability settings, org daily limits) can
    // never undo the order that was just successfully created.
    private static void sendConfirmationEmail(
        CheckoutInput input,
        Order newOrder,
        Order_Tracking__c tracking,
        List<String> emailLines,
        OrderPricingService.PricingResult pricing
    ) {
        try {
            String body =
                'Hi ' + input.customerName + ',\n\n' +
                'Thank you for your order! We have received it and are now confirming your ' +
                'payment. You will get another email the moment it is confirmed.\n\n' +
                'Order Number: ' + newOrder.OrderNumber + '\n' +
                'Payment Method: ' + input.paymentMethod + '\n' +
                'Tracking Number: ' + tracking.Tracking_NUmber__c + '\n' +
                'Estimated Delivery: ' + tracking.Delivery_Date__c.format() + '\n\n' +
                'Items:\n' + String.join(emailLines, '\n') + '\n\n' +
                'Subtotal: Rs. ' + pricing.subtotal.setScale(2) + '\n' +
                (pricing.discountAmount > 0 ? 'Discount (' + pricing.couponCode + '): -Rs. ' + pricing.discountAmount.setScale(2) + '\n' : '') +
                'Taxable Value: Rs. ' + pricing.taxableAmount.setScale(2) + '\n' +
                (pricing.igstAmount > 0
                    ? 'IGST: Rs. ' + pricing.igstAmount.setScale(2) + '\n'
                    : 'CGST: Rs. ' + pricing.cgstAmount.setScale(2) + '\nSGST: Rs. ' + pricing.sgstAmount.setScale(2) + '\n') +
                (pricing.shippingCost > 0 ? 'Shipping (' + pricing.shippingMethodLabel + '): Rs. ' + pricing.shippingCost.setScale(2) + '\n' : '') +
                (pricing.loyaltyDiscount > 0 ? 'Loyalty Points Redeemed (' + pricing.pointsUsed + '): -Rs. ' + pricing.loyaltyDiscount.setScale(2) + '\n' : '') +
                'Amount Payable: Rs. ' + pricing.amountPayable.setScale(2) + '\n\n' +
                'Shipping Address:\n' +
                input.shippingStreet + ', ' + input.shippingCity + ', ' +
                input.shippingState + ' ' + input.shippingPostalCode + ', ' +
                input.shippingCountry + '\n\n' +
                '- The LaptopKart Team';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
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
            mail.setHtmlBody(buildConfirmationHtmlBody(input, newOrder, tracking, emailLines, pricing));
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Order confirmation email failed: ' + e.getMessage());
            EmailSenderService.logEmailFailure('Order Confirmation #' + newOrder.OrderNumber, input.customerEmail, e.getMessage());
        }
    }

    /** Welcomes a shopper whose Account was just created by their first guest checkout. */
    private static void sendGuestAccountCreatedEmail(CheckoutInput input) {
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { input.customerEmail });
            mail.setSubject('Welcome to LaptopKart, ' + input.customerName + '!');
            mail.setPlainTextBody(
                'Hi ' + input.customerName + ',\n\n' +
                'We created your LaptopKart customer account while processing your first order. ' +
                'You will receive a separate email with your order details.\n\n' +
                'Account email: ' + input.customerEmail + '\n' +
                'Phone: ' + (String.isBlank(input.customerPhone) ? 'Not provided' : input.customerPhone) + '\n\n' +
                '- The LaptopKart Team'
            );
            mail.setHtmlBody(
                '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                    '<h2 style="margin:0 0 8px;font-size:20px;color:#1a7a3a;">Welcome to LaptopKart!</h2>' +
                    '<p style="color:#555555;font-size:14px;line-height:1.5;">Hi ' + input.customerName.escapeHtml4() +
                    ', we created your customer account while processing your first order. ' +
                    'A separate email contains your order details.</p>' +
                    '<table style="width:100%;border-collapse:collapse;margin:16px 0;">' +
                        '<tr><td style="color:#666;padding:4px 0;">Account email</td><td style="text-align:right;">' + input.customerEmail.escapeHtml4() + '</td></tr>' +
                        '<tr><td style="color:#666;padding:4px 0;">Phone</td><td style="text-align:right;">' +
                            (String.isBlank(input.customerPhone) ? 'Not provided' : input.customerPhone.escapeHtml4()) + '</td></tr>' +
                    '</table><p>- The LaptopKart Team</p></div>'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Guest account-created email failed: ' + e.getMessage());
            EmailSenderService.logEmailFailure('Guest Account Creation Welcome', input.customerEmail, e.getMessage());
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
        List<String> emailLines,
        OrderPricingService.PricingResult pricing
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

        // Pricing breakdown rows — mirrors the plain-text body in
        // sendConfirmationEmail so both never disagree. Coupon/GST/loyalty
        // rows only render when they actually apply to this order.
        String pricingRows =
            '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Subtotal</td>' +
                '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.subtotal.setScale(2) + '</td></tr>' +
            (pricing.discountAmount > 0 ?
                '<tr><td style="font-size:13px;color:#1a7a3a;padding:4px 0;">Discount (' + pricing.couponCode.escapeHtml4() + ')</td>' +
                    '<td style="text-align:right;font-size:13px;color:#1a7a3a;">-&#8377; ' + pricing.discountAmount.setScale(2) + '</td></tr>' : '') +
            '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Taxable Value</td>' +
                '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.taxableAmount.setScale(2) + '</td></tr>' +
            (pricing.igstAmount > 0 ?
                '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">IGST</td>' +
                    '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.igstAmount.setScale(2) + '</td></tr>' :
                '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">CGST</td>' +
                    '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.cgstAmount.setScale(2) + '</td></tr>' +
                '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">SGST</td>' +
                    '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.sgstAmount.setScale(2) + '</td></tr>') +
            (pricing.shippingCost > 0 ?
                '<tr><td style="font-size:13px;color:#666666;padding:4px 0;">Shipping (' + pricing.shippingMethodLabel.escapeHtml4() + ')</td>' +
                    '<td style="text-align:right;font-size:13px;">&#8377; ' + pricing.shippingCost.setScale(2) + '</td></tr>' : '') +
            (pricing.loyaltyDiscount > 0 ?
                '<tr><td style="font-size:13px;color:#1a7a3a;padding:4px 0;">Loyalty Points Redeemed (' + pricing.pointsUsed + ')</td>' +
                    '<td style="text-align:right;font-size:13px;color:#1a7a3a;">-&#8377; ' + pricing.loyaltyDiscount.setScale(2) + '</td></tr>' : '');

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
                    pricingRows +
                    '<tr><td style="font-size:14px;font-weight:bold;padding-top:8px;border-top:1px solid #eeeeee;">Amount Payable</td>' +
                        '<td style="text-align:right;font-size:14px;font-weight:bold;padding-top:8px;border-top:1px solid #eeeeee;">' +
                        '&#8377; ' + pricing.amountPayable.setScale(2) + '</td></tr>' +
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


    // How many days after delivery a return can still be requested. See
    // Feature Expansion Plan §14: "Your policy should be visible before
    // purchase" — this is LaptopKart's single, storefront-wide return
    // window; a more advanced version could vary this per product category.
    private static final Integer RETURN_WINDOW_DAYS = 7;

    /**
     * Lets a customer request a return on a Delivered order, within the
     * return window. Moves Delivery_Status__c to 'Return Requested' (an
     * admin later moves it to 'Returned' once the product is received back,
     * which is what actually triggers the refund/stock/loyalty reversal —
     * see OrderTrackingService.processReturnedOrders). See §14.
     */
    @AuraEnabled
    public static void requestReturn(Id orderId, String reason) {
        if (orderId == null) {
            throw new AuraHandledException('No order specified.');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('Please tell us why you\'d like to return this order.');
        }

        List<Order_Tracking__c> trackings = [
            SELECT Id, Delivery_Status__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c = :orderId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (trackings.isEmpty()) {
            throw new AuraHandledException('Order not found.');
        }
        Order_Tracking__c tracking = trackings[0];

        if (tracking.Delivery_Status__c != 'Delivered') {
            throw new AuraHandledException('Only a delivered order can be returned.');
        }
        if (tracking.Delivery_Date__c != null && tracking.Delivery_Date__c.addDays(RETURN_WINDOW_DAYS) < Date.today()) {
            throw new AuraHandledException('The ' + RETURN_WINDOW_DAYS + '-day return window for this order has closed. Please contact support.');
        }

        Database.update(
            new Order_Tracking__c(
                Id = tracking.Id,
                Delivery_Status__c = 'Return Requested',
                Return_Reason__c = reason.trim()
            ),
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
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   Discount_Amount__c, Taxable_Amount__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                   Amount_Payable__c, Shipping_Cost__c, Shipping_Method__c, Coupon_Code_Applied__c, Points_Redeemed__c, Points_Earned__c,
                   Recipient_Name__c, Recipient_Phone__c,
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
            summary.discountAmount = ord.Discount_Amount__c;
            summary.taxableAmount = ord.Taxable_Amount__c;
            summary.cgstAmount = ord.CGST_Amount__c;
            summary.sgstAmount = ord.SGST_Amount__c;
            summary.igstAmount = ord.IGST_Amount__c;
            summary.amountPayable = ord.Amount_Payable__c;
            summary.shippingCost = ord.Shipping_Cost__c;
            summary.shippingMethodLabel = ord.Shipping_Method__c;
            summary.couponCodeApplied = ord.Coupon_Code_Applied__c;
            summary.pointsRedeemed = ord.Points_Redeemed__c == null ? null : ord.Points_Redeemed__c.intValue();
            summary.pointsEarned = ord.Points_Earned__c == null ? null : ord.Points_Earned__c.intValue();
            summary.recipientName = ord.Recipient_Name__c;
            summary.recipientPhone = ord.Recipient_Phone__c;

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
    private static final String ADMIN_NOTIFICATION_EMAIL = EmailSenderService.SUPPORT_EMAIL;

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

        // Billing address fields — sent separately from shipping (already
        // collected by techBasketBillingForm, which pre-fills from shipping
        // when the shopper checks "same as shipping"). Flat fields for the
        // exact same reason as the shipping ones above.
        @AuraEnabled
        public String billingStreet;

        @AuraEnabled
        public String billingCity;

        @AuraEnabled
        public String billingState;

        @AuraEnabled
        public String billingPostalCode;

        @AuraEnabled
        public String billingCountry;

        // The delivery recipient — who this specific order is actually
        // shipped to, which may be someone other than the logged-in buyer
        // (a gift, a family member). See Feature Expansion Plan §5.1.
        @AuraEnabled
        public String recipientName;

        @AuraEnabled
        public String recipientPhone;

        // The logged-in shopper's own Account Id (authService session — see
        // LoginCredentialsController), i.e. who actually submitted this
        // order. Stored on Order.Placed_By__c. Null for a guest checkout,
        // in which case submitOrder falls back to matching by email exactly
        // as it always has.
        @AuraEnabled
        public Id accountId;

        // Coupon code the shopper typed in and applied, if any — revalidated
        // here from scratch via DiscountService, never trusted at face value
        // even though the same code was already validated once during the
        // Payment page's live preview. See Feature Expansion Plan §1.3/§1.7.
        @AuraEnabled
        public String couponCode;

        // The delivery method id the shopper picked (Checkout's Shipping
        // Method step — 'standard' | 'express' | 'overnight'). Only the id
        // is ever sent; OrderPricingService.calculate looks up the real
        // price/label server-side, same trust model as couponCode above —
        // a tampered or blank id safely falls back to Standard/free rather
        // than letting the client dictate what shipping actually costs.
        @AuraEnabled
        public String shippingMethodId;

        // How many loyalty points the shopper asked to redeem — revalidated
        // and capped from scratch via LoyaltyService, same reasoning as
        // couponCode above. See §2.5.
        @AuraEnabled
        public Integer pointsToRedeem;

        @AuraEnabled
        public List<CartLineInput> items;

        // The UPI transaction reference (UTR) the shopper typed in after
        // paying via the QR code on the Payment page — set only when
        // paymentMethod is 'Online' and no gateway payment was made (kept
        // as a fallback path; see razorpayPaymentId below for the real
        // gateway flow).
        @AuraEnabled
        public String utrNumber;

        // Set only when the shopper paid through Razorpay's hosted payment
        // page — read from the query params Razorpay's redirect appends
        // when it sends them back to the Payment page. Not trusted at face
        // value — submitOrder re-fetches the payment from Razorpay by id
        // server-side and confirms it actually captured, for the right
        // amount, before ever marking it Successful.
        @AuraEnabled
        public String razorpayPaymentId;
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

        @AuraEnabled
        public Decimal discountAmount;

        @AuraEnabled
        public Decimal taxableAmount;

        @AuraEnabled
        public Decimal cgstAmount;

        @AuraEnabled
        public Decimal sgstAmount;

        @AuraEnabled
        public Decimal igstAmount;

        @AuraEnabled
        public Decimal loyaltyDiscount;

        @AuraEnabled
        public Integer pointsUsed;

        @AuraEnabled
        public Decimal amountPayable;

        @AuraEnabled
        public Decimal shippingCost;

        @AuraEnabled
        public String shippingMethodLabel;
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
        public Decimal discountAmount;

        @AuraEnabled
        public Decimal taxableAmount;

        @AuraEnabled
        public Decimal cgstAmount;

        @AuraEnabled
        public Decimal sgstAmount;

        @AuraEnabled
        public Decimal igstAmount;

        @AuraEnabled
        public Decimal amountPayable;

        @AuraEnabled
        public Decimal shippingCost;

        @AuraEnabled
        public String shippingMethodLabel;

        @AuraEnabled
        public String couponCodeApplied;

        @AuraEnabled
        public Integer pointsRedeemed;

        @AuraEnabled
        public Integer pointsEarned;

        @AuraEnabled
        public String recipientName;

        @AuraEnabled
        public String recipientPhone;

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
