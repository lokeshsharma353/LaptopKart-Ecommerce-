// without sharing: same reasoning as DiscountService — runs from
// Guest-User-facing checkout/preview calls and from the Order_Tracking__c
// trigger chain, neither of which has implicit record access of its own.
//
// The loyalty points engine described in the Feature Expansion Plan §2.
// Account.Loyalty_Points_Balance__c is a maintained cache, never edited
// directly anywhere else — every change to it in this app goes through
// adjustBalance() below, which always also writes the matching
// Loyalty_Point_Transaction__c ledger row in the same call, so the balance
// can never drift from the transaction history that explains it (§2.4).
public without sharing class LoyaltyService {

    // Suppresses AccountTriggerHandler's own generic Adjustment-logging for
    // a Loyalty_Points_Balance__c update this class is already making (and
    // already logging itself, precisely) — set true immediately before such
    // a DML and false immediately after, mirroring InventoryService's
    // identical suppressMovementTrigger pattern for Product2/Stock_Movement__c.
    @TestVisible
    private static Boolean suppressLedgerTrigger = false;

    // 1 point earned per this many rupees of eligible (post-discount,
    // pre-GST) spend, whole-thousand rule — a partial thousand earns
    // nothing extra. See §2.2.
    private static final Decimal EARN_RATE_RUPEES_PER_POINT = 1000;
    // 1 loyalty point is worth this many rupees when redeemed. See §2.1.
    private static final Decimal POINT_VALUE_RUPEES = 1;
    // A redemption can never cover more than this share of the eligible
    // (pre-GST, post-coupon-discount) order value. See §2.5.
    private static final Decimal MAX_REDEMPTION_SHARE = 0.20;

    public class RedemptionPreview {
        @AuraEnabled public Integer pointsUsed = 0;
        @AuraEnabled public Decimal discountAmount = 0;
        @AuraEnabled public Integer availableBalance = 0;
        @AuraEnabled public String message;
    }

    /** Returns the customer's current whole-point balance (0 if none/not found). */
    public static Integer getBalance(Id accountId) {
        if (accountId == null) {
            return 0;
        }
        List<Account> accounts = [
            SELECT Loyalty_Points_Balance__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (accounts.isEmpty() || accounts[0].Loyalty_Points_Balance__c == null) {
            return 0;
        }
        return accounts[0].Loyalty_Points_Balance__c.intValue();
    }

    /**
     * Caps a requested point redemption against the customer's real balance
     * and the eligible-order-value redemption limit — never trusts a
     * client-calculated discount, same reasoning as DiscountService.validate.
     * Re-run at both preview time and again inside submitOrder, so a balance
     * that changed between those two moments (e.g. two tabs redeeming at
     * once) is caught for real rather than just shown once and trusted.
     */
    public static RedemptionPreview previewRedemption(Id accountId, Integer requestedPoints, Decimal eligibleOrderValue) {
        RedemptionPreview preview = new RedemptionPreview();
        Integer balance = getBalance(accountId);
        preview.availableBalance = balance;

        if (requestedPoints == null || requestedPoints <= 0 || eligibleOrderValue == null || eligibleOrderValue <= 0) {
            return preview;
        }

        Integer maxByShare = (MAX_REDEMPTION_SHARE * eligibleOrderValue).intValue();
        Integer pointsUsed = Math.min(requestedPoints, Math.min(balance, maxByShare));
        if (pointsUsed <= 0) {
            preview.message = balance <= 0
                ? 'You have no loyalty points to redeem yet.'
                : 'Points redemption is limited to ' + (MAX_REDEMPTION_SHARE * 100).intValue() + '% of your order value.';
            return preview;
        }

        preview.pointsUsed = pointsUsed;
        preview.discountAmount = pointsUsed * POINT_VALUE_RUPEES;
        preview.message = pointsUsed + ' points applied for a Rs. ' + preview.discountAmount.setScale(2) + ' discount.';
        return preview;
    }

    /** Deducts redeemed points from the customer's balance and writes the ledger row. Called from CheckoutController.submitOrder only after the real Order exists. Best-effort — never undoes an otherwise-successful order. */
    public static void recordRedemption(Id accountId, Integer pointsUsed, Id orderId) {
        if (accountId == null || pointsUsed == null || pointsUsed <= 0) {
            return;
        }
        try {
            adjustBalance(accountId, -pointsUsed, 'Redeemed', orderId, 'Redeemed at checkout.');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Loyalty redemption recording failed: ' + e.getMessage());
        }
    }

    /** Restores points to a customer's balance when an order that redeemed them is cancelled before delivery. See §2.6 Case 1. Best-effort. */
    public static void restoreRedeemedPoints(Id accountId, Integer pointsToRestore, Id orderId) {
        if (accountId == null || pointsToRestore == null || pointsToRestore <= 0) {
            return;
        }
        try {
            adjustBalance(accountId, pointsToRestore, 'Adjustment', orderId, 'Restored — order cancelled before delivery.');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Loyalty point restoration failed: ' + e.getMessage());
        }
    }

    /** Subtracts points already earned on a delivered order that was later returned — the reverse of awardPointsForDeliveredOrder. See §2.6 Case 2. Best-effort. A negative balance is allowed to result (the customer simply can't redeem further until it's settled by future earning), same as the documented policy option in §2.6. */
    public static void reverseEarnedPoints(Id accountId, Integer pointsToReverse, Id orderId) {
        if (accountId == null || pointsToReverse == null || pointsToReverse <= 0) {
            return;
        }
        try {
            adjustBalance(accountId, -pointsToReverse, 'Adjustment', orderId, 'Reversed — order returned after delivery.');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Loyalty point reversal failed: ' + e.getMessage());
        }
    }

    /**
     * Awards points for a just-Delivered order — 1 point per Rs. 1,000 of the
     * order's eligible (post-discount, pre-GST) amount, whole-thousand rule.
     * Called once from OrderTrackingService the exact moment
     * Order_Tracking__c.Delivery_Status__c first reaches 'Delivered' — never
     * earlier, since payment can still fail or the order can still be
     * cancelled before then (§2.3). Also stamps Order.Points_Earned__c so the
     * award is visible directly on the order, not just in the ledger.
     * Best-effort — never blocks the admin's own tracking-status save.
     */
    public static void awardPointsForDeliveredOrder(Id accountId, Decimal eligibleAmount, Id orderId) {
        if (accountId == null || eligibleAmount == null || eligibleAmount <= 0) {
            return;
        }
        Integer points = (eligibleAmount / EARN_RATE_RUPEES_PER_POINT).intValue();
        if (points <= 0) {
            return;
        }
        try {
            adjustBalance(accountId, points, 'Earned', orderId, 'Earned on delivery.');
            Database.update(new Order(Id = orderId, Points_Earned__c = points), AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Loyalty point award failed: ' + e.getMessage());
        }
    }

    /** Writes one ledger row and updates the Account's live balance in the same call. See §2.4. */
    private static void adjustBalance(Id accountId, Integer delta, String type, Id orderId, String notes) {
        List<Account> accounts = [
            SELECT Id, Loyalty_Points_Balance__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return;
        }
        Decimal currentBalance = accounts[0].Loyalty_Points_Balance__c == null ? 0 : accounts[0].Loyalty_Points_Balance__c;
        Decimal newBalance = currentBalance + delta;

        Loyalty_Point_Transaction__c txn = new Loyalty_Point_Transaction__c();
        txn.Customer__c = accountId;
        txn.Points__c = delta;
        txn.Type__c = type;
        txn.Related_Order__c = orderId;
        txn.Notes__c = notes;
        Database.insert(txn, AccessLevel.SYSTEM_MODE);

        suppressLedgerTrigger = true;
        try {
            Database.update(new Account(Id = accountId, Loyalty_Points_Balance__c = newBalance), AccessLevel.SYSTEM_MODE);
        } finally {
            suppressLedgerTrigger = false;
        }
    }

    /**
     * Called by AccountTriggerHandler for a Loyalty_Points_Balance__c change
     * that did NOT go through this service (e.g. an admin editing the field
     * directly on the Account record/page layout — see the "Rewards /
     * Loyalty" section added to the Customer Account Details layout) — logs
     * it as an 'Adjustment' ledger row so the balance shown there never
     * silently drifts from the transaction history that explains it,
     * mirroring Product2TriggerHandler/InventoryService.logManualAdjustments
     * exactly. Skipped entirely while this class is mid-way through its own
     * update, which already logs its own precise row.
     */
    public static void logManualAdjustments(List<Account> newAccounts, Map<Id, Account> oldAccountMap) {
        if (suppressLedgerTrigger) {
            return;
        }

        List<Loyalty_Point_Transaction__c> movements = new List<Loyalty_Point_Transaction__c>();

        for (Account acc : newAccounts) {
            Account oldAcc = oldAccountMap.get(acc.Id);
            if (oldAcc.Loyalty_Points_Balance__c == acc.Loyalty_Points_Balance__c) {
                continue;
            }

            Decimal oldBalance = oldAcc.Loyalty_Points_Balance__c == null ? 0 : oldAcc.Loyalty_Points_Balance__c;
            Decimal newBalance = acc.Loyalty_Points_Balance__c == null ? 0 : acc.Loyalty_Points_Balance__c;

            Loyalty_Point_Transaction__c txn = new Loyalty_Point_Transaction__c();
            txn.Customer__c = acc.Id;
            txn.Type__c = 'Adjustment';
            txn.Points__c = newBalance - oldBalance;
            txn.Notes__c = 'Manual balance edit.';
            movements.add(txn);
        }

        if (!movements.isEmpty()) {
            Database.insert(movements, AccessLevel.SYSTEM_MODE);
        }
    }
}
