trigger contactTrigger on Contact (after update) {
    // Disabled — never enabled, kept only as a record of the original intent
    // (sync a changed Contact.Description onto its Account.Description).
    // An empty trigger body is a deliberate no-op, not a bug: the entire
    // previous version of this file was commented out, including the
    // `trigger ... {` declaration line itself, which is not valid Apex and
    // cannot be deployed under any circumstances — every deploy attempt
    // that included this file was guaranteed to fail with a parse error
    // regardless of anything else in the same deploy.
    //
    // Set<Id> accIds = new Set<Id>();
    // if (trigger.isAfter && trigger.isUpdate) {
    //     if (!trigger.new.isEmpty()) {
    //         for (Contact con : trigger.new) {
    //             if (con.AccountId != null && trigger.oldMap.get(con.Id).Description != con.Description) {
    //                 accIds.add(con.AccountId);
    //             }
    //         }
    //     }
    // }
    //
    // Map<Id, Account> accMap = new Map<Id, Account>([SELECT Id, Description FROM Account WHERE Id IN :accIds]);
    // List<Account> listToUpdate = new List<Account>();
    //
    // if (!trigger.new.isEmpty()) {
    //     for (Contact cont : trigger.new) {
    //         Account acc = accMap.get(cont.AccountId);
    //         acc.Description = cont.Description;
    //         listToUpdate.add(acc);
    //     }
    // }
}
