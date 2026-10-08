# Savr: project status

_Last updated: 5 Oct 2026_

Savr is a Flutter app (Android-first) that compares what you'll pay for the same product across quick-commerce,
grocery, shopping, food and ride apps. You can search by name, paste a product link, or use **Share → Savr**
from another app.

- **Package / bundle ID:** `in.ekrion.savr`
- **Tested on:** Samsung Galaxy A36 (Android, wireless adb) and a Pixel 9 Pro emulator (Android 17)
- **Checks:** `flutter analyze` is clean, 26 unit tests pass, and the on-device smoke test passes for all 3 live platforms

---

## What's done

### Research and data strategy
- None of the target apps (Blinkit, Zepto, Instamart, Swiggy, Zomato, Ola, Rapido…) has a public price API.
  Existing comparison apps (Smartprix, Comparify, Quick Compare) rely on scraping or paid data vendors.
- Plain HTTP requests from the app get bot-blocked (Blinkit/Instamart return 403, Zepto returns an AWS WAF challenge).
- **Decision:** start with **on-device fetching**. Savr loads each platform's own search page in a hidden in-app
  browser and reads the prices that page receives. Move to a **dedicated backend** once there are real users.
  The app already supports both.

### Data modes (Admin → Price source)
| Mode | Status |
|---|---|
| **On this phone** (default) | Live for **Blinkit, Zepto, Swiggy Instamart**. About 5 s per search, all three in parallel |
| **Price server** | Client side is ready (HTTPS only, validated JSON). The backend itself is not built |
| **Sample** | Offline illustrative prices, always labelled as samples |
| **Rides** | Fare *estimates* from rate cards for Uber, Ola, Rapido, Namma Yatri and inDrive, labelled as estimates |

Live results verified on the phone from a fresh session:

| Platform | Products | Time |
|---|---|---|
| Blinkit | 29 | 4.8 s |
| Zepto | 24 | 4.6 s |
| Instamart | 59 | 4.7 s |

### Features
- Search by name, or paste a link (Blinkit, Zepto, Instamart, Amazon, Flipkart, BigBasket, JioMart, Myntra, Meesho, Swiggy, Zomato).
- **Share → Savr** from other Android apps.
- Covers 27 platforms across 5 categories. All of them get a "check live in each app" deep link.
- Sorting: lowest price, lowest per unit, fastest delivery, biggest discount, highest price.
- Filters: apps, delivery time, maximum price, in-stock only, include delivery fee.
- **Cross-platform product matching** with fuzzy titles and the same pack size, e.g. "Amul Taaza Toned Milk" =
  "Amul Taaza Homogenised Toned Milk (Tetra Pack)".
- Best-match summary card showing the lowest price and how much you save versus the highest.
- Per-unit price (₹ per 100 g, 100 ml or piece), parsing pack labels like `1 pack (200 ml)`, `1 ltr x 12` and `2 x 200 ml`.
- One-time **"set your address"** screen per platform, done on the platform's own site inside Savr.
- Rides tab: distance slider, normal/peak toggle, vehicle-type filter, fastest-pickup sort, book via deep link.
- Settings: theme (system/light/dark), pincode, delivery-fee and unit-price toggles, clear history, licences.

### Admin panel (Settings → tap **Version** 7 times)
- Passcode is set on first use: PBKDF2-HMAC-SHA512 with 210k iterations and a salt, stored in the Android Keystore.
- Lock-out after 3 wrong attempts: 30 s, doubling up to 1 h, and it survives app restarts.
- Auto-locks after 3 minutes idle or when you leave the app. Screenshots are blocked while it's open.
- Contains: data mode, server URL and API key, connection test, per-platform on/off, request stats,
  clear cache and history, reset app sessions, change passcode, factory reset.

### Security (OWASP MASVS / Mobile Top 10)
- No hard-coded secrets. Secrets are kept in the Keystore, and app backups and device transfer are disabled.
- HTTPS only, enforced by the network security config, which also trusts system certificates only.
- Redirects are checked hop by hop against a list of allowed hosts. Requests time out and responses are size-capped.
- Links are accepted only from allowed hosts, so lookalikes like `blinkit.com.evil.io` are rejected.
  Only `https` platform links are ever opened.
- All third-party data (backend JSON and captured page JSON) is type-checked and range-checked, with bounded tree walks.
- The in-app browsers can only load the platform's own HTTPS pages. File access, popups, mixed content and
  geolocation are off. The capture script only reads responses.
- Users only see generic error messages, never raw exceptions.
- Release builds are obfuscated and shrunk with R8.

