@RestResource(urlMapping='/google-integration/oauth/callback')
global without sharing class OauthCallback {
  @HttpGet
  global static void doGet() {
    RestResponse res = RestContext.response;
    String authCode = RestContext.request.params.get('code');
    String encodedState = RestContext.request.params.get('state');

    if (String.isBlank(authCode)) {
      throw new OAuthException('Authorization code not received');
    }
    String userId = EncodingUtil.base64Decode(encodedState).toString().trim();
    if (String.isBlank(userId)) {
      throw new OAuthException('Invalid state: missing user ID');
    }
    google_api_settings__c settings = google_api_settings__c.getOrgDefaults();
    HttpRequest req = new HttpRequest();
    String tokenExchangeEndpoint = settings.Token_url__c;
    req.setEndpoint('https://oauth2.googleapis.com/token');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    //req.setHeader('Content-Length','0');
    String body =
      'code=' +
      EncodingUtil.urlEncode(authCode, 'UTF-8') +
      '&client_id=' +
      EncodingUtil.urlEncode(settings.ClientId__c, 'UTF-8') +
      '&client_secret=' +
      EncodingUtil.urlEncode(settings.ClientSecret__c, 'UTF-8') +
      '&redirect_uri=' +
      settings.redirect_url__c +
      '&grant_type=authorization_code';

    req.setBody(body);
    Http http = new Http();
    HttpResponse resp = http.send(req);
    if (resp.getStatusCode() == 200) {
      Map<String, Object> tokens = (Map<String, Object>) JSON.deserializeUntyped(
        resp.getBody()
      );
      User userRecord = [
        SELECT Id, Google_Access_Token__c, Google_Refresh_Token__c
        FROM User
        WHERE Id = :userId
      ];
      userRecord.Google_Access_Token__c = (String) tokens.get('access_token');
      userRecord.Google_Refresh_Token__c = (String) tokens.get('refresh_token');
      update userRecord;
    } else {
      throw new OAuthException('Failed to exchange code for tokens: ' + resp);
    }
  }
  public class OAuthException extends Exception {
  }
}
