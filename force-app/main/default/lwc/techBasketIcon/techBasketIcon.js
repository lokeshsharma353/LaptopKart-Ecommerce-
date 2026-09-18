import { LightningElement, api } from 'lwc';

/**
 * TechBasketIcon — a small shared set of line icons used in place of emoji
 * across the storefront's account/dashboard UI. Emoji render inconsistently
 * across OS/browser font sets and read as a placeholder rather than a real
 * icon set on a "premium" site; these are plain inline SVG (stroke =
 * currentColor) so every icon inherits the surrounding text color and
 * matches the site's theme in both light and dark mode with no images or
 * external icon font to load.
 */
export default class TechBasketIcon extends LightningElement {
    /** Which icon to render — see the if:true blocks in the template for the full supported set. */
    @api name = 'user';

    get isGrid() { return this.name === 'grid'; }
    get isUser() { return this.name === 'user'; }
    get isPackage() { return this.name === 'package'; }
    get isGift() { return this.name === 'gift'; }
    get isPin() { return this.name === 'pin'; }
    get isHeart() { return this.name === 'heart'; }
    get isCard() { return this.name === 'card'; }
    get isCash() { return this.name === 'cash'; }
    get isSettings() { return this.name === 'settings'; }
    get isLogout() { return this.name === 'logout'; }
    get isMail() { return this.name === 'mail'; }
    get isPhone() { return this.name === 'phone'; }
    get isLock() { return this.name === 'lock'; }
    get isCamera() { return this.name === 'camera'; }
}
