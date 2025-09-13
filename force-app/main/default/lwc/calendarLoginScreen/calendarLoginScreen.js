import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import googleLogo from '@salesforce/resourceUrl/google_logo';
import getAuthUrl from '@salesforce/apex/OauthUtility.getAuthUrl';

export default class CalendarLoginScreen extends LightningElement {
  googleLogoUrl = googleLogo;
  oauthUrl = ''; // Will be populated later with actual OAuth URL

  handleGoogleLogin() {
    if (this.oauthUrl) {
      window.open(this.oauthUrl, '_blank', 'noopener,noreffer');
    } else {
      console.error('OAuth URL not configured');
    }
  }

  async connectedCallback() {
    this.oauthUrl = await getAuthUrl();
  }
}
