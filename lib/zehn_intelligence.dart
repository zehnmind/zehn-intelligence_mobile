/// Zehn Intelligence: an in-app AI assistant for Flutter apps.
///
/// The end user asks for something in the app, in their own words. The SDK
/// sends the request to the Zehn Intelligence server, which plans the answer
/// and asks the SDK to run the tools the app registered and to show the app's
/// own widgets. The server never calls the app's backend: the app's handlers
/// do that with the user's own session, and they decide which fields are sent
/// back.
///
/// This file is the package's public API and holds exports only. The code
/// lives in `lib/src/`. Nothing is exported yet: the first exports arrive with
/// the phase 1 tasks (config and `init()`, the registries, the chat UI).
library;
