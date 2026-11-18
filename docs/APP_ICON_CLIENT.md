# Full mobile launcher and icon synchronization

Full starts on its landscape-only, twelve-slot Launchpad. Slot order comes
from LumiaKey Desktop. Empty slots remain empty and explain how to configure
them on the computer. Installed-app discovery never fills or replaces the
saved slots. Old eight-slot manifests are padded to twelve; an explicitly
cleared launcher remains cleared after restart.

Selecting an application sends its Desktop application ID. Full waits for a
new activation sequence for that application and a matching foreground state
before enabling its shortcuts. A successful HTTP response alone is insufficient.
Returning to Launchpad, disconnecting, rotating into a portrait window, or
switching computers invalidates pending selection work. Notifications do not
automatically navigate away from Launchpad.

## Icon sources and validation

The client first checks a valid computer-scoped native icon cache, then requests
the computer's authenticated `GET /icons/{appId}` resource when available.
Bundled brand assets remain usable offline. Unknown IDs, failed requests, and
invalid images fall back to bundled artwork or a generic application mark.
Turning off Desktop's **Sync Icons** prevents native requests and hides native
cached artwork until icon synchronization is enabled again.

Native and centralized-download images must be PNG, at most 64 KiB, and at most
512 pixels on either side. The client checks the PNG header dimensions before
decoding and rejects invalid image data. Icon requests never accept an arbitrary
remote image URL from a manifest.

Persistent cache scopes use the stable Desktop computer ID and platform, with
the host address as the fallback for legacy computers without an ID. A random
Desktop port change does not discard a stable computer's cache. Each application
cache identity includes its executable and icon metadata. A change to either
invalidates that application's cached image. Cached images expire after 24 hours;
foreground/activation-only manifest revisions do not redownload every icon.
In-flight requests additionally check the active connection session, so a late
response from another computer cannot populate the current screen.

## Optional centralized service

`SMARTKEYS_ICON_URL` is a build-time, same-origin HTTPS service setting. Its
default is empty: this change does **not** establish or deploy a public icon
service. Without that setting, bundled artwork and authenticated native Desktop
icons work without a centralized service. The separately supplied Rust dashboard
can serve the registered catalog and `GET /v1/icons/{appId}` PNG resources when
deployed and configured. The client refuses redirects and unknown catalog IDs.
Loopback HTTP is supported only by an explicit development/test constructor flag.

`test/app_icon_client_test.dart` exercises real loopback HTTP for authentication,
catalog downloading, redirect rejection, bounded image data, and the Sync Icons
setting, alongside cache isolation and expiry tests. These tests do not claim
that an Internet icon endpoint is deployed or that native platform extraction
has been tested on every physical computer.
