public with sharing class GoogleCalendarUtility {
  public class SimpleEventDTO {
    @AuraEnabled
    public String eventId;
    @AuraEnabled
    public String htmlLink;
    @AuraEnabled
    public String eventStartTime;
    @AuraEnabled
    public String eventEndTime;
    @AuraEnabled 
    public String label;
    @AuraEnabled
    public Boolean isAllDay;
  }

  @AuraEnabled
  public static List<SimpleEventDTO> getMonthlyEvents(
    String userId,
    String month
  ) {
    if (String.isBlank(userId) || String.isBlank(month)) {
      throw new AuraHandledException(
        'Missing required parameters: userId and month'
      );
    }

    Date firstDayOfMonth = parseMonthToFirstDay(month);
    Date firstDayOfNextMonth = firstDayOfMonth.addMonths(1);

    Datetime timeMinDt = Datetime.newInstanceGmt(
      firstDayOfMonth.year(),
      firstDayOfMonth.month(),
      1,
      0,
      0,
      0
    );
    Datetime timeMaxDt = Datetime.newInstanceGmt(
      firstDayOfNextMonth.year(),
      firstDayOfNextMonth.month(),
      1,
      0,
      0,
      0
    );

    String timeMin = toRfc3339Utc(timeMinDt);
    String timeMax = toRfc3339Utc(timeMaxDt);

    User u = [
      SELECT Google_Access_Token__c, Google_Refresh_Token__c
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];

    if (u == null) {
      throw new AuraHandledException('User not found');
    }

    String accessToken = u.Google_Access_Token__c;
    String refreshToken = u.Google_Refresh_Token__c;

    if (String.isBlank(accessToken) && String.isBlank(refreshToken)) {
      throw new AuraHandledException('User is not connected to Google.');
    }

    try {
      return fetchEventsWithAccessToken(accessToken, timeMin, timeMax);
    } catch (TokenExpiredException e) {
      if (String.isBlank(refreshToken)) {
        throw new AuraHandledException(
          'Access token expired and no refresh token available.'
        );
      }
      String newAccessToken = refreshAccessToken(refreshToken, userId);
      List<SimpleEventDTO> refreshed = fetchEventsWithAccessToken(
        newAccessToken,
        timeMin,
        timeMax
      );
      // Persist token after successful refresh and fetch
      GoogleCalendarUtility.commitToken(newAccessToken, userId);
      return refreshed;
    }
  }

  private static List<SimpleEventDTO> fetchEventsWithAccessToken(
    String accessToken,
    String timeMin,
    String timeMax
  ) {
    if (String.isBlank(accessToken)) {
      throw new AuraHandledException('Missing access token');
    }

    String endpoint =
      'https://www.googleapis.com/calendar/v3/calendars/primary/events' +
      '?singleEvents=true' +
      '&orderBy=startTime' +
      '&maxResults=2500' +
      '&timeMin=' +
      EncodingUtil.urlEncode(timeMin, 'UTF-8') +
      '&timeMax=' +
      EncodingUtil.urlEncode(timeMax, 'UTF-8');

    HttpRequest req = new HttpRequest();
    req.setMethod('GET');
    req.setEndpoint(endpoint);
    req.setHeader('Authorization', 'Bearer ' + accessToken);

    Http http = new Http();
    HttpResponse resp = http.send(req);

    Integer status = resp.getStatusCode();
    if (status == 401 || status == 403) {
      throw new TokenExpiredException('Unauthorized');
    }
    if (status < 200 || status >= 300) {
      String bodyPreview = resp.getBody();
      if (bodyPreview != null && bodyPreview.length() > 1500) {
        bodyPreview = bodyPreview.substring(0, 1500);
      }
      throw new AuraHandledException(
        'Failed to fetch events: HTTP ' + status + ' ' + bodyPreview
      );
    }

    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      resp.getBody()
    );
    List<Object> items = (List<Object>) payload.get('items');
    List<SimpleEventDTO> results = new List<SimpleEventDTO>();
    if (items == null) {
      return results;
    }

    for (Object itemObj : items) {
      Map<String, Object> item = (Map<String, Object>) itemObj;
      SimpleEventDTO dto = new SimpleEventDTO();
      dto.eventId = (String) item.get('id');
      dto.htmlLink = (String) item.get('htmlLink');
      dto.label = (String) item.get('summary');
      Map<String, Object> startMap = (Map<String, Object>) item.get('start');
      Map<String, Object> endMap = (Map<String, Object>) item.get('end');

      String startDateTime = (String) startMap.get('dateTime');
      String endDateTime = (String) endMap.get('dateTime');
      Boolean isAllDay = false;

      if (String.isBlank(startDateTime)) {
        String startDate = (String) startMap.get('date');
        if (!String.isBlank(startDate)) {
          startDateTime = startDate + 'T00:00:00Z';
          isAllDay = true;
        }
      }

      if (String.isBlank(endDateTime)) {
        String endDate = (String) endMap.get('date');
        if (!String.isBlank(endDate)) {
          endDateTime = endDate + 'T00:00:00Z';
        }
      }

      dto.eventStartTime = startDateTime;
      dto.eventEndTime = endDateTime;
      dto.isAllDay = isAllDay;
      results.add(dto);
    }
    return results;
  }

  private static String refreshAccessToken(String refreshToken, String userId) {
    google_api_settings__c settings = google_api_settings__c.getOrgDefaults();

    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://oauth2.googleapis.com/token');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

    String body =
      'grant_type=refresh_token' +
      '&refresh_token=' +
      EncodingUtil.urlEncode(refreshToken, 'UTF-8') +
      '&client_id=' +
      EncodingUtil.urlEncode(settings.ClientId__c, 'UTF-8') +
      '&client_secret=' +
      EncodingUtil.urlEncode(settings.ClientSecret__c, 'UTF-8');
    req.setBody(body);

    Http http = new Http();
    HttpResponse resp = http.send(req);
    if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
      throw new AuraHandledException('Failed to refresh access token');
    }

    Map<String, Object> tokenPayload = (Map<String, Object>) JSON.deserializeUntyped(
      resp.getBody()
    );
    String newAccessToken = (String) tokenPayload.get('access_token');
    if (String.isBlank(newAccessToken)) {
      throw new AuraHandledException('Refresh response missing access_token');
    }

    return newAccessToken;
  }

  private static Date parseMonthToFirstDay(String month) {
    // Expected formats: 'YYYY-MM' or 'YYYY/MM'
    String normalized = month.replace('/', '-').trim();
    List<String> parts = normalized.split('-');
    if (parts.size() != 2) {
      throw new AuraHandledException('Invalid month format. Expected YYYY-MM');
    }
    Integer year;
    Integer mon;
    try {
      year = Integer.valueOf(parts[0]);
      mon = Integer.valueOf(parts[1]);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Invalid month numbers in month parameter'
      );
    }
    if (year < 1970 || mon < 1 || mon > 12) {
      throw new AuraHandledException('Month out of valid range');
    }
    return Date.newInstance(year, mon, 1);
  }

  private static String toRfc3339Utc(Datetime dt) {
    // Format as 2025-06-01T00:00:00Z
    return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
  }

  @AuraEnabled
  public static Boolean isUserSignedIn(String userId) {
    User userRecord = [
      SELECT Id, Google_Access_Token__c, Google_Refresh_Token__c
      FROM User
      WHERE Id = :userId
    ];
    if (userRecord.Google_Refresh_Token__c == '' || userRecord.Google_Refresh_Token__c == null) {
      return false;
    }
    return true;
  }

  public class TokenExpiredException extends Exception {
  }

  @future(callout=true)
  public static void commitToken(String accessToken, String userId){
    update new User(Id = userId, Google_Access_Token__c = accessToken);
  }
}