### Design
- **Light mode:** warm off-white, teal-green primary, amber "lowest price" accent.
- **Dark mode:** black with a deep emerald gradient glow, slightly see-through cards, mint primary, amber accent.
- Every text/background pair is verified at WCAG AA (4.5:1 contrast) or better.
- Inter font bundled in the app (includes ₹), with fixed-width digits for prices.
- **App icon:** a falling-price line with an amber dot on a green-to-black gradient. Includes an adaptive icon,
  an Android 13 themed icon, legacy PNGs and a 512 px Play Store icon (`branding/`).
  Regenerate with `flutter test tool/generate_icons_test.dart`.

### Tests and tooling
- Unit tests (`test/`): link parsing, host spoofing, pack-size parsing, filters and sorting, rupee formatting,
  URL validation, sample source, admin auth and lock-out, the three scrapers (using fixtures with the real
  response shapes), the product matcher, and malicious or deeply nested input.
- Device smoke test: `flutter test integration_test/live_fetch_test.dart -d <device>`. It shows when a platform
  changes its site.
- Debug builds log each page load and captured response with the `[savr:<platform>]` prefix.

---

## What's left

### Must do before a Play Store release
- [ ] **Release signing key.** Releases are currently signed with the debug key.
- [ ] **Put the project under git.** This folder is not a git repository yet.
- [ ] **Legal and policy review.** On-device scraping may breach platform terms and Google Play's
      "Device and Network Abuse" policy. Plan the backend, or a licensed data vendor (Apify, Actowiz),
      before a public launch.
- [ ] Privacy policy page and Play Data safety form.
- [ ] Build with `--split-per-abi` (a single all-ABI APK is about 48 MB; arm64 alone is 18.8 MB).

### Live price coverage
- [ ] Live fetching for **BB Now, Flipkart Minutes, Amazon Now**. They currently only get deep links.
- [ ] Live fetching for **Grocery** (BigBasket, JioMart, DMart), **Shopping** (Amazon, Flipkart…) and
      **Food** (Swiggy, Zomato). These categories currently fall back to sample data.
- [ ] **Delivery and handling fees.** Search pages don't include them, so live results say "fees not included".
- [ ] Instamart ETA, which isn't captured yet.
- [ ] Instamart product links currently open a search for that product's name, not the exact product page.
- [ ] Check whether the address was really set on each platform. Today Savr trusts the user tapping **Done**.
- [ ] Use the pincode/GPS automatically for on-device mode. Each platform's address is currently set manually.
- [ ] The **dedicated backend** (`/v1/search` and `/v1/health`, contract in README) for when there are users.

### Rides
- [ ] Real distance from pickup and drop. Today you set the distance with a slider; there's no geocoding.
- [ ] Live fares, if a partner API or backend becomes available. They're estimates today.

### Quality and UX
- [ ] Test on iOS. Nothing has been run on iOS yet, and Share → Savr is Android-only for now (iOS needs a share extension).
- [ ] Time the admin passcode unlock on a real device (about 2 s in debug, expected faster in release).
- [ ] Branded splash screen (the default Flutter launch screen is still used).
- [ ] Product images in results (images are blocked in the hidden browser to save data).
- [ ] Price history and price-drop alerts.
- [ ] Crash reporting and basic analytics, privacy-respecting.
- [ ] Add `--strip` (or equivalent) to remove the DWARF debug-info warning in release builds.
- [ ] CI that runs analyze and unit tests on every change.

### Known risks
- **Platforms change their sites often.** Expect occasional breakage. Run the smoke test; the fix is usually a
  changed field in `lib/data/device/scrapers.dart`.
- **`flutter_inappwebview` is on 6.2.0-beta.3**, because the stable 6.1.5 fails to build with the current
  Android Gradle Plugin. Move to stable when it's released.
- A first-ever Instamart visit can get a placeholder response while its bot check runs. Savr reloads once to
  handle this.

---

## Key files
| Area | Path |
|---|---|
| Platforms and links | `lib/core/platforms.dart`, `lib/core/link_parser.dart` |
| Models, filters, matching | `lib/core/models.dart`, `lib/core/matcher.dart` |
| On-device fetching | `lib/data/device/` (`scrapers.dart`, `webview_runner.dart`, `device_source.dart`) |
| Server and sample sources | `lib/data/remote_source.dart`, `lib/data/sample_source.dart`, `lib/data/repository.dart` |
| Ride estimates | `lib/data/ride_estimator.dart` |
| Security | `lib/security/admin_auth.dart`, `lib/data/safe_http.dart`, `android/app/src/main/res/xml/` |
| Theme and brand | `lib/theme/tokens.dart`, `lib/theme/app_theme.dart`, `lib/theme/brand_mark.dart` |
| Screens | `lib/ui/` (compare, results, rides, settings, connect, admin) |
| Tests | `test/`, `integration_test/live_fetch_test.dart`, `tool/generate_icons_test.dart` |
