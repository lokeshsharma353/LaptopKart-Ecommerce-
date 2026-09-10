@isTest(SeeAllData=true)
private class OrderInvoiceControllerTest {

    /**
     * Mirrors production exactly: real checkout always runs as the site's
     * Guest User (System.runAs here), and the confirmation email's invoice
     * PDF is built the same way — Page.OrderInvoice with the order Id as a
     * parameter, feeding a fresh OrderInvoiceController query. This proves
     * (or disproves) whether the order/order-item/payment data is actually
     * visible to OrderInvoiceController when it runs as Guest, without ever
     * sending a real email or rendering a real PDF — Test.isRunningTest()
     * makes Messaging.sendEmail a no-op and getContentAsPDF() unusable in
     * test context either way, so this checks the controller's underlying
     * data directly instead.
     */
    @isTest
    static void invoiceControllerSeesFullOrderDataWhenRunningAsGuestUser() {
        User guestUser = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];

        PricebookEntry pbe = [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.IsActive = true
            LIMIT 1
        ];

        Id orderId;

        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Invoice Diagnostic","customerEmail":"invoice-diagnostic@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Cash","shippingStreet":"1 Diagnostic Lane",'
                + '"shippingCity":"Noida","shippingState":"Uttar Pradesh","shippingPostalCode":"201301",'
                + '"shippingCountry":"India","items":[{"productId":"' + pbe.Product2Id + '","quantity":1}]}';

            Test.startTest();
            CheckoutController.OrderResult result = CheckoutController.submitOrder(inputJson);
            orderId = result.orderId;
            Test.stopTest();
        }

        System.assertNotEquals(null, orderId, 'Order should have been created.');

        System.runAs(guestUser) {
            PageReference invoicePage = Page.OrderInvoice;
            invoicePage.getParameters().put('orderId', String.valueOf(orderId));
            Test.setCurrentPageReference(invoicePage);

            OrderInvoiceController controller = new OrderInvoiceController();

            System.assert(controller.getHasOrder(), 'OrderInvoiceController must find the order when running as the Guest User.');
            System.assertNotEquals(null, controller.ord, 'Order record must be populated.');
            System.assertEquals(1, controller.lineItems.size(), 'The one order line item must be visible to the Guest User.');
            System.assertNotEquals('', controller.getCustomerName(), 'Customer name must resolve to something real, not blank.');
            System.assert(controller.getIsCashOnDelivery(), 'This order was placed as Cash on Delivery.');
        }
    }
}
