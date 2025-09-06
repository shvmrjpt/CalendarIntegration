@RestResource(urlMapping='/google-integration/oauth/callback')
global with sharing class OauthCallback {

    @HttpGet
    global static void handle(){
        //Update user creds
        String authCode = RestContext.request.params.get('code');
        String state = RestContext.request.params.get('state');

        //redirect
        RestResponse res = RestContext.response;
        res.statusCode = 302;
        String baseUrl = URL.getSalesforceBaseUrl().toExternalForm();
        res.addHeader('Location', baseUrl);
    }
}