# PHYSIOPAÑO Android app

The Flutter app pairs with the [ESP32 wristband](../../Firmware/Final_Code/) over Bluetooth. It compares resting sensor readings with the wearer's own baseline and offers a short check-in after a sustained change. The wearer can preview what they would share when requesting support.

## Run with a test Firebase project

1. Set up Flutter, the Android SDK, the Firebase CLI, and the FlutterFire CLI.
2. Register an Android app in a separate test Firebase project. Use the application ID in [build.gradle.kts](android/app/build.gradle.kts).
3. Enable email/password sign-in and set up Firestore in the test project. Use the [repository rules](../../firestore.rules) for testing the referral workflow.
4. From this directory, run the commands below. Choose your test project and the Android platform when prompted. If FlutterFire does not put google-services.json in android/app, download it from your test Firebase project and place it there.

~~~sh
flutter pub get
flutterfire configure --platforms=android
flutter run
~~~

With a test account, open **Settings → Your usual → Load demo history**. On Home, open the check-in from the synthetic baseline change card and follow the support route.
