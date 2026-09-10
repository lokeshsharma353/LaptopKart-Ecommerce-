// without sharing: see OrderService for why — this class is the trigger
// handler that calls it, in the same execution context.
public without sharing class OpportunityTriggerHandler {

    /** Fires OrderService.createOrders() for every Opportunity that just became Closed Won in this update. */
    public static void handleAfterUpdate(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldOppMap
    ) {

        List<Opportunity> closedWonOpps = new List<Opportunity>();

        for (Opportunity opp : newOpps) {

            Opportunity oldOpp = oldOppMap.get(opp.Id);

            if (
                opp.StageName == 'Closed Won' &&
                oldOpp.StageName != 'Closed Won'
            ) {
                closedWonOpps.add(opp);
            }
        }

        if (!closedWonOpps.isEmpty()) {
            OrderService.createOrders(closedWonOpps);
        }
    }
}