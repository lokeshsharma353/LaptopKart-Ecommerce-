// with sharing (the default admin-facing behavior): unlike the storefront's
// Guest-User-facing controllers, this runs only for an internal Salesforce
// user (the System Administrator) working inside the "Enterprise Order
// Management" app — there is no Guest User context here, so none of the
// without-sharing/SYSTEM_MODE reasoning used throughout the rest of this
// project's Apex applies.
//
// Backs the Admin Dashboard LWC — a single screen where the admin can see
// store-wide KPIs, manage discount campaigns/coupons, and send a one-off
// offer email to every customer, instead of hunting across several tabs and
// raw records to do the same things.
public with sharing class AdminDashboardController {

    // ───────────────────────── KPIs ─────────────────────────

    public class DashboardStats {
        @AuraEnabled public Integer totalOrders = 0;
        @AuraEnabled public Decimal totalRevenue = 0;
        @AuraEnabled public Integer totalCustomers = 0;
        @AuraEnabled public Integer activeCoupons = 0;
        @AuraEnabled public Integer pendingReturns = 0;
        @AuraEnabled public Integer lowStockProducts = 0;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardStats getDashboardStats() {
        DashboardStats stats = new DashboardStats();

        stats.totalOrders = [SELECT COUNT() FROM Order];

        // Amount_Payable__c (the pricing-engine's real "what was actually
        // charged" figure) is null on any order placed before that engine
        // existed — those legacy orders fall back to TotalAmount, same
        // fallback used everywhere else in this app (Order History, Order
        // Confirmation, My Account). Summed in Apex rather than SOQL SUM()
        // because SOQL has no COALESCE-style expression to combine the two
        // fields in one aggregate query.
        Decimal revenue = 0;
        for (Order ord : [SELECT Amount_Payable__c, TotalAmount FROM Order]) {
            revenue += (ord.Amount_Payable__c != null ? ord.Amount_Payable__c : (ord.TotalAmount == null ? 0 : ord.TotalAmount));
        }
        stats.totalRevenue = revenue;

        Id customerRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('Customer_Account_Details')
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer_Account_Details').getRecordTypeId()
            : null;
        stats.totalCustomers = customerRTId == null ? 0 : [SELECT COUNT() FROM Account WHERE RecordTypeId = :customerRTId];

        stats.activeCoupons = [
            SELECT COUNT() FROM Coupon_Code__c
            WHERE Is_Active__c = true
            AND Campaign__r.Status = 'Active'
            AND Campaign__r.IsActive = true
        ];

        stats.pendingReturns = [SELECT COUNT() FROM Order_Tracking__c WHERE Delivery_Status__c = 'Return Requested'];

        // Same "no field <= COALESCE(other, default)" limitation as revenue
        // above — Reorder_Level__c is null on most products (only ever set
        // explicitly), so this falls back to the same default threshold
        // ProductCatalogController.stockStatusFor already uses.
        Integer lowStockDefaultThreshold = 3;
        Integer lowStock = 0;
        for (Product2 prod : [
            SELECT Stock_Quantity__c, Reorder_Level__c FROM Product2 WHERE IsActive = true
        ]) {
            Decimal threshold = prod.Reorder_Level__c != null ? prod.Reorder_Level__c : lowStockDefaultThreshold;
            Decimal stock = prod.Stock_Quantity__c == null ? 0 : prod.Stock_Quantity__c;
            if (stock <= threshold) {
                lowStock++;
            }
        }
        stats.lowStockProducts = lowStock;

        return stats;
    }

    // ───────────────────────── Recent Orders ─────────────────────────

    public class RecentOrder {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public Date orderDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static List<RecentOrder> getRecentOrders() {
        List<RecentOrder> result = new List<RecentOrder>();
        for (Order ord : [
            SELECT OrderNumber, EffectiveDate, TotalAmount, Amount_Payable__c, Status,
                   Account.Name, Recipient_Name__c
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            RecentOrder summary = new RecentOrder();
            summary.orderId = ord.Id;
            summary.orderNumber = ord.OrderNumber;
            summary.customerName = String.isNotBlank(ord.Recipient_Name__c)
                ? ord.Recipient_Name__c
                : (ord.Account != null ? ord.Account.Name : '—');
            summary.orderDate = ord.EffectiveDate;
            summary.amount = ord.Amount_Payable__c != null ? ord.Amount_Payable__c : ord.TotalAmount;
            summary.status = ord.Status;
            result.add(summary);
        }
        return result;
    }

    // ───────────────────────── Low Stock Products ─────────────────────────

    public class LowStockProduct {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal stockQuantity;
        @AuraEnabled public Decimal reorderLevel;
    }

    @AuraEnabled(cacheable=true)
    public static List<LowStockProduct> getLowStockProducts() {
        List<LowStockProduct> result = new List<LowStockProduct>();
        Integer defaultThreshold = 3;
        for (Product2 prod : [
            SELECT Name, Stock_Quantity__c, Reorder_Level__c
            FROM Product2
            WHERE IsActive = true
            ORDER BY Stock_Quantity__c ASC NULLS FIRST
            LIMIT 200
        ]) {
            Decimal threshold = prod.Reorder_Level__c != null ? prod.Reorder_Level__c : defaultThreshold;
            Decimal stock = prod.Stock_Quantity__c == null ? 0 : prod.Stock_Quantity__c;
            if (stock <= threshold) {
                LowStockProduct summary = new LowStockProduct();
                summary.productId = prod.Id;
                summary.productName = prod.Name;
                summary.stockQuantity = stock;
                summary.reorderLevel = threshold;
                result.add(summary);
                if (result.size() >= 10) {
                    break;
                }
            }
        }
        return result;
    }

    // ───────────────────────── Coupons & Campaigns ─────────────────────────

    public class CouponSummary {
        @AuraEnabled public Id couponCodeId;
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String code;
        @AuraEnabled public String campaignName;
        @AuraEnabled public String discountType;
        @AuraEnabled public Decimal discountValue;
        @AuraEnabled public String eligibleCategory;
        @AuraEnabled public Decimal minimumOrderValue;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean campaignActive;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal totalRedemptions;
        @AuraEnabled public Decimal maxTotalUses;
    }

    @AuraEnabled(cacheable=true)
    public static List<CouponSummary> getCoupons() {
        List<CouponSummary> result = new List<CouponSummary>();
        for (Coupon_Code__c coupon : [
            SELECT Id, Code__c, Is_Active__c, Total_Redemptions__c, Max_Total_Uses__c,
                   Campaign__c, Campaign__r.Name, Campaign__r.Discount_Type__c, Campaign__r.Discount_Value__c,
                   Campaign__r.Eligible_Category__c, Campaign__r.Minimum_Order_Value__c,
                   Campaign__r.Status, Campaign__r.IsActive, Campaign__r.StartDate, Campaign__r.EndDate
            FROM Coupon_Code__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            CouponSummary summary = new CouponSummary();
            summary.couponCodeId = coupon.Id;
            summary.campaignId = coupon.Campaign__c;
            summary.code = coupon.Code__c;
            summary.campaignName = coupon.Campaign__r != null ? coupon.Campaign__r.Name : null;
            summary.discountType = coupon.Campaign__r != null ? coupon.Campaign__r.Discount_Type__c : null;
            summary.discountValue = coupon.Campaign__r != null ? coupon.Campaign__r.Discount_Value__c : null;
            summary.eligibleCategory = coupon.Campaign__r != null ? coupon.Campaign__r.Eligible_Category__c : null;
            summary.minimumOrderValue = coupon.Campaign__r != null ? coupon.Campaign__r.Minimum_Order_Value__c : null;
            summary.isActive = coupon.Is_Active__c;
            summary.campaignActive = coupon.Campaign__r != null && coupon.Campaign__r.Status == 'Active' && coupon.Campaign__r.IsActive == true;
            summary.startDate = coupon.Campaign__r != null ? coupon.Campaign__r.StartDate : null;
            summary.endDate = coupon.Campaign__r != null ? coupon.Campaign__r.EndDate : null;
            summary.totalRedemptions = coupon.Total_Redemptions__c == null ? 0 : coupon.Total_Redemptions__c;
            summary.maxTotalUses = coupon.Max_Total_Uses__c;
            result.add(summary);
        }
        return result;
    }

    public class CampaignCouponInput {
        @AuraEnabled public String campaignName;
        @AuraEnabled public String discountType; // 'Percentage' or 'Flat Amount'
        @AuraEnabled public Decimal discountValue;
        @AuraEnabled public Decimal minimumOrderValue;
        @AuraEnabled public Decimal maximumDiscountAmount;
        @AuraEnabled public String eligibleCategory;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String couponCode;
        @AuraEnabled public Integer maxUsesPerCustomer;
        @AuraEnabled public Integer maxTotalUses;
    }

    /**
     * Creates a new Campaign (the offer's own configuration) together with
     * its Coupon_Code__c (the redeemable code customers actually type in) in
     * one call — mirrors exactly what DiscountService.validate expects, and
     * is the same two-object model the storefront's checkout/discount engine
     * already reads from (see DiscountService's own header comment).
     */
    @AuraEnabled
    public static Id createCampaignCoupon(CampaignCouponInput input) {
        if (input == null || String.isBlank(input.campaignName)) {
            throw new AuraHandledException('Please enter a campaign name.');
        }
        if (String.isBlank(input.couponCode)) {
            throw new AuraHandledException('Please enter a coupon code.');
        }
        if (input.discountValue == null || input.discountValue <= 0) {
            throw new AuraHandledException('Please enter a discount value greater than 0.');
        }

        String normalizedCode = input.couponCode.trim().toUpperCase();
        List<Coupon_Code__c> existing = [SELECT Id FROM Coupon_Code__c WHERE Code__c = :normalizedCode LIMIT 1];
        if (!existing.isEmpty()) {
            throw new AuraHandledException('A coupon with this code already exists.');
        }

        Campaign newCampaign = new Campaign();
        newCampaign.Name = input.campaignName.trim();
        newCampaign.Status = 'Active';
        newCampaign.IsActive = true;
        newCampaign.Discount_Type__c = String.isBlank(input.discountType) ? 'Percentage' : input.discountType;
        newCampaign.Discount_Value__c = input.discountValue;
        newCampaign.Minimum_Order_Value__c = input.minimumOrderValue;
        newCampaign.Maximum_Discount_Amount__c = input.maximumDiscountAmount;
        newCampaign.Eligible_Category__c = input.eligibleCategory;
        newCampaign.StartDate = input.startDate;
        newCampaign.EndDate = input.endDate;
        insert newCampaign;

        Coupon_Code__c newCoupon = new Coupon_Code__c();
        newCoupon.Campaign__c = newCampaign.Id;
        newCoupon.Code__c = normalizedCode;
        newCoupon.Is_Active__c = true;
        newCoupon.Max_Uses_Per_Customer__c = input.maxUsesPerCustomer == null ? 1 : input.maxUsesPerCustomer;
        newCoupon.Max_Total_Uses__c = input.maxTotalUses;
        insert newCoupon;

        return newCoupon.Id;
    }

    /** Quick activate/deactivate — flips the coupon's own switch without opening the record. */
    @AuraEnabled
    public static void setCouponActive(Id couponCodeId, Boolean isActive) {
        if (couponCodeId == null) {
            return;
        }
        update new Coupon_Code__c(Id = couponCodeId, Is_Active__c = isActive);
    }

    // ───────────────────────── Offer email blast ─────────────────────────

    public class OfferEmailResult {
        @AuraEnabled public Integer recipientCount = 0;
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Integer failureCount = 0;
        @AuraEnabled public Integer skippedBouncedCount = 0;
        @AuraEnabled public Boolean sent = false;
        // One "email — reason" line per address that failed, so a single bad
        // address is named specifically instead of silently taking the whole
        // send down with it (see the allOrNone=false reasoning below).
        @AuraEnabled public List<String> failureDetails = new List<String>();
    }

    /**
     * Sends a one-off marketing/offer email to every customer account with a
     * real email on file. One Messaging.sendEmail call carries the whole
     * recipient list (each as its own SingleEmailMessage) — that's a single
     * "email invocation" against the 10-per-transaction Apex limit no matter
     * how many recipients are in it.
     *
     * Passes allOrNone=false explicitly. Messaging.sendEmail defaults to
     * all-or-nothing: if even ONE address in the batch is rejected (a typo'd
     * test address, a malformed one, anything), the platform throws for the
     * WHOLE call and every other, perfectly valid recipient gets nothing —
     * exactly the "one bad email poisons the batch" failure mode. With
     * allOrNone=false the good addresses still go out, and this returns
     * exactly which address(es) failed and why instead of one opaque error.
     */
    @AuraEnabled
    public static OfferEmailResult sendOfferEmail(String subject, String body) {
        if (String.isBlank(subject) || String.isBlank(body)) {
            throw new AuraHandledException('Please enter both a subject and a message.');
        }

        Id customerRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().containsKey('Customer_Account_Details')
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer_Account_Details').getRecordTypeId()
            : null;

        OfferEmailResult result = new OfferEmailResult();
        if (customerRTId == null) {
            return result;
        }

        // Addresses Salesforce has already hard-bounced (e.g. "account does
        // not exist") on a Contact created during checkout/signup — mostly
        // test/typo'd addresses from development. Skipped outright rather
        // than re-attempted: repeatedly sending to a dead mailbox does
        // nothing for that recipient and risks degrading this org-wide
        // email address's sender reputation for every OTHER, real send.
        Set<String> bouncedAddresses = new Set<String>();
        for (Contact con : [
            SELECT Email FROM Contact
            WHERE Email != null AND EmailBouncedDate != null
        ]) {
            bouncedAddresses.add(con.Email.toLowerCase());
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        // Parallel to `emails` — Messaging.sendEmail returns results in the
        // same order as the input list, so index i here is always the
        // address behind emails[i], letting a per-message failure be named
        // by address instead of reported as one opaque batch error.
        List<String> addressByIndex = new List<String>();
        for (Account acc : [
            SELECT Name, Email__c
            FROM Account
            WHERE RecordTypeId = :customerRTId
            AND Email__c != null
            LIMIT 500
        ]) {
            if (bouncedAddresses.contains(acc.Email__c.toLowerCase())) {
                result.skippedBouncedCount++;
                continue;
            }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            EmailSenderService.applySupportSender(mail);
            mail.setToAddresses(new String[] { acc.Email__c });
            mail.setSubject(subject);
            mail.setPlainTextBody('Hi ' + acc.Name + ',\n\n' + body + '\n\n- The LaptopKart Team');
            mail.setHtmlBody(
                '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111111;">' +
                    '<p style="font-size:14px;line-height:1.6;">Hi ' + acc.Name.escapeHtml4() + ',</p>' +
                    '<p style="font-size:14px;line-height:1.6;white-space:pre-wrap;">' + body.escapeHtml4() + '</p>' +
                    '<p>- The LaptopKart Team</p>' +
                '</div>'
            );
            mail.setSaveAsActivity(false);
            emails.add(mail);
            addressByIndex.add(acc.Email__c);
        }

        result.recipientCount = emails.size();
        if (emails.isEmpty()) {
            return result;
        }

        try {
            List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);
            Integer successCount = 0;
            for (Integer i = 0; i < sendResults.size(); i++) {
                Messaging.SendEmailResult sr = sendResults[i];
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    String reason = !sr.getErrors().isEmpty() ? sr.getErrors()[0].getMessage() : 'Unknown error';
                    result.failureDetails.add(addressByIndex[i] + ' — ' + reason);
                }
            }
            result.successCount = successCount;
            result.failureCount = emails.size() - successCount;
            result.sent = successCount > 0;

            if (!result.failureDetails.isEmpty()) {
                EmailSenderService.logEmailFailure(
                    'Offer Email Blast (partial failure): ' + subject,
                    String.join(result.failureDetails, '; '),
                    result.failureCount + ' of ' + emails.size() + ' addresses failed — see this Task\'s recipient list for exactly which ones and why'
                );
            }
        } catch (Exception e) {
            EmailSenderService.logEmailFailure('Offer Email Blast: ' + subject, 'batch of ' + emails.size(), e.getMessage());
            throw new AuraHandledException('Could not send the offer email: ' + e.getMessage());
        }
        return result;
    }
}
