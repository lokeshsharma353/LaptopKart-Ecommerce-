public without sharing class ProductCatalogController {

    // This org's Standard Price Book still carries Salesforce's own default
    // sample data (generators, installation services, SLA tiers) alongside
    // the real laptop catalog. Rather than an allow-list of specific laptop
    // brands (which meant a newly added brand like Samsung, or any future
    // one, silently never appeared on the site until someone remembered to
    // add it here), this is a deny-list of just that leftover sample data's
    // name prefixes — anything else in the active Standard Price Book is
    // treated as a real product and shown. So: add a Product2 + Standard
    // Price Book entry (IsActive = true on both) in Setup, and it appears
    // on the storefront automatically, whatever brand it is.
    private static final List<String> NON_PRODUCT_PREFIXES = new List<String>{
        'GenWatt', 'Installation:', 'SLA:'
    };

    /** Returns every active Product2/PricebookEntry in the Standard Price Book except leftover Salesforce sample data — this is the storefront's entire catalog. */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> getProducts() {

        List<ProductView> results = new List<ProductView>();

        // Static SOQL with WITH SYSTEM_MODE so guest users can read products.
        // All active pricebook entries are fetched first, then filtered in Apex
        // by brand name prefix — this avoids dynamic Database.query() which does
        // not support WITH SYSTEM_MODE and fails for guest/public site users.
        for (PricebookEntry entry : [
            SELECT Product2Id,
                   Product2.Name,
                   Product2.ProductCode,
                   Product2.Description,
                   Product2.Family,
                   UnitPrice
            FROM   PricebookEntry
            WHERE  Pricebook2.IsStandard = true
            AND    IsActive = true
            AND    Product2.IsActive = true
            WITH   SYSTEM_MODE
            ORDER BY Product2.Name
        ]) {
            // Keep everything except the leftover Salesforce sample data.
            if (isRealProduct(entry.Product2.Name)) {
                ProductView view = new ProductView();
                view.productId   = entry.Product2Id;
                view.productName = entry.Product2.Name;
                view.productCode = entry.Product2.ProductCode;
                view.description = entry.Product2.Description;
                view.category    = 'Laptops';
                view.price       = entry.UnitPrice;
                results.add(view);
            }
        }

        return results;
    }

    // Returns false only for the known Salesforce sample-data prefixes.
    private static Boolean isRealProduct(String productName) {
        if (String.isBlank(productName)) return false;
        String lower = productName.toLowerCase();
        for (String prefix : NON_PRODUCT_PREFIXES) {
            if (lower.startsWith(prefix.toLowerCase())) return false;
        }
        return true;
    }

    // Product data returned to the LWC storefront.
    public class ProductView {
        @AuraEnabled public Id      productId;
        @AuraEnabled public String  productName;
        @AuraEnabled public String  productCode;
        @AuraEnabled public String  description;
        @AuraEnabled public String  category;
        @AuraEnabled public Decimal price;
    }
}
