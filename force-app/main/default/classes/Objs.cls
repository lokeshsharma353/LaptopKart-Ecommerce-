// Scratch/practice class, not referenced by anything in the app — only
// operations() actually runs; everything else below it is commented-out
// practice SOQL/DML snippets kept for reference, not live code.
public class Objs {

/** Demo of a Map<String, Integer> — puts two fruit/quantity pairs in and debug-logs one back out. Not used anywhere. */
public static void operations(){

	Map <String, Integer> inventory = new Map<String, Integer>();
	inventory.put('Apple',1);
	inventory.put('Banana',2);
	System.debug(inventory.get('Apple'));
	
	// List <Account> acclist = [SELECT Id , name From Account];
	// System.debug(acclist);

	// List<Opportunity> deals= [Select  Name From Opportunity WHERE StageName !='Prospecting'];

	// System.debug(deals);

	// List<Case> Cases= [Select CaseNumber from Case Order by CreatedDate ASC ];
	// System.System.debug(Cases);



	// List<Account> accList = [SELECT Id ,Name from Account where Name Like '%Tech%'];
	// System.debug(accList);

	// List<Case> Cases= [Select CaseNumber from Case Order by CreatedDate ASC ];
// for (Case cases : [
//     SELECT Account.Name, CaseNumber
//     FROM Case
//     ORDER BY CreatedDate DESC
//     LIMIT 2
// ]) {
// 	if (Cases.id !=Null){
// 		System.debug('Account name :'+Cases.Account.Name+ 'Case Number :'+cases.CaseNumber);
// 	}
// 	else{
// 		    System.debug(cases.CaseNumber);

// 	}
// }



// List<Account> acc= new List<Account>{
// 	new Account (Name ='Tech Mahindra'),
// 	new Account(Name ='Infosys')
// };
// insert acc;

// System.debug(acc.Size());
// for(Account a : acc){
// 	System.debug(a.Name);
// }

// List<Contact> con = [
//     SELECT Id, Name, AccountId, Account.Name
//     FROM Contact
//     WHERE Account.Name = 'Tech Mahindra'
// ];

// for (Contact c : con) {
//     System.debug('Contact Name: ' + c.Name +' -  Company Name Name: ' + c.Account.Name);
// }


// Account acc= new Account(Name='New Company');
// insert acc;
// System.debug('Account Id = ' + acc.Id);
// System.debug('Account Name = ' + acc.Name);


// List<Contact> contactInsert=new List<Contact>{
// 	new Contact(LastName='Doe'),
// 	new Contact(LastName='Smith')
// };

// insert contactInsert;

// for (Contact c:contactInsert ){
// System.debug(c.LastName);
// System.debug(c.id);



// }

// Account acc=[Select Id,Name,Rating from Account where Name='Edge Communications'];
// acc.Rating='Warm';
// update acc;

// System.debug(acc.Name +'   ---  '+acc.Rating);
//  public Boolean isHighRevenue(Account acc) {
//         return acc.AnnualRevenue != null && acc.AnnualRevenue > 1000000;
//     }


// Account acc = [SELECT Id, AnnualRevenue FROM Account LIMIT 1];
// Operations validator = new Operations();
// System.debug(validator.isHighRevenue(acc));

// }


}}