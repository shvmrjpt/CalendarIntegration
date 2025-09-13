public with sharing class OauthUtility {
  @AuraEnabled
  public static String getAuthUrl() {
    google_api_settings__c settings = google_api_settings__c.getOrgDefaults();
    String[] scopes = new List<String>{
      'openid',
      'email',
      'https://www.googleapis.com/auth/calendar.calendarlist',
      'https://www.googleapis.com/auth/calendar.events',
      'https://www.googleapis.com/auth/calendar.readonly'
    };
    // Use userId as state for user-specific token storage
    String encodedState = EncodingUtil.base64Encode(
      Blob.valueOf(UserInfo.getUserId())
    );
    Map<String, String> params = new Map<String, String>{
      'client_id' => settings.ClientId__c,
      'redirect_uri' => settings.redirect_url__c,
      'response_type' => 'code',
      'scope' => String.join(scopes, ' '),
      'prompt' => 'consent',
      'access_type' => 'offline',
      'state' => encodedState
    };
    List<String> queryParams = new List<String>();
    for (String key : params.keySet()) {
      String encodedKey = EncodingUtil.urlEncode(key, 'UTF-8');
      String encodedValue = EncodingUtil.urlEncode(params.get(key), 'UTF-8');
      queryParams.add(encodedKey + '=' + encodedValue);
    }
    String finalUrl =
      settings.Auth_url__c +
      '?' +
      String.join(queryParams, '&');
    return finalUrl;
  }
}
