// without sharing: see InventoryService — this can run for any DML on
// Product2, including SYSTEM_MODE updates from a Guest-User checkout.
public without sharing class Product2TriggerHandler {

    /** Logs a Stock_Movement__c 'Adjustment' row for any direct Stock_Quantity__c edit that didn't already come through InventoryService (which logs its own precise Sale/Cancellation row and suppresses this). */
    public static void handleAfterUpdate(
        List<Product2> newProducts,
        Map<Id, Product2> oldProductMap
    ) {
        InventoryService.logManualAdjustments(newProducts, oldProductMap);
    }
}
