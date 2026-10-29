# registry

`ToolRegistry` (the app's tool handlers) and `ComponentRegistry` (the app's widget builders). Names
are checked at registration, and every call and every mount is checked before the app's code runs.
A handler's result must be JSON and within the size limit.

Task: P1-SDK-04.
