import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import PROFILE_PHOTO_FIELD from '@salesforce/schema/Account.Profile_Photo__c';
import NAME_FIELD from '@salesforce/schema/Account.Name';

/**
 * AccountProfilePhoto — renders a customer's uploaded profile photo (a data
 * URI stored in Account.Profile_Photo__c) as an actual image on the Account
 * record page, instead of the raw base64 text the field shows in the
 * standard Details layout. Uses Lightning Data Service (getRecord) rather
 * than a formula field with IMAGE() because a resized photo's data URI runs
 * to tens of thousands of characters — well past what a formula field's
 * compiled output can reliably carry — while a wired record field has no
 * such limit.
 */
export default class AccountProfilePhoto extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [PROFILE_PHOTO_FIELD, NAME_FIELD] })
    account;

    get photoUrl() {
        return this.account?.data?.fields?.Profile_Photo__c?.value;
    }

    get accountName() {
        return this.account?.data?.fields?.Name?.value || 'Account';
    }

    get hasPhoto() {
        return !!this.photoUrl;
    }
}
