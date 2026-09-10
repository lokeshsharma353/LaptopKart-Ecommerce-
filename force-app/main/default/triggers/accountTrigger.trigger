trigger accountTrigger on Account(after Update) {
    
    









    
    // Map<Id, Account> accMap=new Map<Id,Account> ();
    // if (trigger.isAfter && trigger.isUpdate) {
    //     if(!trigger.new.isEmpty()){
    //         for(Account acc : trigger.new){
    //             if(trigger.oldMap.get(acc.Id).Phone !=acc.Phone){
                    
    //                 accMap.put(acc.Id, acc);
                    
    //             }
    //         }
    //     }
        
    // }
    
    // List<Contact> conList = [Select Id,AccountId,Phone from Contact Where AccountId in : accMap.keySet()];
    // List <Contact> listToUpdate = new List<Contact>();
    // if(!conList.isEmpty()){
    //     for(Contact con : conList ){
    //         con.Phone =accMap.get(con.AccountId).Phone;
    //     }
    // }
    // if(!listToUpdate.isEmpty()){
        
    //     update  listToUpdate;
    // }
    
    
    
    
    
    
    
    
    
    
    
    
    
    // if (trigger.isBefore && (trigger.isInsert || trigger.isUpdate)) {
        
        //     if (!trigger.new.isEmpty()){
            //         for (Account acc :trigger.new ){
                
                //             if(acc.BillingStreet !=null){
                    //                 acc.ShippingStreet =acc.BillingStreet;
                //             }
                //             if(acc.BillingState != null){
                    //                 acc.ShippingState = acc.BillingState;
                //         }
                //         if(acc.BillingCountry!=null){acc.ShippingCountry = acc.BillingCountry;
                //         }
                
            //     }
        //     }
        
    // }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // if(Trigger.isUpdate){
        //     if(Trigger.isBefore){
            //          AccountTriggerHandler.updatePhone(Trigger.New,Trigger.oldMap);
            
        //     }
    // }
    
    
    
    
    // if (trigger.isinsert){
        //  if(trigger.isBefore){
            
            //      AccountTriggerHandler.TypeEnter(Trigger.New);
        //  }
    // }
    
    
    
    
    // if(trigger.isInsert){
        //  if(trigger.isBefore){
            //      AccountTriggerHandler.Industry(Trigger.New);
        //  }
    // }
    
    
    // if(Trigger.isInsert){
        //  if(Trigger.isBefore){
            //      AccountTriggerHandler.updateDesc(Trigger.New);
            //      AccountTriggerHandler.populateRating(Trigger.New);
        //  }else if(Trigger.isAfter){
            //      AccountTriggerHandler.createopp(Trigger.New);
            
        //  }
    // }
    
    // for (Account acc: Trigger.new){
        //  acc.Description ='New Account';
    // }
    
    // if (Trigger.isinsert){
        //  if(Trigger.isBefore){
            //  for (Account acc: Trigger.new){
                //      acc.Description ='New Account';
            //  }
            
        //  }
    // }
    
    
}