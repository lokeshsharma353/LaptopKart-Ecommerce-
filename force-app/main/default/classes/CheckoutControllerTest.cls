@isTest(SeeAllData=true)
private class CheckoutControllerTest {

    // Real checkout always runs as the site's Guest User, and needs real
    // Product2/PricebookEntry data — matches the pattern already established
    // in OrderInvoiceControllerTest for the same reasons (System.runAs to
    // simulate the exact identity checkout uses, SeeAllData since standard
    // pricing data isn't creatable/visible from a plain @isTest).
    private static User getGuestUser() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
    }

    private static PricebookEntry getActivePricebookEntry() {
        return [
            SELECT Id, Product2Id, Product2.Name, Product2.Price__c, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.IsActive = true
            LIMIT 1
        ];
    }

    // Matches CheckoutController's own STEP 4 preference exactly: Product2.
    // Price__c is the real source of truth now, UnitPrice is only a fallback
    // for a product that predates this field.
    private static Decimal expectedUnitPrice(PricebookEntry pbe) {
        return pbe.Product2.Price__c != null ? pbe.Product2.Price__c : pbe.UnitPrice;
    }

    private static String buildOrderJson(PricebookEntry pbe, String email, String paymentMethod, String utr) {
        return '{"customerName":"Test Customer","customerEmail":"' + email + '",'
            + '"customerPhone":"9999900000","paymentMethod":"' + paymentMethod + '",'
            + '"shippingStreet":"1 Test Lane","shippingCity":"Noida","shippingState":"Uttar Pradesh",'
            + '"shippingPostalCode":"201301","shippingCountry":"India",'
            + '"utrNumber":"' + (utr == null ? '' : utr) + '",'
            + '"items":[{"productId":"' + pbe.Product2Id + '","quantity":2}]}';
    }


    @isTest
    /** A Cash-on-Delivery checkout creates a correct Order, OrderItem, Pending tracking record, and Pending payment with a generated transaction id. */
    static void submitOrderCreatesFullOrderPipelineForCashOnDelivery() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        CheckoutController.OrderResult result;

        System.runAs(guestUser) {
            String inputJson = buildOrderJson(pbe, 'cod-customer@example.com', 'Cash', null);

            Test.startTest();
            result = CheckoutController.submitOrder(inputJson);
            Test.stopTest();
        }

        System.assertNotEquals(null, result.orderId, 'Order should have been created.');
        System.assertNotEquals(null, result.orderNumber, 'Order number should be populated.');
        System.assertNotEquals(null, result.trackingNumber, 'Tracking number should be generated.');
        System.assertEquals(Date.today().addDays(5), result.deliveryDate, 'Delivery date should be 5 days out.');
        System.assertEquals(expectedUnitPrice(pbe) * 2, result.totalAmount, 'Total should be unit price x quantity.');

        Order ord = [SELECT Id, Status, TotalAmount, ShippingCity, Website_Order__c FROM Order WHERE Id = :result.orderId];
        System.assertEquals('Activated', ord.Status, 'Order should be activated by checkout.');
        System.assertEquals('Noida', ord.ShippingCity, 'Shipping city should be saved.');
        System.assertEquals(true, ord.Website_Order__c, 'Order must be flagged as a website order.');

        List<OrderItem> items = [SELECT Quantity, UnitPrice FROM OrderItem WHERE OrderId = :result.orderId];
        System.assertEquals(1, items.size(), 'One order line should exist.');
        System.assertEquals(2, items[0].Quantity, 'Quantity should match cart input.');

        Order_Tracking__c tracking = [SELECT Delivery_Status__c, Tracking_NUmber__c FROM Order_Tracking__c WHERE Order__c = :result.orderId];
        System.assertEquals('Pending', tracking.Delivery_Status__c, 'New tracking should start Pending.');

        Payment__c payment = [SELECT Payment_Method__c, Payment_Status__c, Transaction_ID__c FROM Payment__c WHERE Order__c = :result.orderId];
        System.assertEquals('Cash', payment.Payment_Method__c, 'Payment method should be Cash.');
        System.assertEquals('Pending', payment.Payment_Status__c, 'Payment starts Pending regardless of method.');
        System.assert(payment.Transaction_ID__c.startsWith('TXN'), 'COD should get a generated placeholder transaction id.');
    }


    @isTest
    /** An Online checkout keeps the shopper-entered UTR as the payment's transaction id, instead of generating a placeholder. */
    static void submitOrderUsesRealUtrForOnlinePayment() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        CheckoutController.OrderResult result;

        System.runAs(guestUser) {
            String inputJson = buildOrderJson(pbe, 'online-customer@example.com', 'Online', 'UTR123456789');

            Test.startTest();
            result = CheckoutController.submitOrder(inputJson);
            Test.stopTest();
        }

        Payment__c payment = [SELECT Payment_Method__c, Transaction_ID__c FROM Payment__c WHERE Order__c = :result.orderId];
        System.assertEquals('Online', payment.Payment_Method__c, 'Payment method should be Online.');
        System.assertEquals('UTR123456789', payment.Transaction_ID__c, 'Online payment should keep the shopper-entered UTR.');
    }


    @isTest
    /** A second order from the same email reuses that customer's existing Account instead of creating a duplicate. */
    static void submitOrderReusesExistingAccountForReturningCustomer() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        Id firstOrderId;
        Id secondOrderId;

        System.runAs(guestUser) {
            String firstJson = buildOrderJson(pbe, 'returning-customer@example.com', 'Cash', null);
            Test.startTest();
            CheckoutController.OrderResult firstResult = CheckoutController.submitOrder(firstJson);
            firstOrderId = firstResult.orderId;

            String secondJson = buildOrderJson(pbe, 'returning-customer@example.com', 'Online', 'UTR000111');
            CheckoutController.OrderResult secondResult = CheckoutController.submitOrder(secondJson);
            secondOrderId = secondResult.orderId;
            Test.stopTest();
        }

        // Queried as the running test user (not the Guest User) — ownership of
        // both Orders was already reassigned to the admin inside submitOrder's
        // final step, and Guest User criteria-based sharing-rule recalculation
        // isn't guaranteed to have caught up within the same transaction (see
        // OrderInvoiceController's own "without sharing" comment for the same
        // documented gap), so this avoids relying on it.
        Id firstAccountId = [SELECT AccountId FROM Order WHERE Id = :firstOrderId].AccountId;
        Id secondAccountId = [SELECT AccountId FROM Order WHERE Id = :secondOrderId].AccountId;

        System.assertEquals(firstAccountId, secondAccountId, 'A repeat customer must be linked to their existing Account, not a duplicate.');
    }


    @isTest
    /** Submitting an order with no cart items is rejected. */
    static void submitOrderRejectsEmptyCart() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Empty Cart","customerEmail":"empty@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Cash","shippingStreet":"1 Test Lane",'
                + '"shippingCity":"Noida","shippingState":"Uttar Pradesh","shippingPostalCode":"201301",'
                + '"shippingCountry":"India","items":[]}';

            Boolean threw = false;
            try {
                Test.startTest();
                CheckoutController.submitOrder(inputJson);
                Test.stopTest();
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw, 'An empty cart must be rejected.');
        }
    }


    @isTest
    /** Malformed checkout JSON is rejected with a friendly error, not an unhandled exception. */
    static void submitOrderRejectsMalformedJson() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            Boolean threw = false;
            try {
                Test.startTest();
                CheckoutController.submitOrder('{not valid json');
                Test.stopTest();
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw, 'Malformed JSON must be rejected with a friendly error, not an unhandled exception.');
        }
    }


    @isTest
    /** A cart whose only item has no matching PricebookEntry (so nothing is actually purchasable) is rejected. */
    static void submitOrderRejectsCartWithNoAvailableProducts() {
        User guestUser = getGuestUser();

        System.runAs(guestUser) {
            // A syntactically valid but nonexistent product id — no matching
            // PricebookEntry means every line gets skipped, leaving an
            // effectively empty order.
            String inputJson = '{"customerName":"No Product","customerEmail":"noproduct@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Cash","shippingStreet":"1 Test Lane",'
                + '"shippingCity":"Noida","shippingState":"Uttar Pradesh","shippingPostalCode":"201301",'
                + '"shippingCountry":"India","items":[{"productId":"01t000000000000AAA","quantity":1}]}';

            Boolean threw = false;
            try {
                Test.startTest();
                CheckoutController.submitOrder(inputJson);
                Test.stopTest();
            } catch (Exception e) {
                threw = true;
            }
            System.assert(threw, 'An order with no purchasable lines must be rejected.');
        }
    }


    @isTest
    /** Cancelling an order sets its Status to Cancelled and cascades to mark its tracking record Cancelled too. */
    static void cancelOrderMarksOrderAndTrackingCancelled() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        Id orderId;

        System.runAs(guestUser) {
            String inputJson = buildOrderJson(pbe, 'cancel-customer@example.com', 'Cash', null);
            Test.startTest();
            CheckoutController.OrderResult result = CheckoutController.submitOrder(inputJson);
            orderId = result.orderId;

            CheckoutController.cancelOrder(orderId);
            Test.stopTest();
        }

        Order ord = [SELECT Status FROM Order WHERE Id = :orderId];
        System.assertEquals('Cancelled', ord.Status, 'Order should be cancelled.');

        Order_Tracking__c tracking = [SELECT Delivery_Status__c FROM Order_Tracking__c WHERE Order__c = :orderId];
        System.assertEquals('Cancelled', tracking.Delivery_Status__c, 'Tracking should follow the order to Cancelled.');
    }


    @isTest
    /** Cancelling an order that's already Cancelled is rejected. */
    static void cancelOrderRejectsAlreadyCancelledOrder() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        System.runAs(guestUser) {
            String inputJson = buildOrderJson(pbe, 'double-cancel@example.com', 'Cash', null);
            Test.startTest();
            CheckoutController.OrderResult result = CheckoutController.submitOrder(inputJson);
            CheckoutController.cancelOrder(result.orderId);

            Boolean threw = false;
            try {
                CheckoutController.cancelOrder(result.orderId);
            } catch (AuraHandledException e) {
                threw = true;
            }
            Test.stopTest();
            System.assert(threw, 'Cancelling an already-cancelled order must be rejected.');
        }
    }


    @isTest
    /** cancelOrder rejects a null order id and an id that doesn't match any real Order. */
    static void cancelOrderRejectsNullAndUnknownId() {
        Boolean threwOnNull = false;
        try {
            CheckoutController.cancelOrder(null);
        } catch (AuraHandledException e) {
            threwOnNull = true;
        }
        System.assert(threwOnNull, 'A null order id must be rejected.');

        // A syntactically valid Order Id that does not exist.
        Boolean threwOnUnknown = false;
        try {
            CheckoutController.cancelOrder('801000000000000AAA');
        } catch (AuraHandledException e) {
            threwOnUnknown = true;
        }
        System.assert(threwOnUnknown, 'An unknown order id must be rejected.');
    }


    @isTest
    /** getOrdersByEmail returns exactly that customer's own website order(s), with correct summary and line-item detail. */
    static void getOrdersByEmailReturnsOnlyThatCustomersWebsiteOrders() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();

        List<CheckoutController.OrderSummary> summaries;

        System.runAs(guestUser) {
            String inputJson = buildOrderJson(pbe, 'history-customer@example.com', 'Online', 'UTR999888');
            Test.startTest();
            CheckoutController.submitOrder(inputJson);
            Test.stopTest();

            summaries = CheckoutController.getOrdersByEmail('history-customer@example.com');
        }

        System.assertEquals(1, summaries.size(), 'Exactly one order should be found for this email.');
        CheckoutController.OrderSummary summary = summaries[0];
        System.assertEquals('Activated', summary.status, 'Status should reflect the activated order.');
        System.assertEquals('Online', summary.paymentMethod, 'Payment method should carry through to the summary.');
        System.assertEquals('UTR999888', summary.transactionId, 'Transaction id should carry through to the summary.');
        System.assertEquals(1, summary.items.size(), 'One line item should be on the summary.');
        System.assertEquals(pbe.Product2.Name, summary.items[0].productName, 'Product name should resolve correctly.');
        System.assertNotEquals(null, summary.trackingNumber, 'Tracking number should be present on the summary.');
        System.assert(summary.shippingAddressLine.contains('Noida'), 'Shipping address line should include the city.');
    }


    @isTest
    /** getOrdersByEmail returns an empty list for a null, blank, or unrecognized email. */
    static void getOrdersByEmailReturnsEmptyForBlankOrUnknownEmail() {
        System.assertEquals(0, CheckoutController.getOrdersByEmail(null).size(), 'Null email must return no orders.');
        System.assertEquals(0, CheckoutController.getOrdersByEmail('').size(), 'Blank email must return no orders.');
        System.assertEquals(0, CheckoutController.getOrdersByEmail('nobody-at-all@example.com').size(), 'Unknown email must return no orders.');
    }


    @isTest
    /** getOrders returns an empty list for a null or empty order-id list. */
    static void getOrdersReturnsEmptyForNullOrEmptyIdList() {
        System.assertEquals(0, CheckoutController.getOrders(null).size(), 'Null id list must return no orders.');
        System.assertEquals(0, CheckoutController.getOrders(new List<Id>()).size(), 'Empty id list must return no orders.');
    }


    /** Creates an active, dated discount Campaign + Coupon_Code__c for the pricing tests below. See Feature Expansion Plan §1. */
    private static Coupon_Code__c createTestCoupon(String code, String discountType, Decimal discountValue, Decimal minOrder, Decimal maxDiscount) {
        return createTestCoupon(code, discountType, discountValue, minOrder, maxDiscount, null);
    }

    /** Same as above, but restricted to one Product2.Family category — see Eligible_Category__c. */
    private static Coupon_Code__c createTestCoupon(String code, String discountType, Decimal discountValue, Decimal minOrder, Decimal maxDiscount, String eligibleCategory) {
        Campaign campaign = new Campaign(
            Name = 'Test Discount Campaign ' + code,
            IsActive = true,
            Status = 'Active',
            StartDate = Date.today().addDays(-1),
            EndDate = Date.today().addDays(30),
            Discount_Type__c = discountType,
            Discount_Value__c = discountValue,
            Minimum_Order_Value__c = minOrder,
            Maximum_Discount_Amount__c = maxDiscount,
            Eligible_Category__c = eligibleCategory
        );
        insert campaign;

        Coupon_Code__c coupon = new Coupon_Code__c(
            Code__c = code,
            Campaign__c = campaign.Id,
            Is_Active__c = true,
            Max_Uses_Per_Customer__c = 1
        );
        insert coupon;
        return coupon;
    }


    @isTest
    /** A valid coupon reduces Discount_Amount__c/Amount_Payable__c, and GST is calculated on the discounted (taxable) value, not the raw subtotal. */
    static void submitOrderAppliesCouponAndCalculatesGst() {
        User guestUser = getGuestUser();
        PricebookEntry pbe = getActivePricebookEntry();
        Coupon_Code__c coupon = createTestCoupon('TESTSAVE10', 'Percentage', 10, null, null);

        CheckoutController.OrderResult result;

        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Coupon Test","customerEmail":"coupon-test@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Cash","shippingStreet":"1 Test Lane",'
                + '"shippingCity":"Noida","shippingState":"Uttar Pradesh","shippingPostalCode":"201301",'
                + '"shippingCountry":"India","couponCode":"' + coupon.Code__c + '",'
                + '"items":[{"productId":"' + pbe.Product2Id + '","quantity":2}]}';

            Test.startTest();
            result = CheckoutController.submitOrder(inputJson);
            Test.stopTest();
        }

        Decimal subtotal = expectedUnitPrice(pbe) * 2;
        Decimal expectedDiscount = (subtotal * 0.10).setScale(2, System.RoundingMode.HALF_UP);

        Order ord = [
            SELECT Discount_Amount__c, Taxable_Amount__c, CGST_Amount__c, SGST_Amount__c,
                   IGST_Amount__c, Amount_Payable__c, Coupon_Code_Applied__c
            FROM Order WHERE Id = :result.orderId
        ];

        System.assertEquals(expectedDiscount, ord.Discount_Amount__c, 'A 10% coupon must discount exactly 10% of the subtotal.');
        System.assertEquals('TESTSAVE10', ord.Coupon_Code_Applied__c, 'The applied coupon code should be stamped on the order.');
        System.assertEquals(subtotal - expectedDiscount, ord.Taxable_Amount__c, 'Taxable value must be subtotal minus the discount.');
        System.assert(ord.CGST_Amount__c > 0 || ord.IGST_Amount__c > 0, 'GST must be calculated on the taxable value.');
        System.assertEquals(
            (ord.Taxable_Amount__c + ord.CGST_Amount__c + ord.SGST_Amount__c + ord.IGST_Amount__c).setScale(2),
            ord.Amount_Payable__c.setScale(2),
            'Amount payable must equal taxable value plus GST when no loyalty points were redeemed.'
        );

        // Coupon is capped to one use per customer — a second attempt by the
        // same account must be rejected by the live server preview. Queried
        // as the running test user (admin), not the Guest User — see
        // submitOrderReusesExistingAccountForReturningCustomer above for why:
        // ownership was already reassigned to the admin inside submitOrder's
        // final step, and Guest User criteria-based sharing-rule
        // recalculation isn't guaranteed to have caught up within the same
        // transaction.
        Id accountId = [SELECT AccountId FROM Order WHERE Id = :result.orderId].AccountId;

        OrderPricingService.PricingLine line = new OrderPricingService.PricingLine();
        line.productId = pbe.Product2Id;
        line.quantity = 1;
        line.unitPrice = expectedUnitPrice(pbe);
        line.gstRatePercent = null;
        line.lineSubtotal = expectedUnitPrice(pbe);

        OrderPricingService.PricingResult repeatPreview = OrderPricingService.calculate(
            new List<OrderPricingService.PricingLine>{ line }, 'Uttar Pradesh', accountId, 'TESTSAVE10', null, null
        );
        System.assertEquals(false, repeatPreview.couponValid, 'The same customer must not be able to reuse a single-use coupon.');
    }


    @isTest
    /** A Percentage coupon's discount is capped at Maximum_Discount_Amount__c. */
    static void couponDiscountIsCappedByMaximumDiscountAmount() {
        createTestCoupon('TESTCAP', 'Percentage', 50, null, 100);

        DiscountService.CouponPreview preview = DiscountService.validate('TESTCAP', null, 10000, new Map<String, Decimal>());
        System.assertEquals(true, preview.valid, 'Coupon should validate against a sufficient subtotal.');
        System.assertEquals(100, preview.discountAmount, '50% of Rs. 10,000 (Rs. 5,000) must be capped down to the Rs. 100 maximum.');
    }


    @isTest
    /** A coupon is rejected when the cart subtotal is below Minimum_Order_Value__c. */
    static void couponRejectsOrderBelowMinimumValue() {
        createTestCoupon('TESTMIN', 'Flat Amount', 500, 20000, null);

        DiscountService.CouponPreview preview = DiscountService.validate('TESTMIN', null, 5000, new Map<String, Decimal>());
        System.assertEquals(false, preview.valid, 'A coupon with a minimum order value must reject a smaller cart.');
        System.assert(preview.message.contains('Minimum purchase'), 'Rejection message should explain the minimum order requirement.');
    }


    @isTest
    /**
     * A category-restricted coupon (10% off Laptops only) discounts only the
     * Laptop line's GST-taxable value — an Accessory line in the same cart
     * must come through completely untouched, even though its spend still
     * counted toward the minimum order gate. Matches the discount system's
     * own worked example (Laptop ₹50,000 + Earbuds ₹2,000 → only the laptop
     * portion is discounted).
     */
    static void categoryRestrictedCouponOnlyDiscountsMatchingLines() {
        createTestCoupon('TESTLAPTOP', 'Percentage', 10, 30000, 5000, 'Laptop');

        OrderPricingService.PricingLine laptopLine = new OrderPricingService.PricingLine();
        laptopLine.productId = null;
        laptopLine.quantity = 1;
        laptopLine.unitPrice = 50000;
        laptopLine.gstRatePercent = 18;
        laptopLine.lineSubtotal = 50000;
        laptopLine.category = 'Laptop';

        OrderPricingService.PricingLine accessoryLine = new OrderPricingService.PricingLine();
        accessoryLine.productId = null;
        accessoryLine.quantity = 1;
        accessoryLine.unitPrice = 2000;
        accessoryLine.gstRatePercent = 18;
        accessoryLine.lineSubtotal = 2000;
        accessoryLine.category = 'Accessory';

        OrderPricingService.PricingResult result = OrderPricingService.calculate(
            new List<OrderPricingService.PricingLine>{ laptopLine, accessoryLine },
            'Uttar Pradesh', null, 'TESTLAPTOP', null, null
        );

        System.assertEquals(true, result.couponValid, 'The coupon should validate — cart subtotal (Rs. 52,000) meets the Rs. 30,000 minimum, and a Laptop line is present.');
        System.assertEquals(5000, result.discountAmount, '10% of the Rs. 50,000 laptop line is Rs. 5,000, within the Rs. 5,000 cap.');
        System.assertEquals(47000, result.taxableAmount, 'Taxable value must be the full Rs. 52,000 cart minus only the Rs. 5,000 laptop discount.');

        // GST must reflect the laptop's own taxable value dropping to
        // Rs. 45,000 while the accessory's stays the full Rs. 2,000 —
        // proving the discount was never spread onto the accessory line.
        Decimal expectedGst = (45000 * 0.18) + (2000 * 0.18);
        System.assertEquals(expectedGst.setScale(2), result.gstAmount, 'GST must be computed per line on each line\'s own (correctly discounted or undiscounted) taxable value.');
    }


    @isTest
    /** A category-restricted coupon is rejected when the cart has no line in that category, even if the cart otherwise meets the minimum order value. */
    static void categoryRestrictedCouponRejectsCartWithNoMatchingCategory() {
        createTestCoupon('TESTPHONE', 'Percentage', 10, 1000, null, 'Mobile');

        OrderPricingService.PricingLine laptopLine = new OrderPricingService.PricingLine();
        laptopLine.productId = null;
        laptopLine.quantity = 1;
        laptopLine.unitPrice = 50000;
        laptopLine.gstRatePercent = 18;
        laptopLine.lineSubtotal = 50000;
        laptopLine.category = 'Laptop';

        OrderPricingService.PricingResult result = OrderPricingService.calculate(
            new List<OrderPricingService.PricingLine>{ laptopLine },
            'Uttar Pradesh', null, 'TESTPHONE', null, null
        );

        System.assertEquals(false, result.couponValid, 'A Mobile-only coupon must reject a cart with only a Laptop line.');
        System.assertEquals(0, result.discountAmount, 'No discount should apply when the coupon is rejected.');
    }
}
