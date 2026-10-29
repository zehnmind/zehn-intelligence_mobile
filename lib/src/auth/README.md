# auth

The user token holder: `setUser(token, onTokenExpired: …)` and `clearUser()`. The SDK stores the
token and never reads it. When the server says the token expired, the SDK asks the app for a new one
once (concurrent calls share that refresh) and retries the request once.

Task: P1-SDK-03.
