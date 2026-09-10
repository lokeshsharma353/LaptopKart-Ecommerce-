// Not currently deployable or wired to any trigger — the only place it's
// referenced (OpportunityTrigger.trigger) has that call commented out, and
// the fields it writes (Account.Customer_Status__c, Account.Total_Won_Amount__c)
// don't exist in this org, so activating it would fail to compile.
public class OpprtunityClosedWonHandler {

	/** Would mark an Account as a customer and total up its Closed-Won Opportunity amounts whenever one of its Opportunities is newly won. Currently unusable — see class comment. */
	public static void updateAccountDetails(List<Opportunity>oppList,Map<ID,Opportunity>oldMap){


		Set<Id> accountIds= new Set<Id>();

		for(Opportunity opp : oppList){
			Opportunity oldOpp=oldMap.get(opp.Id);

			if(opp.StageName == 'Closed Won' && oldOpp.StageName !='Closed Won' && opp.AccountId != null)
			{
				accountIds.add(opp.AccountId);

			}
		}
		if(accountIds.isEmpty()){
			return;
		}
		
		List<AggregateResult> results=[
			Select AccountId,Sum(Amount) totalAmount
			from Opportunity
			where AccountId in : accountIds
			And StageName ='Closed Won'
			GROUP BY AccountId
		];
		Map<Id, Decimal> totalAmountMap=new Map<Id, Decimal>();

		for (AggregateResult result : results){
			totalAmountMap.put((Id) result .get ('AccountId'),(Decimal)result.get('totalAmount'));
		}
		List<Account> accountsToUpdate=[
			Select id, Customer_Status__c,Total_Won_Amount__c
			From Account
			Where Id IN : accountIds
		];

		for(Account acc : accountsToUpdate){
			acc.Customer_Status__c=TRUE;
			if(totalAmountMap.containsKey(acc.Id)){
				acc.Total_Won_Amount__c=totalAmountMap.get(acc.Id);
			}
		}
		update accountsToUpdate;
		
		
		
	}


}