// Handler for AccountTrigger. Only updatePhone is currently wired up to the
// trigger; every other method below is commented out and not running.
public class AccountTriggerHandler {

  /** Records the old and new phone number in Description whenever an Account's Phone field changes. */
  public static void updatePhone(List<Account> accList , Map<Id,Account> accOldMap){
    for (Account acc : accList){
      if(acc.Phone !=accOldMap.get(acc.Id).Phone){
        acc.Description= 'Phone is Updated | Old Value = '+ accOldMap.get(acc.Id).Phone + ' New Value = '+acc.Phone;
      }
    }
  }

// public static void TypeEnter(List <Account> accList){
//   for (Account acc: accList){
//     if(acc.Type=='Customer - Direct' && acc.Type!=null)
//     acc.Industry='Technology';
//   }
// }


  //  public static void Industry(List<Account>accList){
  //       for(Account acc : accList ){
	// 		acc.Industry='Technology';
	// 	}
  //   }
// public static void createopp(List<Account> accList ){
// 	List<Opportunity> oppList= new List<Opportunity>();

// 	for(Account acc: accList){
// 		Opportunity opp= new Opportunity();
// 		opp.Name = acc.Name;
// 		opp.CloseDate= System.today();
// 		opp.StageName='Prospecting';
// 		opp.AccountId=acc.Id;
// 		oppList.add(opp);

// 	}
// 	if(!oppList.isEmpty()){
// 		insert oppList;


// 	}


// }

// public static void updateDesc(List<Account> accList){
// 	for(Account acc : accList){
// 		acc.Description='Account is created';

// 	}
// }
// public static void populateRating(List<Account> accList){
// 	for(Account acc : accList){
// 		if(acc.Industry != null && acc.Industry =='Media'){
// 			acc.Rating='Hot';
// 		}
// 	}
// }

}