# Authentication Architecture

Authentication is a platform concern. Providers request sessions from the Authentication Manager; they never authenticate directly.

Flow:
UI -> Service Layer -> Authentication Manager -> Adapter -> Authentication Session -> Microsoft APIs
