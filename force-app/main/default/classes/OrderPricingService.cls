// without sharing: delegates straight into DiscountService/LoyaltyService,
// which are without sharing themselves for the same Guest-User reasons.
//
// The single pricing engine for a checkout: subtotal -> coupon discount ->
// taxable value -> GST (CGST+SGST or IGST) -> loyalty point redemption ->
// final amount payable, in that exact order (Feature Expansion Plan §3.1).
// Used identically by CheckoutController.previewOrderTotals (read-only, for
// the cart/payment UI) and CheckoutController.submitOrder (authoritative —
// this is what actually gets charged and verified). Both call sites pass the
// same product prices/GST rates looked up fresh from Product2 and the same
// coupon/points inputs, so as long as nothing about the cart or the coupon
// changes in between, a preview and the real charge agree exactly — but
// submitOrder never trusts the preview's own numbers; it always recalculates
// from scratch, same reasoning as DiscountService/LoyaltyService never
// trusting a client-supplied discount.
public without sharing class OrderPricingService {

    // Registered state of the seller — decides CGST+SGST (intrastate) vs
    // IGST (interstate) for a given shipping state (§3.6). Update this if
    // the business's registered state changes; a real multi-state seller
    // would look this up from configuration instead of a constant.
    public static final String SELLER_STATE = 'Delhi';

    // Applied when a Product2 has no GST_Rate__c set — 18% is the standard
    // GST slab for laptops/computers (HSN 8471) in India.
    public static final Decimal DEFAULT_GST_RATE_PERCENT = 18;

    // Canonical shipping method prices — must mirror the METHODS constant in
    // techBasketShippingMethod.js exactly (id -> {label, price}). The client
    // only ever sends the chosen method's id; the actual amount charged is
    // always looked up here, server-side, the same way a coupon's discount
    // or a loyalty redemption is never trusted from the client. An id that
    // doesn't match a known method (blank, tampered, or the shopper hasn't
    // reached that step yet) safely falls back to Standard/free rather than
    // failing the whole pricing preview.
    private static final Map<String, ShippingMethod> SHIPPING_METHODS = new Map<String, ShippingMethod>{
        'standard'  => new ShippingMethod('Standard Delivery', 0),
        'express'   => new ShippingMethod('Express Delivery', 500),
        'overnight' => new ShippingMethod('Overnight Delivery', 1500)
    };

    private class ShippingMethod {
        String label;
        Decimal price;
        ShippingMethod(String label, Decimal price) {
            this.label = label;
            this.price = price;
        }
    }

    /** Looks up a shipping method's real cost/label by id — defaults to Standard/free for an unrecognized or blank id. */
    private static ShippingMethod shippingMethodFor(String shippingMethodId) {
        if (String.isNotBlank(shippingMethodId) && SHIPPING_METHODS.containsKey(shippingMethodId)) {
            return SHIPPING_METHODS.get(shippingMethodId);
        }
        return SHIPPING_METHODS.get('standard');
    }

    /** One cart line's pricing inputs, already resolved server-side from Product2 — never from the browser. */
    public class PricingLine {
        public Id productId;
        public Integer quantity;
        public Decimal unitPrice;
        public Decimal gstRatePercent;
        public Decimal lineSubtotal;
        // Product2.Family — used only to match a coupon's Eligible_Category__c
        // (§1.2's category-specific discount type). Blank/unknown categories
        // simply never match a category-restricted coupon.
        public String category;
    }

    /** Full breakdown of a checkout's pricing — what previewOrderTotals returns to the UI, and what submitOrder charges/stores on the Order. */
    public class PricingResult {
        @AuraEnabled public Decimal subtotal = 0;
        @AuraEnabled public Decimal discountAmount = 0;
        @AuraEnabled public Decimal taxableAmount = 0;
        @AuraEnabled public Decimal cgstAmount = 0;
        @AuraEnabled public Decimal sgstAmount = 0;
        @AuraEnabled public Decimal igstAmount = 0;
        @AuraEnabled public Decimal gstAmount = 0;
        @AuraEnabled public Decimal shippingCost = 0;
        @AuraEnabled public String shippingMethodLabel;
        @AuraEnabled public Integer pointsUsed = 0;
        @AuraEnabled public Decimal loyaltyDiscount = 0;
        @AuraEnabled public Decimal amountPayable = 0;
        @AuraEnabled public Boolean couponValid = false;
        @AuraEnabled public String couponMessage;
        @AuraEnabled public String loyaltyMessage;
        @AuraEnabled public Integer loyaltyBalance = 0;
        @AuraEnabled public Id campaignId;
        @AuraEnabled public Id couponCodeId;
        @AuraEnabled public String couponCode;
    }

    public static PricingResult calculate(
        List<PricingLine> lines,
        String shippingState,
        Id accountId,
        String couponCode,
        Integer pointsRequested,
        String shippingMethodId
    ) {
        PricingResult result = new PricingResult();

        ShippingMethod shippingMethod = shippingMethodFor(shippingMethodId);
        result.shippingCost = shippingMethod.price;
        result.shippingMethodLabel = shippingMethod.label;

        Decimal subtotal = 0;
        for (PricingLine line : lines) {
            subtotal += line.lineSubtotal;
        }
        result.subtotal = subtotal.setScale(2, System.RoundingMode.HALF_UP);

        if (subtotal <= 0) {
            return result;
        }

        // Combined subtotal per Product2.Family — lets DiscountService find
        // the real discount base when a coupon is restricted to one category
        // (Eligible_Category__c) without discounting the rest of the cart.
        Map<String, Decimal> subtotalByCategory = new Map<String, Decimal>();
        for (PricingLine line : lines) {
            if (String.isNotBlank(line.category)) {
                Decimal current = subtotalByCategory.containsKey(line.category) ? subtotalByCategory.get(line.category) : 0;
                subtotalByCategory.put(line.category, current + line.lineSubtotal);
            }
        }

        // STEP 2: Coupon discount (§1).
        Decimal discount = 0;
        String eligibleCategory = null;
        if (String.isNotBlank(couponCode)) {
            DiscountService.CouponPreview couponPreview = DiscountService.validate(couponCode, accountId, subtotal, subtotalByCategory);
            result.couponValid = couponPreview.valid;
            result.couponMessage = couponPreview.message;
            if (couponPreview.valid) {
                discount = couponPreview.discountAmount;
                eligibleCategory = couponPreview.eligibleCategory;
                result.campaignId = couponPreview.campaignId;
                result.couponCodeId = couponPreview.couponCodeId;
                result.couponCode = couponPreview.code;
            }
        }
        result.discountAmount = discount.setScale(2, System.RoundingMode.HALF_UP);

        // STEP 3: Taxable value (§3.1/§3.2).
        Decimal taxableAmount = subtotal - discount;
        if (taxableAmount < 0) {
            taxableAmount = 0;
        }
        result.taxableAmount = taxableAmount.setScale(2, System.RoundingMode.HALF_UP);

        // STEP 4: GST — allocated per line at that product's own GST_Rate__c
        // (falling back to DEFAULT_GST_RATE_PERCENT when blank), so a
        // mixed-rate cart is taxed correctly instead of at one blended rate.
        // The discount itself is spread only across the lines it actually
        // applies to: every line when the coupon has no Eligible_Category__c,
        // or only the matching-category lines when it does (proportional to
        // their own share within that eligible group) — an accessory sitting
        // alongside a laptop-only coupon must never get a price cut it wasn't
        // offered. See the discount system's worked example.
        Decimal eligibleGroupSubtotal = 0;
        for (PricingLine line : lines) {
            if (String.isBlank(eligibleCategory) || eligibleCategory.equals(line.category)) {
                eligibleGroupSubtotal += line.lineSubtotal;
            }
        }

        Decimal gstTotal = 0;
        for (PricingLine line : lines) {
            Boolean lineIsDiscounted = String.isBlank(eligibleCategory) || eligibleCategory.equals(line.category);
            Decimal lineDiscountShare = (lineIsDiscounted && eligibleGroupSubtotal > 0)
                ? (discount * (line.lineSubtotal / eligibleGroupSubtotal))
                : 0;
            Decimal lineTaxable = line.lineSubtotal - lineDiscountShare;
            Decimal rate = line.gstRatePercent != null ? line.gstRatePercent : DEFAULT_GST_RATE_PERCENT;
            gstTotal += (lineTaxable * (rate / 100));
        }
        gstTotal = gstTotal.setScale(2, System.RoundingMode.HALF_UP);
        result.gstAmount = gstTotal;

        Boolean isIntrastate = String.isNotBlank(shippingState) && shippingState.trim().equalsIgnoreCase(SELLER_STATE);
        if (isIntrastate) {
            result.cgstAmount = (gstTotal / 2).setScale(2, System.RoundingMode.HALF_UP);
            result.sgstAmount = (gstTotal - result.cgstAmount).setScale(2, System.RoundingMode.HALF_UP);
            result.igstAmount = 0;
        } else {
            result.cgstAmount = 0;
            result.sgstAmount = 0;
            result.igstAmount = gstTotal;
        }

        // STEP 5/6: Loyalty point redemption, capped against the taxable
        // (pre-GST) amount (§2.5/§3.1).
        LoyaltyService.RedemptionPreview loyaltyPreview =
            LoyaltyService.previewRedemption(accountId, pointsRequested, result.taxableAmount);
        result.pointsUsed = loyaltyPreview.pointsUsed;
        result.loyaltyDiscount = loyaltyPreview.discountAmount;
        result.loyaltyMessage = loyaltyPreview.message;
        result.loyaltyBalance = loyaltyPreview.availableBalance;

        // STEP 7: Final payable amount. Shipping is added after GST (not
        // itself taxed in this model — the storefront doesn't charge GST on
        // the delivery fee separately) and after the loyalty discount, which
        // only ever applies against the product/tax portion (§2.5).
        Decimal payable = taxableAmount + gstTotal - result.loyaltyDiscount + result.shippingCost;
        if (payable < 0) {
            payable = 0;
        }
        result.amountPayable = payable.setScale(2, System.RoundingMode.HALF_UP);

        return result;
    }
}
