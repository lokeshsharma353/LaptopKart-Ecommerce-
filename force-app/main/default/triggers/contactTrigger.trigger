// trigger contactTrigger on Contact (after update){
//     Set<Id> accIds = new Set<Id>();
//     if (trigger.isAfter && trigger.isUpdate) {
//         if (!trigger.new.isEmpty()) {
//             for(Contact con : trigger.new){
//                 if(con.AccountId !=null && trigger.oldMap.get(con.Id).Description!=con.Description){
//                     accIds.add(con.AccountId);
//                 }
//             }
            
//         }
        
//     }
    
    
//     Map<Id, Account> accMap = new Map<Id, Account>([Select Id, Description from Account Where Id in : accIds]);
//     List<Account> listToUpdate = new List<Account>();

//     if (!trigger.new.isEmpty()) {
//         for (Contact cont : trigger.new) {
//             Account acc=accMap.get(Cont.AccountId);
//             acc.Description=cont.Description;
//             listToUpdate.add(acc);
            
//         }
        
//     }
// }