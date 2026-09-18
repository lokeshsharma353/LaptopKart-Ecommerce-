// without sharing: runs from Guest-User-facing checkout calls and from the
// Product2 trigger chain, neither of which has implicit record access of
// its own — same reasoning as every other service class in this app.
//
// LaptopKart's inventory engine, described in the "Inventory & Vendor
// System" design: one live number per product (Product2.Stock_Quantity__c)
// that a small number of events can change, and one ledger
// (Stock_Movement__c) that records every change as a row — mirroring how
// Payment__c already ledgers every change to an Order's paid amount.
// Callers: CheckoutController (Sale on a successful order), OrderTrackingService
// (Cancellation when an order is cancelled or returned), and
// Product2TriggerHandler (Adjustment when Stock_Quantity__c is edited
// directly, e.g. an admin correcting a count in Setup — the "Restock" type
// is reserved for a future formal Purchase Order workflow; until then, a
// manual restock is just an Adjustment with a note).
public without sharing class InventoryService {

    // Suppresses Product2TriggerHandler's own generic Adjustment-logging for
    // an update this class is already making (and already logging itself,
    // precisely, as a Sale/Cancellation row) — set true immediately before
    // such a DML and false immediately after, so a checkout or cancellation
    // is never double-logged as both its real movement type AND a generic
    // Adjustment. Plain static field: Apex is single-threaded per
    // transaction, so this is safe without any concurrency guard.
    @TestVisible
    private static Boolean suppressMovementTrigger = false;

    /** One product/quantity pair — the unit InventoryService's public methods operate on. */
    public class StockLine {
        public Id productId;
        public Integer quantity;
    }

    /**
     * Rejects (via AuraHandledException) any line whose requested quantity
     * exceeds the given product's real Stock_Quantity__c. Takes an
     * already-queried Map<Id, Product2> rather than querying itself — the
     * caller is expected to have already locked these exact rows with
     * SELECT ... FOR UPDATE (see CheckoutController.submitOrder), so the
     * classic "two customers both buy the last unit" race is closed by
     * that lock, not by this method. Blank Stock_Quantity__c means the
     * product isn't tracked yet and never blocks a sale — same
     * graceful-fallback approach as Price__c/GST_Rate__c elsewhere in this
     * app.
     */
    public static void validateStock(Map<Id, Product2> lockedProducts, List<StockLine> lines) {
        for (StockLine line : lines) {
            Product2 product = lockedProducts.get(line.productId);
            if (product == null || product.Stock_Quantity__c == null) {
                continue;
            }
            if (line.quantity > product.Stock_Quantity__c) {
                String available = product.Stock_Quantity__c <= 0
                    ? 'out of stock'
                    : 'only ' + product.Stock_Quantity__c.intValue() + ' left in stock';
                throw new AuraHandledException(product.Name + ' is ' + available + '. Please adjust the quantity in your cart.');
            }
        }
    }

    /**
     * Decrements stock for a completed sale and logs one Stock_Movement__c
     * ('Sale', negative Quantity__c) per tracked product. Call only after
     * the real Order exists (see CheckoutController), using the same
     * locked Map validateStock was called with.
     */
    public static void recordSale(Map<Id, Product2> lockedProducts, List<StockLine> lines, Id orderId) {
        applyMovements(lockedProducts, lines, -1, 'Sale', orderId);
    }

    /**
     * Restores stock for one or more orders that were just Cancelled or
     * Returned, and logs one Stock_Movement__c ('Cancellation', positive
     * Quantity__c) per (order, product) pair — bulk-safe for the
     * OrderTrackingService trigger batch that calls this. Best-effort:
     * failure here must never block the admin's own status-change save.
     */
    public static void restoreStockForOrders(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return;
        }
        try {
            // One line per (order, product) — keeps Related_Order__c on the
            // Stock_Movement__c row accurate to the specific order, even
            // when two different orders in the same batch happen to touch
            // the same product (rare, but Running_Balance__c is then only
            // exact for the batch's FINAL balance, not each row's own
            // intermediate step — see the field's own description).
            Map<Id, List<StockLine>> linesByOrder = new Map<Id, List<StockLine>>();
            Set<Id> allProductIds = new Set<Id>();

            for (OrderItem item : [
                SELECT OrderId, Product2Id, Quantity
                FROM OrderItem
                WHERE OrderId IN :orderIds
                WITH SYSTEM_MODE
            ]) {
                if (!linesByOrder.containsKey(item.OrderId)) {
                    linesByOrder.put(item.OrderId, new List<StockLine>());
                }
                StockLine line = new StockLine();
                line.productId = item.Product2Id;
                line.quantity = item.Quantity.intValue();
                linesByOrder.get(item.OrderId).add(line);
                allProductIds.add(item.Product2Id);
            }

            if (allProductIds.isEmpty()) {
                return;
            }

            Map<Id, Product2> productById = new Map<Id, Product2>([
                SELECT Id, Stock_Quantity__c FROM Product2 WHERE Id IN :allProductIds WITH SYSTEM_MODE FOR UPDATE
            ]);

            for (Id orderId : linesByOrder.keySet()) {
                applyMovements(productById, linesByOrder.get(orderId), 1, 'Cancellation', orderId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Stock restoration failed: ' + e.getMessage());
        }
    }

    /**
     * Shared apply step: updates Product2.Stock_Quantity__c (only for
     * products with tracked stock — blank is skipped, same as
     * validateStock) and inserts the matching Stock_Movement__c row(s) for
     * this same call. lockedProducts is mutated in place with each
     * product's new balance, so a caller applying several movements against
     * the same Map (see restoreStockForOrders) always works from the
     * latest quantity, not a stale snapshot.
     */
    private static void applyMovements(Map<Id, Product2> lockedProducts, List<StockLine> lines, Integer direction, String movementType, Id relatedOrderId) {
        List<Product2> toUpdate = new List<Product2>();
        List<Stock_Movement__c> movements = new List<Stock_Movement__c>();

        for (StockLine line : lines) {
            Product2 product = lockedProducts.get(line.productId);
            if (product == null || product.Stock_Quantity__c == null) {
                continue;
            }

            Decimal signedQty = direction * line.quantity;
            Decimal newBalance = product.Stock_Quantity__c + signedQty;

            // Mutates the SObject already held by lockedProducts in place
            // (maps hold references, not copies) — so a second call against
            // the same Map (see restoreStockForOrders processing several
            // orders in one batch) always reads this updated balance, not a
            // stale one.
            product.Stock_Quantity__c = newBalance;

            toUpdate.add(new Product2(Id = product.Id, Stock_Quantity__c = newBalance));

            Stock_Movement__c movement = new Stock_Movement__c();
            movement.Product__c = product.Id;
            movement.Movement_Type__c = movementType;
            movement.Quantity__c = signedQty;
            movement.Running_Balance__c = newBalance;
            movement.Related_Order__c = relatedOrderId;
            movements.add(movement);
        }

        if (toUpdate.isEmpty()) {
            return;
        }

        suppressMovementTrigger = true;
        try {
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
        } finally {
            suppressMovementTrigger = false;
        }

        Database.insert(movements, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Called by Product2TriggerHandler for a Stock_Quantity__c change that
     * did NOT go through this service (e.g. an admin editing the field
     * directly on the Product record in Setup) — logs it as an
     * 'Adjustment' movement so every change to the live number still has a
     * ledger row, matching the design's "no matter which of the four
     * events caused the change" principle. Skipped entirely while this
     * class is mid-way through its own Sale/Cancellation update, which
     * already logs its own precise row (see suppressMovementTrigger).
     */
    public static void logManualAdjustments(List<Product2> newProducts, Map<Id, Product2> oldProductMap) {
        if (suppressMovementTrigger) {
            return;
        }

        List<Stock_Movement__c> movements = new List<Stock_Movement__c>();

        for (Product2 product : newProducts) {
            Product2 oldProduct = oldProductMap.get(product.Id);
            if (oldProduct.Stock_Quantity__c == product.Stock_Quantity__c) {
                continue;
            }

            Decimal oldQty = oldProduct.Stock_Quantity__c == null ? 0 : oldProduct.Stock_Quantity__c;
            Decimal newQty = product.Stock_Quantity__c == null ? 0 : product.Stock_Quantity__c;

            Stock_Movement__c movement = new Stock_Movement__c();
            movement.Product__c = product.Id;
            movement.Movement_Type__c = 'Adjustment';
            movement.Quantity__c = newQty - oldQty;
            movement.Running_Balance__c = product.Stock_Quantity__c;
            movement.Notes__c = 'Manual stock edit.';
            movements.add(movement);
        }

        if (!movements.isEmpty()) {
            Database.insert(movements, AccessLevel.SYSTEM_MODE);
        }
    }
}
