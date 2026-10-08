# Savr

Compare what you'll actually pay across quick-commerce, grocery, shopping, food and ride apps,
by searching for a name, pasting a link, or using **Share → Savr** from Blinkit, Zepto, Amazon and other apps.

| Vertical | Platforms |
|---|---|
| Quick commerce | Blinkit, Zepto, Swiggy Instamart, BB Now, Flipkart Minutes, Amazon Now |
| Grocery | BigBasket, JioMart, DMart Ready, Amazon Fresh |
| Shopping | Amazon, Flipkart, Myntra, Meesho, AJIO, Croma, Tata CLiQ, Nykaa, JioMart |
| Food | Swiggy, Zomato, magicpin |
| Rides | Uber, Ola, Rapido, Namma Yatri, inDrive |

## Where prices come from

None of these platforms has a public pricing API, and quick-commerce prices change by pincode and time of day.
Savr has three data modes (Admin → Price source):

- **On this phone** (default). Blinkit, Zepto and Swiggy Instamart are fetched live on the device.
  Savr loads each platform's own search page in a hidden, locked-down WebView and reads the JSON the page itself receives
  (`lib/data/device/`). It works on mobile data or Wi-Fi with no server. The user picks their address once on each
  platform (Settings → Live prices) so prices match their local store. Each search takes about 5 s per platform, with
  platforms running in parallel. Other categories fall back to labelled samples.
- **Price server**. Your own aggregator backend (contract below). Use this when you have real users.
- **Sample**. Offline, deterministic illustrative prices, always labelled as samples.
- **Rides**. Fares are estimated from approximate rate cards (`lib/data/ride_estimator.dart`) and always labelled as estimates.

Every result also deep-links to the platform's own search.

### When a platform breaks

Platforms change their sites. Run the on-device smoke test to see which platform broke:

```bash
flutter test integration_test/live_fetch_test.dart -d <device-id>
```

Debug builds log the page lifecycle with the `[savr:<platform>]` prefix. The fix is usually a changed response
field in `scrapers.dart`; update the fixture in `test/device_scrapers_test.dart` to match.

### Live backend contract

```
GET  {base}/v1/health                     → 200
GET  {base}/v1/search?q=&vertical=quick|grocery|shopping|food&platforms=blinkit,zepto&pincode=560034
     Authorization: Bearer <apiKey>
200  { "offers": [ {
        "platform": "blinkit",          // must be a platform id from lib/core/platforms.dart
        "title": "Amul Taaza Toned Milk",
        "group": "amul-taaza-500ml",    // optional: same SKU across platforms
        "pack": "500 ml",               // used for per-unit price
        "price": 28, "mrp": 30, "deliveryFee": 0,
        "etaMinutes": 9, "inStock": true,
        "url": "https://blinkit.com/prn/…", // dropped unless it's on that platform's own host
        "seller": null
     } ] }
```

You could build this with n8n, Apify actors or your own scrapers. Before you do, check each platform's terms of service.

## Admin panel

Settings → tap **Version** 7 times. On first open you set a passcode. The panel has:
data source and API key, connection test, per-platform toggles, diagnostics, cache and history clearing,
passcode change and factory reset.

## Security (OWASP MASVS / Mobile Top 10)

| Area | Control |
|---|---|
| Credentials | No hard-coded secrets. The admin passcode is PBKDF2-HMAC-SHA512 (210k iterations, 16-byte salt) and is compared in constant time. Repeated failures trigger an exponential lock-out (30 s up to 1 h) that persists across restarts. |
| Session | Admin auto-locks after 3 min idle or when the app is backgrounded. FLAG_SECURE blocks screenshots and recents thumbnails while admin is open. |
| Storage | The API key and passcode hash live in the Android Keystore (`flutter_secure_storage`). Backups and device transfer are disabled (`allowBackup=false`, `dataExtractionRules`). |
| Network | HTTPS only (`usesCleartextTraffic=false` and a network security config that trusts system CAs only). Redirects are followed manually and every hop is checked against the host allowlist. Requests have a 12 s timeout and a 2 MB response cap. |
| Input | Pasted text and share intents are length-capped and sanitised. Links are accepted only from allowlisted platform hosts (lookalike hosts like `blinkit.com.evil.io` are rejected). The backend URL must be `https` with no credentials, query or fragment. |
| Untrusted data | Backend JSON is type- and range-checked, unknown platforms are dropped, and offer URLs are kept only if they're on the platform's own host. Only `https` platform URLs are ever launched (no `intent:`, `javascript:` or `file:`). |
| Errors | Users only ever see fixed messages. Raw exceptions and server bodies are never shown. |
| Embedded browser | WebViews load only HTTPS pages on the platform's own hosts (other schemes and hosts are cancelled). File and content access, popups, mixed content and geolocation are disabled. The capture script only reads responses and never touches cookies or the DOM. Captured data is validated like any untrusted input, and Savr never sees passwords or payment details. |
| Binary | Release builds use `--obfuscate --split-debug-info` and R8 shrinking. |

## Build

```bash
flutter test
flutter build apk --release --obfuscate --split-debug-info=build/symbols --split-per-abi
```

Package / bundle ID: `in.ekrion.savr`. Launcher icons are generated from `lib/theme/brand_mark.dart`:

```bash
flutter test tool/generate_icons_test.dart   # mipmap PNGs + branding/play_store_icon.png
```

Adaptive and themed (Android 13) icons are vectors in `android/app/src/main/res/drawable/ic_launcher_*.xml`; keep them in sync with `BrandMark` if the mark changes.

**Before publishing:** set up a real release signing config (release is currently signed with the debug key).
