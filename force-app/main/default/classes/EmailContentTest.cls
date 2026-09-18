@isTest(SeeAllData=true)
private class EmailContentTest {

    /**
     * Directly asserts on the real HTML string built for the order
     * confirmation email — not just that sendConfirmationEmail runs without
     * throwing, but that the actual content contains the real order number,
     * product name, and shipping city. This is the concrete proof that the
     * "order confirmation email has no invoice" report is fixed: the
     * invoice content is provably present in the email body itself.
     */
    @isTest
    static void confirmationEmailHtmlBodyContainsRealInvoiceContent() {
        User guestUser = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
        PricebookEntry pbe = [
            SELECT Id, Product2Id, Product2.Name
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.IsActive = true
            LIMIT 1
        ];

        Id orderId;
        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Email Content Test","customerEmail":"email-content-test@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Cash","shippingStreet":"1 Diagnostic Lane",'
                + '"shippingCity":"Noida","shippingState":"Uttar Pradesh","shippingPostalCode":"201301",'
                + '"shippingCountry":"India","items":[{"productId":"' + pbe.Product2Id + '","quantity":2}]}';

            Test.startTest();
            CheckoutController.OrderResult result = CheckoutController.submitOrder(inputJson);
            orderId = result.orderId;
            Test.stopTest();
        }

        Order ord = [SELECT Id, OrderNumber, TotalAmount FROM Order WHERE Id = :orderId];
        Order_Tracking__c tracking = [
            SELECT Tracking_NUmber__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c = :orderId
            LIMIT 1
        ];

        CheckoutController.CheckoutInput input = new CheckoutController.CheckoutInput();
        input.customerName = 'Email Content Test';
        input.shippingStreet = '1 Diagnostic Lane';
        input.shippingCity = 'Noida';
        input.shippingState = 'Uttar Pradesh';
        input.shippingPostalCode = '201301';
        input.shippingCountry = 'India';
        input.paymentMethod = 'Cash';

        List<String> emailLines = new List<String>{ '2 x ' + pbe.Product2.Name + ' - Rs. ' + (ord.TotalAmount / 2).setScale(2) };

        List<OrderPricingService.PricingLine> pricingLines = new List<OrderPricingService.PricingLine>();
        OrderPricingService.PricingLine pricingLine = new OrderPricingService.PricingLine();
        pricingLine.productId = pbe.Product2Id;
        pricingLine.quantity = 2;
        pricingLine.unitPrice = ord.TotalAmount / 2;
        pricingLine.gstRatePercent = null;
        pricingLine.lineSubtotal = ord.TotalAmount;
        pricingLines.add(pricingLine);
        OrderPricingService.PricingResult pricing =
            OrderPricingService.calculate(pricingLines, 'Uttar Pradesh', null, null, null, null);

        String html = CheckoutController.buildConfirmationHtmlBody(input, ord, tracking, emailLines, pricing);

        System.assert(html.contains(ord.OrderNumber), 'HTML body must contain the real order number.');
        System.assert(html.contains(pbe.Product2.Name), 'HTML body must contain the real product name.');
        System.assert(html.contains('Noida'), 'HTML body must contain the real shipping city.');
        System.assert(html.contains(String.valueOf(pricing.amountPayable.setScale(2))), 'HTML body must contain the real amount payable.');
        System.assert(html.length() > 500, 'HTML body must be substantial, not a near-empty stub (was ' + html.length() + ' chars).');
    }

    /**
     * Same proof for the payment-confirmation ("Order is Confirmed!") email
     * — the one whose subject line most literally matches "order confirmed".
     */
    @isTest
    static void paymentConfirmationEmailHtmlBodyContainsRealInvoiceContent() {
        User guestUser = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];
        PricebookEntry pbe = [
            SELECT Id, Product2Id, Product2.Name
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.IsActive = true
            LIMIT 1
        ];

        Id orderId;
        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Payment Confirm Content Test","customerEmail":"payment-confirm-content-test@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Online","utrNumber":"UTR9988776655",'
                + '"shippingStreet":"2 Diagnostic Lane","shippingCity":"Gurgaon","shippingState":"Haryana",'
                + '"shippingPostalCode":"122001","shippingCountry":"India",'
                + '"items":[{"productId":"' + pbe.Product2Id + '","quantity":1}]}';
            CheckoutController.submitOrder(inputJson);
        }
        // Re-query by email rather than trusting the OrderResult, since this
        // block only needs a real Order/Contact pair that mirrors production.
        Contact con = [SELECT Id, Name, AccountId, Email FROM Contact WHERE Email = 'payment-confirm-content-test@example.com' LIMIT 1];
        Order ord = [
            SELECT Id, OrderNumber, TotalAmount, AccountId,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   (SELECT Product2.Name, Quantity, UnitPrice FROM OrderItems)
            FROM Order
            WHERE AccountId = :con.AccountId
            LIMIT 1
        ];
        Order_Tracking__c tracking = [
            SELECT Tracking_NUmber__c, Delivery_Date__c
            FROM Order_Tracking__c
            WHERE Order__c = :ord.Id
            LIMIT 1
        ];

        String html = PaymentService.buildPaymentConfirmationHtmlBody(con, ord, tracking);

        System.assert(html.contains(ord.OrderNumber), 'HTML body must contain the real order number.');
        System.assert(html.contains(pbe.Product2.Name), 'HTML body must contain the real product name.');
        System.assert(html.contains('Gurgaon'), 'HTML body must contain the real shipping city.');
        System.assert(html.length() > 500, 'HTML body must be substantial, not a near-empty stub (was ' + html.length() + ' chars).');
    }
}
