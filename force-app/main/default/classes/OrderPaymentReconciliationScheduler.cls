// Cron-scheduled trigger for OrderPaymentReconciliationBatch — schedule via
// Setup > Apex Classes > Schedule Apex, or System.schedule(...) in Anonymous Apex.
public class OrderPaymentReconciliationScheduler
    implements Schedulable {

    // Start the payment reconciliation batch.
    // Batch processes Orders in manageable groups.
    public void execute(
        SchedulableContext sc
    ) {

        Database.executeBatch(
            new OrderPaymentReconciliationBatch()
        );
    }
}