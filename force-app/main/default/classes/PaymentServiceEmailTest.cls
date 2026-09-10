@isTest(SeeAllData=true)
private class PaymentServiceEmailTest {

    /**
     * Exercises the real trigger path — marking a Payment__c 'Successful'
     * fires PaymentTriggerHandler -> PaymentService.sendPaymentConfirmationEmails
     * — end to end, to catch any bug in the newly-added Order_Tracking__c
     * query, OrderItems subquery, or HTML body builder. Test.isRunningTest()
     * makes Messaging.sendEmail a no-op and getContentAsPDF() return a dummy
     * blob, so this never sends a real email or spends any org email quota.
     */
    @isTest
    static void markingPaymentSuccessfulSendsConfirmationWithoutError() {
        User guestUser = [SELECT Id FROM User WHERE UserType = 'Guest' AND IsActive = true LIMIT 1];

        PricebookEntry pbe = [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = true AND IsActive = true AND Product2.IsActive = true
            LIMIT 1
        ];

        Id orderId;

        System.runAs(guestUser) {
            String inputJson = '{"customerName":"Payment Email Test","customerEmail":"payment-email-test@example.com",'
                + '"customerPhone":"9999900000","paymentMethod":"Online","utrNumber":"UTR1234567890",'
                + '"shippingStreet":"1 Test Lane","shippingCity":"Noida","shippingState":"Uttar Pradesh",'
                + '"shippingPostalCode":"201301","shippingCountry":"India",'
                + '"items":[{"productId":"' + pbe.Product2Id + '","quantity":1}]}';

            CheckoutController.OrderResult result = CheckoutController.submitOrder(inputJson);
            orderId = result.orderId;
        }

        Payment__c payment = [SELECT Id, Payment_Status__c FROM Payment__c WHERE Order__c = :orderId LIMIT 1];

        Test.startTest();
        payment.Payment_Status__c = 'Successful';
        update payment;
        Test.stopTest();

        Order updatedOrder = [SELECT Payment_Status__c FROM Order WHERE Id = :orderId];
        System.assertEquals('Fully Paid', updatedOrder.Payment_Status__c, 'Marking the payment Successful must roll the Order up to Fully Paid.');
    }
}
