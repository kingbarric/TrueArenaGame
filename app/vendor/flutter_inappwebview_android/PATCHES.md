# Local compatibility patch

Source: the unmodified pub.dev release `flutter_inappwebview_android` 1.1.3, with its upstream license retained.

The upstream example and package test directories are omitted from this runtime-only copy.

Only functional change: replace the two `getDefaultProguardFile('proguard-android.txt')` calls in `android/build.gradle` with `proguard-android-optimize.txt`. PlayHuud uses Android Gradle Plugin 9.1, which rejects the old default at configuration time, including debug builds.

The upstream project uses the optimized default in its development branch: https://github.com/pichillilorenzo/flutter_inappwebview/blob/master/flutter_inappwebview_android/android/build.gradle
Upstream tracking issue: https://github.com/pichillilorenzo/flutter_inappwebview/issues/2765

`app/pubspec.yaml` points to this stable local copy to avoid silently patching a developer's shared Pub cache or moving every WebView platform to a prerelease. Remove the override and vendor directory once a compatible stable upstream release is adopted. No Dart, Android Java, runtime permission or WebView API changes are made.
