import { LightningElement } from "lwc";
import isUserSignedIn from "@salesforce/apex/GoogleCalendarUtility.isUserSignedIn";
import userId from "@salesforce/user/Id";

export default class CalendarTab extends LightningElement {
  loginCheck = false;
  isLoading = true;
  async connectedCallback() {
    try {
      const result = await isUserSignedIn({ userId });
      this.loginCheck = Boolean(result);
    } catch (e) {
      console.error("Failed to check Google sign-in status", JSON.stringify(e));
      this.loginCheck = false;
    } finally {
      this.isLoading = false;
    }
  }
}
