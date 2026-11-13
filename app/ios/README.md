# Building the Sirena HR iPhone app

Everything in the project is ready. What's left can only be done on a **Mac**, because Apple's build
tools run nowhere else, and it needs an **Apple Developer Program** account ($99 a year) to put the
app on other people's phones.

## What is already set up

| | |
|---|---|
| App name on the phone | **Sirena HR** |
| App identifier | `com.sirenatech.hr` |
| Lowest iPhone version | iOS 15 |
| Location permission | Asked with: "Used to check you in when you're at the office or on the office Wi-Fi." |
| Office Wi-Fi detection | `Runner/Runner.entitlements` asks for *Access WiFi Information* |
| Notifications while closed | Background task `sirena-check-notifications`, allowed in `Info.plist` and registered in `AppDelegate.swift` |
| Unused permissions | Stripped in `Podfile`, so review doesn't ask about contacts, photos and the rest |
| App icon | The Sirena eyes on the app's dark background, made by `tool/make-icons.py` |
| Support contact | `dev@sirenatech.com`, shown on the sign-in screen and under **Me → Help** |
| Server certificate | Checked by the app itself (`lib/core/pinning_io.dart`), which works on iPhone exactly as on Android |

## On the Mac, once

1. **Install the tools**
   ```bash
   xcode-select --install          # command line tools
   sudo gem install cocoapods      # or: brew install cocoapods
   ```
   Install **Xcode** from the App Store, open it once, and accept the licence.
   Install Flutter: https://docs.flutter.dev/get-started/install/macos

2. **Get the code**
   ```bash
   git clone https://github.com/hilokeshrm/sirena-hr.git
   cd sirena-hr/app
   flutter pub get
   ```

3. **Apple Developer account**
   - Join at https://developer.apple.com/programs (a company account needs a D-U-N-S number, which takes a few days; a personal one is instant).
   - In the developer site under **Identifiers**, register `com.sirenatech.hr` and tick **Access WiFi Information**.

4. **Sign the app in Xcode**
   ```bash
   open ios/Runner.xcworkspace
   ```
   Pick the **Runner** target → **Signing & Capabilities** → choose your Team. Leave "Automatically manage signing" on.
   Check these are listed (add with "+ Capability" if not):
   - **Access WiFi Information**
   - **Background Modes** with *Background fetch* and *Background processing* ticked
   - **Push Notifications** is **not** needed; notifications are made on the phone itself.

## Building

The app needs to know the server address and its certificate fingerprint.

```bash
cd sirena-hr/app
flutter build ipa --release \
  --dart-define=API_BASE=https://106.51.70.71:7777/api \
  --dart-define=SERVER_CERT_SHA256=46DF38B3F495D7FBF04042CC80ECE4DA58A7AE2C61CAC659A1E475BB92499306
```

The fingerprint comes from the server, so re-read it if the certificate is ever replaced:

```bash
ssh dgx "openssl x509 -in ~/sirena/certs/server.pem -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':'"
```

To try it on a phone plugged into the Mac, use `flutter run --release` with the same two `--dart-define`
lines. Nothing else about the build differs from Android.

## Getting it onto people's phones

- **TestFlight (recommended).** Upload the `.ipa` from `build/ios/ipa` with **Transporter** (free, App Store)
  or `xcrun altool`. Add staff as testers by email; they install Apple's TestFlight app and get the app
  there. No App Store review for internal testers (up to 100), and builds last 90 days.
- **App Store** is not suitable: this app is only useful to Sirena staff, and Apple rejects apps that the
  public can't use.
- **Apple Business Manager** (Custom Apps) distributes privately and permanently, but takes more setup.

When filling in App Store Connect, use **dev@sirenatech.com** as the support email, the same address the
app shows people.

## Worth knowing

- **Notifications while the app is closed** are less reliable on iPhone than on Android. Apple decides when
  a background check may run, based on how often the person uses the app, and it never runs after they
  force-quit the app. In the app itself they always appear.
- **Office Wi-Fi detection** needs the person to allow location *and* precise location. Without it, the app
  falls back to the office internet address and GPS, same as the website.
- **The certificate warning** that browsers show doesn't appear in the app: it checks the fingerprint
  instead, which is stricter.
- **If the server address changes**, rebuild with the new `API_BASE` and fingerprint. Nothing else changes.
