# Legacy Google account backups

Google sign-in and the cloud backup screen have been retired from the phone
app. Full users can import and export Desktop-managed layouts in Desktop's
**Shortcut Layout** page. Local Profile JSON import and export remain available
in the versions that expose a local Profile editor.

Existing deployments retain the authenticated `/v1/account/backup` endpoints
and the PostgreSQL snapshots associated with legacy clients. Updating the phone
app does not modify those snapshots. Operators can use their existing
[deployment and database backup procedures](../community_server/README.md).
Community ranking and contributions continue through their independent APIs.
