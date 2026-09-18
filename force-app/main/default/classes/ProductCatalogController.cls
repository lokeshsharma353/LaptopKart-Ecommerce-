public without sharing class ProductCatalogController {

    // This org's Product2 records still carry Salesforce's own default
    // sample data (generators, installation services, SLA tiers) alongside
    // the real laptop catalog. Rather than an allow-list of specific laptop
    // brands (which meant a newly added brand like Samsung, or any future
    // one, silently never appeared on the site until someone remembered to
    // add it here), this is a deny-list of just that leftover sample data's
    // name prefixes — anything else active is treated as a real product and
    // shown. So: add a Product2 with Price__c set (IsActive = true), and it
    // appears on the storefront automatically, whatever brand it is — no
    // Price Book step required at all.
    private static final List<String> NON_PRODUCT_PREFIXES = new List<String>{
        'GenWatt', 'Installation:', 'SLA:'
    };

    // A tracked product (Stock_Quantity__c not null) at or below this many
    // units shows as "Low Stock" instead of "In Stock" — see §3.3.
    private static final Integer LOW_STOCK_THRESHOLD = 3;

    /** Returns every active, priced Product2 except leftover Salesforce sample data — this is the storefront's entire catalog. Reads Product2 directly; no Price Book involved. */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> getProducts() {

        List<ProductView> results = new List<ProductView>();

        // Static SOQL with WITH SYSTEM_MODE so guest users can read products.
        // Price__c != null is the actual "is this product sellable yet" gate
        // now — a product with no price set simply doesn't appear, the same
        // way one with no Price Book entry used to not appear before.
        for (Product2 p : [
            SELECT Id, Name, ProductCode, Description, Family, Price__c, Stock_Quantity__c, Reorder_Level__c
            FROM   Product2
            WHERE  IsActive = true
            AND    Price__c != null
            WITH   SYSTEM_MODE
            ORDER BY Name
        ]) {
            // Keep everything except the leftover Salesforce sample data.
            if (isRealProduct(p.Name)) {
                ProductView view = new ProductView();
                view.productId   = p.Id;
                view.productName = p.Name;
                view.productCode = p.ProductCode;
                view.description = p.Description;
                // Product2.Family is the real, editable category — was a
                // hardcoded 'Laptops' string before.
                view.category    = String.isNotBlank(p.Family) ? p.Family : 'Laptops';
                view.price       = p.Price__c;
                view.stockQuantity = p.Stock_Quantity__c;
                view.stockStatus = stockStatusFor(p.Stock_Quantity__c, p.Reorder_Level__c);
                results.add(view);
            }
        }

        return results;
    }

    /** Blank Stock_Quantity__c means "not tracked" — always shown as available. See the field's own description. Uses the product's own Reorder_Level__c as the low-stock threshold when set, falling back to LOW_STOCK_THRESHOLD otherwise. */
    private static String stockStatusFor(Decimal stockQuantity, Decimal reorderLevel) {
        if (stockQuantity == null) {
            return 'In Stock';
        }
        if (stockQuantity <= 0) {
            return 'Out of Stock';
        }
        Decimal threshold = reorderLevel != null ? reorderLevel : LOW_STOCK_THRESHOLD;
        if (stockQuantity <= threshold) {
            return 'Low Stock';
        }
        return 'In Stock';
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
        @AuraEnabled public Decimal stockQuantity;
        @AuraEnabled public String stockStatus;
    }
}
