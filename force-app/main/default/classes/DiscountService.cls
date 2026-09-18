// without sharing: runs from Guest-User-facing checkout/preview calls
// (CheckoutController, OrderPricingService) the same way every other
// storefront controller in this app does — see CheckoutController's own
// header comment for the full reasoning.
//
// The coupon/campaign discount engine described in the Feature Expansion
// Plan §1. Built on standard Campaign (the offer's configuration:
// Discount_Type__c/Discount_Value__c/Minimum_Order_Value__c/
// Maximum_Discount_Amount__c/Status/StartDate/EndDate) and standard
// CampaignMember (the per-customer redemption ledger, extended with
// Coupon_Code__c/Order__c/Discount_Applied__c) rather than new custom
// objects — see the Feature Expansion Plan for why standard objects were
// preferred wherever they fit.
public without sharing class DiscountService {

    public class AvailableCoupon {
        @AuraEnabled public String code;
        @AuraEnabled public String description;
    }

    /**
     * Returns every currently usable coupon code — active campaign, active
     * coupon, within its date window, and not yet at its total-use cap — for
     * display at checkout, so a shopper can see what's available instead of
     * having to already know or guess a code. Doesn't check per-customer use
     * limits (there's no specific shopper to check them against for a public
     * listing); validate() still re-checks everything for real, including
     * that, the moment a shopper actually applies one.
     */
    @AuraEnabled(cacheable=true)
    public static List<AvailableCoupon> getAvailableCoupons() {
        List<AvailableCoupon> result = new List<AvailableCoupon>();
        Date today = Date.today();

        for (Coupon_Code__c coupon : [
            SELECT Code__c, Campaign__r.Discount_Type__c, Campaign__r.Discount_Value__c,
                   Campaign__r.Minimum_Order_Value__c, Campaign__r.Eligible_Category__c,
                   Max_Total_Uses__c, Total_Redemptions__c
            FROM Coupon_Code__c
            WHERE Is_Active__c = true
            AND Campaign__c != null
            AND Campaign__r.Status = 'Active'
            AND Campaign__r.IsActive = true
            AND (Campaign__r.StartDate = null OR Campaign__r.StartDate <= :today)
            AND (Campaign__r.EndDate = null OR Campaign__r.EndDate >= :today)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            Decimal totalRedemptions = coupon.Total_Redemptions__c == null ? 0 : coupon.Total_Redemptions__c;
            if (coupon.Max_Total_Uses__c != null && totalRedemptions >= coupon.Max_Total_Uses__c) {
                continue;
            }

            AvailableCoupon summary = new AvailableCoupon();
            summary.code = coupon.Code__c;

            Decimal discountValue = coupon.Campaign__r.Discount_Value__c == null ? 0 : coupon.Campaign__r.Discount_Value__c;
            String discountText = coupon.Campaign__r.Discount_Type__c == 'Flat Amount'
                ? 'Rs. ' + discountValue.setScale(0) + ' off'
                : discountValue.setScale(0) + '% off';
            String scopeText = String.isBlank(coupon.Campaign__r.Eligible_Category__c)
                ? ''
                : ' on ' + coupon.Campaign__r.Eligible_Category__c;
            String minText = coupon.Campaign__r.Minimum_Order_Value__c != null
                ? ' (min. order Rs. ' + coupon.Campaign__r.Minimum_Order_Value__c.setScale(0) + ')'
                : '';
            summary.description = discountText + scopeText + minText;
            result.add(summary);
        }
        return result;
    }

    public class CouponPreview {
        @AuraEnabled public Boolean valid = false;
        @AuraEnabled public String message;
        @AuraEnabled public Decimal discountAmount = 0;
        @AuraEnabled public Id campaignId;
        @AuraEnabled public Id couponCodeId;
        @AuraEnabled public String code;
        // Blank/null means the discount applies to the whole cart. Set means
        // it applies only to lines whose Product2.Family matches this value
        // — OrderPricingService uses this to know which lines to actually
        // discount when it allocates GST per line. See Eligible_Category__c.
        @AuraEnabled public String eligibleCategory;
    }

    /**
     * Validates a coupon code against the campaign's own rules (active,
     * dated, minimum order value, per-customer and total usage limits) and
     * calculates the discount it earns. Never trusts a client-calculated
     * discount — see §1.3/§1.7: "The backend must validate the code and
     * calculate the final discount again."
     * Re-run at both cart-preview time (CheckoutController.previewOrderTotals)
     * and again inside submitOrder itself, so a coupon that expired or was
     * exhausted between those two moments is caught for real, not just shown
     * once and trusted afterward.
     *
     * cartSubtotal is the WHOLE cart's subtotal — used only to gate
     * Minimum_Order_Value__c ("spend this much in your cart to unlock the
     * offer"). subtotalByCategory maps each cart line's Product2.Family to
     * its combined subtotal — used to find the actual discount base once a
     * campaign restricts itself to one category via Eligible_Category__c
     * (e.g. a laptop-only 10% off must never discount an accessory sitting
     * in the same cart, even though that accessory's spend still counts
     * toward the minimum). See the discount system's worked example.
     */
    public static CouponPreview validate(String rawCode, Id accountId, Decimal cartSubtotal, Map<String, Decimal> subtotalByCategory) {
        CouponPreview result = new CouponPreview();

        if (String.isBlank(rawCode)) {
            result.message = 'Please enter a coupon code.';
            return result;
        }
        if (cartSubtotal == null || cartSubtotal <= 0) {
            result.message = 'Your cart is empty.';
            return result;
        }

        String code = rawCode.trim().toUpperCase();
        result.code = code;

        List<Coupon_Code__c> matches = [
            SELECT Id, Code__c, Is_Active__c, Max_Uses_Per_Customer__c, Max_Total_Uses__c,
                   Total_Redemptions__c, Campaign__c,
                   Campaign__r.IsActive, Campaign__r.StartDate, Campaign__r.EndDate,
                   Campaign__r.Status, Campaign__r.Discount_Type__c, Campaign__r.Discount_Value__c,
                   Campaign__r.Minimum_Order_Value__c, Campaign__r.Maximum_Discount_Amount__c,
                   Campaign__r.Eligible_Category__c
            FROM Coupon_Code__c
            WHERE Code__c = :code
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            result.message = 'This coupon code does not exist.';
            return result;
        }

        Coupon_Code__c coupon = matches[0];

        if (coupon.Campaign__c == null) {
            result.message = 'This coupon is not linked to an offer.';
            return result;
        }
        if (coupon.Is_Active__c != true) {
            result.message = 'This coupon is no longer active.';
            return result;
        }
        if (coupon.Campaign__r.Status != 'Active' || coupon.Campaign__r.IsActive != true) {
            result.message = 'This offer is not currently active.';
            return result;
        }

        Date today = Date.today();
        if (coupon.Campaign__r.StartDate != null && today < coupon.Campaign__r.StartDate) {
            result.message = 'This offer has not started yet.';
            return result;
        }
        if (coupon.Campaign__r.EndDate != null && today > coupon.Campaign__r.EndDate) {
            result.message = 'This offer has expired.';
            return result;
        }

        if (coupon.Campaign__r.Minimum_Order_Value__c != null && cartSubtotal < coupon.Campaign__r.Minimum_Order_Value__c) {
            result.message = 'Minimum purchase of Rs. ' + coupon.Campaign__r.Minimum_Order_Value__c.setScale(0) + ' is required for this offer.';
            return result;
        }

        String eligibleCategory = coupon.Campaign__r.Eligible_Category__c;
        result.eligibleCategory = eligibleCategory;

        Decimal eligibleSubtotal;
        if (String.isBlank(eligibleCategory)) {
            eligibleSubtotal = cartSubtotal;
        } else {
            eligibleSubtotal = (subtotalByCategory != null && subtotalByCategory.containsKey(eligibleCategory))
                ? subtotalByCategory.get(eligibleCategory)
                : 0;
        }
        if (eligibleSubtotal <= 0) {
            result.message = String.isBlank(eligibleCategory)
                ? 'Your cart is empty.'
                : 'This offer only applies to ' + eligibleCategory + ' products, and your cart doesn\'t have any.';
            return result;
        }

        Decimal totalRedemptions = coupon.Total_Redemptions__c == null ? 0 : coupon.Total_Redemptions__c;
        if (coupon.Max_Total_Uses__c != null && totalRedemptions >= coupon.Max_Total_Uses__c) {
            result.message = 'This offer has reached its usage limit.';
            return result;
        }

        if (accountId != null) {
            Integer maxPerCustomer = coupon.Max_Uses_Per_Customer__c == null ? 1 : coupon.Max_Uses_Per_Customer__c.intValue();
            // Excludes redemptions tied to a Cancelled order — a cancelled
            // order never really used the offer, and releaseRedemptionForCancelledOrder
            // keeps Total_Redemptions__c in sync with the same rule. See §1.6.
            Integer customerUses = [
                SELECT COUNT()
                FROM CampaignMember
                WHERE Coupon_Code__c = :coupon.Id
                AND Contact.AccountId = :accountId
                AND (Order__r.Status = null OR Order__r.Status != 'Cancelled')
                WITH SYSTEM_MODE
            ];
            if (customerUses >= maxPerCustomer) {
                result.message = 'This offer has already been used on your account.';
                return result;
            }
        }

        Decimal discount = 0;
        Decimal discountValue = coupon.Campaign__r.Discount_Value__c == null ? 0 : coupon.Campaign__r.Discount_Value__c;
        if (coupon.Campaign__r.Discount_Type__c == 'Flat Amount') {
            discount = discountValue;
        } else {
            discount = (eligibleSubtotal * (discountValue / 100)).setScale(2, System.RoundingMode.HALF_UP);
            if (coupon.Campaign__r.Maximum_Discount_Amount__c != null && discount > coupon.Campaign__r.Maximum_Discount_Amount__c) {
                discount = coupon.Campaign__r.Maximum_Discount_Amount__c;
            }
        }
        if (discount > eligibleSubtotal) {
            discount = eligibleSubtotal;
        }
        if (discount < 0) {
            discount = 0;
        }

        result.valid = true;
        result.discountAmount = discount;
        result.campaignId = coupon.Campaign__c;
        result.couponCodeId = coupon.Id;
        result.message = 'Offer applied: Rs. ' + discount.setScale(2) + ' off' +
            (String.isBlank(eligibleCategory) ? '.' : ' on ' + eligibleCategory + ' items.');
        return result;
    }

    /**
     * Records a redemption as one CampaignMember row (the permanent
     * per-customer ledger — see §1.4/§1.7) and increments the coupon's
     * Total_Redemptions__c. Called only from CheckoutController.submitOrder,
     * strictly after the real Order/Contact already exist — never from the
     * cart-preview path, which only ever calls validate() and must never
     * itself consume the coupon (see §1.5: applying a coupon to a cart must
     * not permanently use it up). Best-effort: a redemption-bookkeeping
     * failure must never undo an otherwise-successful order.
     */
    public static void recordRedemption(Id couponCodeId, Id campaignId, Id contactId, Id orderId, Decimal discountApplied) {
        if (couponCodeId == null || campaignId == null || contactId == null) {
            return;
        }
        try {
            CampaignMember member = new CampaignMember();
            member.CampaignId = campaignId;
            member.ContactId = contactId;
            member.Coupon_Code__c = couponCodeId;
            member.Order__c = orderId;
            member.Discount_Applied__c = discountApplied;
            Database.insert(member, AccessLevel.SYSTEM_MODE);

            List<Coupon_Code__c> current = [
                SELECT Id, Total_Redemptions__c FROM Coupon_Code__c WHERE Id = :couponCodeId WITH SYSTEM_MODE LIMIT 1
            ];
            if (!current.isEmpty()) {
                Decimal currentTotal = current[0].Total_Redemptions__c == null ? 0 : current[0].Total_Redemptions__c;
                Database.update(
                    new Coupon_Code__c(Id = couponCodeId, Total_Redemptions__c = currentTotal + 1),
                    AccessLevel.SYSTEM_MODE
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Coupon redemption recording failed: ' + e.getMessage());
        }
    }

    /**
     * Releases a coupon redemption when its order is cancelled before
     * fulfillment: decrements Total_Redemptions__c so the code becomes
     * available again, matching §1.6 ("If an order is cancelled before
     * fulfillment, the coupon may be restored"). The CampaignMember row
     * itself is deliberately kept, not deleted — it preserves the original
     * discount amount as a historical record (§1.6) and is excluded from the
     * per-customer usage count by validate()'s own Order__r.Status check
     * above, so the two stay consistent with each other.
     */
    public static void releaseRedemptionForCancelledOrder(Id orderId) {
        if (orderId == null) {
            return;
        }
        try {
            List<CampaignMember> members = [
                SELECT Id, Coupon_Code__c
                FROM CampaignMember
                WHERE Order__c = :orderId
                AND Coupon_Code__c != null
                WITH SYSTEM_MODE
            ];
            if (members.isEmpty()) {
                return;
            }

            Set<Id> couponIds = new Set<Id>();
            for (CampaignMember m : members) {
                couponIds.add(m.Coupon_Code__c);
            }

            List<Coupon_Code__c> toUpdate = new List<Coupon_Code__c>();
            for (Coupon_Code__c c : [
                SELECT Id, Total_Redemptions__c FROM Coupon_Code__c WHERE Id IN :couponIds WITH SYSTEM_MODE
            ]) {
                Decimal current = c.Total_Redemptions__c == null ? 0 : c.Total_Redemptions__c;
                toUpdate.add(new Coupon_Code__c(Id = c.Id, Total_Redemptions__c = Math.max(0, current - 1)));
            }
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Coupon redemption release failed: ' + e.getMessage());
        }
    }
}
