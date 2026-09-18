/**
 * Thin wrapper around the Razorpay REST API. Every call goes through the
 * "Razorpay" Named Credential, which injects the Key Id / Key Secret as
 * HTTP Basic Auth automatically — this class never sees the raw secret,
 * and neither does any Salesforce code.
 *
 * Uses Razorpay's Payment Links product rather than the embedded
 * Checkout.js widget: this org's Lightning Web Security blocks the dynamic
 * <script> injection Checkout.js needs (confirmed directly — no CSP
 * Trusted Site script-src option exists here even in the Setup UI), so the
 * Payment page instead redirects the shopper to Razorpay's own hosted
 * payment page (same live QR / card / UPI options, same auto-detect
 * completion) and Razorpay redirects back once they're done. No
 * third-party script ever needs to load inside the Salesforce page.
 *
 * Two calls:
 *  - createPaymentLink: called before redirecting, to get the hosted URL.
 *  - fetchPayment: called after the shopper returns, to re-confirm
 *    directly with Razorpay that the payment actually captured, rather
 *    than trusting the redirect's own query parameters at face value.
 */
public without sharing class RazorpayService {

    private static final String NAMED_CREDENTIAL = 'callout:Razorpay';

    public class RazorpayException extends Exception {}

    /** Just enough for the frontend to redirect the shopper to Razorpay's hosted page. */
    public class PaymentLinkResult {
        @AuraEnabled public String paymentLinkId;
        @AuraEnabled public String shortUrl;
    }

    /**
     * Creates a Razorpay Payment Link for the given amount.
     * @param amountRupees - order total in rupees (e.g. 1999.00) — always
     *        computed server-side from the cart, never a client-supplied value.
     * @param customerName
     * @param customerEmail
     * @param customerPhone
     * @param callbackUrl - the Payment page's own URL; Razorpay redirects the
     *        shopper back here (with its own query params appended) once
     *        they've paid or cancelled.
     * @return PaymentLinkResult with the hosted page URL to redirect to
     */
    public static PaymentLinkResult createPaymentLink(
        Decimal amountRupees,
        String customerName,
        String customerEmail,
        String customerPhone,
        String callbackUrl
    ) {
        Integer amountPaise = Integer.valueOf((amountRupees * 100).setScale(0));

        Map<String, Object> body = new Map<String, Object>{
            'amount' => amountPaise,
            'currency' => 'INR',
            'description' => 'LaptopKart Order Payment',
            'customer' => new Map<String, Object>{
                'name' => customerName,
                'email' => customerEmail,
                'contact' => customerPhone
            },
            'notify' => new Map<String, Object>{ 'sms' => false, 'email' => false },
            'reminder_enable' => false,
            'callback_url' => callbackUrl,
            'callback_method' => 'get'
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/payment_links');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Razorpay createPaymentLink failed: ' + res.getStatusCode() + ' ' + res.getBody());
            throw new RazorpayException('Razorpay createPaymentLink failed: ' + res.getStatusCode());
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        PaymentLinkResult result = new PaymentLinkResult();
        result.paymentLinkId = (String) parsed.get('id');
        result.shortUrl = (String) parsed.get('short_url');
        return result;
    }

    /** What actually happened to a payment, straight from Razorpay — the source of truth. */
    public class PaymentDetails {
        public String paymentId;
        /** e.g. 'created', 'authorized', 'captured', 'failed', 'refunded'. */
        public String status;
        public Integer amountInPaise;
    }

    /**
     * Re-fetches a payment directly from Razorpay by id.
     * @param razorpayPaymentId - the payment id Razorpay's redirect returned
     */
    public static PaymentDetails fetchPayment(String razorpayPaymentId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/payments/' + EncodingUtil.urlEncode(razorpayPaymentId, 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Razorpay fetchPayment failed: ' + res.getStatusCode() + ' ' + res.getBody());
            throw new RazorpayException('Razorpay fetchPayment failed: ' + res.getStatusCode());
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        PaymentDetails details = new PaymentDetails();
        details.paymentId = (String) parsed.get('id');
        details.status = (String) parsed.get('status');
        details.amountInPaise = (Integer) parsed.get('amount');
        return details;
    }
}
