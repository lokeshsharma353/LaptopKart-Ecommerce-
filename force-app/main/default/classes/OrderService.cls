// without sharing: this runs inside the OpportunityTrigger chain fired by
// CheckoutController's Closed-Won update. "WITH SYSTEM_MODE" on the SOQL
// below only bypasses object/field permissions, not sharing — and a Guest
// User's implicit visibility to its own just-created Opportunity depends on
// a criteria-based Guest Sharing Rule that hasn't recalculated yet within
// this same transaction. Without this keyword, the OpportunityLineItem
// query below returns 0 rows for a real Guest checkout (confirmed via a
// live debug log), silently producing an Order with no OrderItems.
public without sharing class OrderService {

    /** Creates one Order (+ its OrderItems, copied from the Opportunity's line items) per Closed-Won Opportunity passed in. */
    public static void createOrders(List<Opportunity> closedWonOpps) {

        // STEP 1: Create Orders
        List<Order> ordersToInsert = new List<Order>();

        for (Opportunity opp : closedWonOpps) {
            Order ord = new Order();
            ord.AccountId = opp.AccountId;
            ord.Pricebook2Id = opp.Pricebook2Id;
            ord.EffectiveDate = opp.CloseDate;
            ord.Status = 'Draft';
            // Explicitly forced to the running user — see CheckoutController
            // for why: leaving this to default under AccessLevel.SYSTEM_MODE
            // was observed to silently assign ownership to someone other than
            // the actual running user, which then blocks that same user from
            // referencing the Order later (Order_Tracking__c, Payment__c) for
            // a Guest User the same way it blocked this Order from
            // referencing its Account.
            ord.OwnerId = UserInfo.getUserId();
            ordersToInsert.add(ord);
        }

        // AccessLevel.SYSTEM_MODE — this trigger chain can be invoked by an
        // Experience Cloud Guest User (see CheckoutController), and Guest
        // Users are denied cross-reference access to records (like the
        // Account this Order points to) they don't have sharing visibility
        // into, even with object permissions granted. SYSTEM_MODE bypasses
        // that; it's a strict superset of the previous plain `insert`, so it
        // doesn't change behavior for any other caller of this class.
        Database.insert(ordersToInsert, AccessLevel.SYSTEM_MODE);


        // STEP 2: Map Opportunity → Order
        Map<Id, Order> opportunityOrderMap = new Map<Id, Order>();

        for (Integer i = 0; i < closedWonOpps.size(); i++) {
            opportunityOrderMap.put(closedWonOpps[i].Id, ordersToInsert[i]);
        }


        // STEP 3: Get Opportunity Products
        List<OpportunityLineItem> oppProducts = [
            SELECT Id, OpportunityId, PricebookEntryId, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityOrderMap.keySet()
            WITH SYSTEM_MODE
        ];


        // STEP 4: Create Order Products
        List<OrderItem> orderProducts = new List<OrderItem>();

        for (OpportunityLineItem oppProduct : oppProducts) {
            OrderItem orderProduct = new OrderItem();

            orderProduct.OrderId = opportunityOrderMap.get(oppProduct.OpportunityId).Id;
            orderProduct.PricebookEntryId = oppProduct.PricebookEntryId;
            orderProduct.Quantity = oppProduct.Quantity;
            orderProduct.UnitPrice = oppProduct.UnitPrice;

            orderProducts.add(orderProduct);
        }


        // STEP 5: Insert Order Products
        if (!orderProducts.isEmpty()) {
            Database.insert(orderProducts, AccessLevel.SYSTEM_MODE);
        }
    }
}
