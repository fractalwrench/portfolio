---
title: "Playing APK Golf"
subtitle: "How low can an Android APK's file size go?"
date: 2017-09-30T16:07:19+01:00
---

Have you ever been accused by your colleagues of premature optimisation?

I have, so decided to take the argument to its logical conclusion - by making the smallest possible APK that will install on an Android device.

### Setup
Nothing ground-breaking here, we're just going to use the defaults supplied to us when creating a new Android app. We'll be using the following setup:

- `minSdkVersion` 15
- AppCompat/Support Library
- Empty activity + layout created by default
- No Kotlin/C++ support

We'll also use the following tools:

- Android Studio 3.0.0 Beta 6
- `stat -f%z $filename` (finds the size of a file in bytes)
- HexFiend for editing binary files
- Bash scripts
- A physical Nexus 5x running Oreo
- Zipalign for manually aligning APK archives
- ApkSigner for signing APKs manually

### User Requirements
Our user is entertained easily, and will be happy if we can just print "Hello World" onto the screen.

### Measuring a baseline
The boilerplate for our app has been generated successfully, so let's get our app running and see how large the generated APK is. We'll sign our APK signed with v1 (Jar Signature) and v2 (Full APK Signature), make sure it runs on the physical device, then begin analysing it.

![Default App Screenshot](/img/apkgolf/default-app.png)

### 1.5 Mb
We've created a simple Android App, which prints "Hello World" on screen to the user. However, this would be a very short blog post if we considered this Mission Accomplished. Although the APK weighs in at a respectable 1.5Mb on disk, it's nowhere near as complicated as hundred of megabytes Android apps such as Facebook and Twitter. Surely we can reduce the APK's size, the question is how far?

Let's start with a little visual exploration.

### Visual Contents
- One `Activity` which extends an `AppCompatActivity`, simply sets its content view as a layout file in onCreate.
- One layout file which has `ConstraintLayout` as its root view.
- Values files containing 3 colours, a string resource of the app name, and the app's theme which extends an `AppCompat` theme.
- One `AndroidManifest` which specifies an intent filter that allows the `MainActivity` to be invoked via Launchers.
- The AppCompat and ConstraintLayout support libraries.
- A square, round, and foreground PNG used for the launcher icon, provided for different screen densities under the mipmap directory. There are 15 images overall and 2 XML files under `mipmap-anydpi-v26`.
- Unit Tests, Instrumentation tests, and various build/metadata files, which can be ignored as they won't be included in the APK.

### APK Analyser
It feels like the easiest initial target will be reducing our dependency on External Libraries, which often have to provide complex functionality that supports many different API Levels and use-cases. All we want to do is say Hello World.

Let's back up that claim with some evidence, using a tool recently introduced in Android Studio 2.2 - the APK Analyser.

![Apk Analyser Screenshot](/img/apkgolf/apk-analyser-1.png)

This shows us the internals of the generated APK, and can be accessed by double-clicking on an APK in the project panel, or by selecting Build > Analyse APK.

### APK Structure

- classes.dex: 74%
- res: 20%
- resources.arsc: 4%
- META-INF: 2%
- AndroidManifest.xml: <1%

<!-- TODO briefly describe what these actually do for the Android novice!  -->


`classes.dex` is the biggest culprit and therefore our first target, taking up over 73% of the APK size. This contains all our compiled Java classes which have been run through a Dexer. Although we only defined one Activity in our app, this Dex file has a massive 1,622 classes which define 12,622 methods, and references 17,381 methods in total. That's already more than a quarter of the infamous 64k Dex limit!

Our res directory looked fairly simple in the IDE, but that's certainly not the case in our generated APK. We have a vast number of layout files, drawables, and animations. These weigh in at around 20% of the APK size, so present the second target. Our values files have been combined into `resources.arsc`, which performs some clever mapping of drawables (TODO need to read up on that a bit more and include something)

![Apk Analyser Screenshot](/img/apkgolf/apk-analyser-2.png)

Other items include a `META-INF` folder which contains `CERT.SF`, `MANIFEST.MF`, and `CERT.RSA` files, all of which are related to the APK signature we just generated.

![Manifest.mf](/img/apkgolf/manifest-mf.png)

And of course, we have the AndroidManifest, which looks much the same as it does in the IDE, with the exception of the resource IDs, which now point to a location within the resources.arsc file.

### Low-hanging Fruit

First off, there's one obvious trick that we haven't tried - enabling minification in our app's build.gradle file. Let's give that a go and observe the results.

```
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
}
```


proguard-rules.pro (due to an apparent bug in studio, we need to specify the activity should be kept)

```
-keep class com.fractalwrench.** { *; }
```

The following commands enable Proguard, which detects unused code out of our application before it is compiled, and also obfuscates class and method names. `shrinkResources` will remove any files from the Android res directory which are not directly referenced - another thing our example APK suffers from. If you are using reflection in your application to access resources, you may want to be careful with this flag, as it will strip out these resources anyway and you will encounter exceptions at runtime.

Let's generate a signed APK as before and see what's changed.

### 786 Kb (50% reduction)
We're now down to 786Kb, reducing our APK size by a half. This has had no noticeable effect on our application, as it's simply stripped out unused drawable/layout resources, and removed any support library classes which weren't referenced from the output JAR. As an added bonus, Proguard will obfuscate the class names in our dex file, making it harder to reverse-engineer.

If you haven't already enabled `minifyEnabled` and `shrinkResources` in your application, this is the single most important thing you should take away from this post. In a production application this will easily save you several megabytes, and only takes a couple of hours of configuration and testing.

### Next target
The effect of Proguard can clearly be seen in the APK Analyser. Our `classes.dex` now takes up 57% of the APK, and the res directory has increased its proportion to 28%. Our APK now 661 classes with 5150 methods, and references 7657 in total.

Nearly 5,800 of those methods are taken up by the `android.support` package. Where we're going, backwards compatibility won't be an issue, and as a result this low-hanging fruit can't be ignored, especially as removing the support library will drastically reduce the number of resources we're pulling into the res directory.

One important caveat is that I certainly can't recommend taking this approach with any complex production app that needs to support older Android devices. The support library is just too useful, and the only time you'd not want to use it is when size is an issue, such as writing an SDK.

### Bye bye compatibility
To make this change we perform the following:

- Remove the dependencies block from our `build.gradle` entirely

```
dependencies {
    implementation 'com.android.support:appcompat-v7:26.1.0'
    implementation 'com.android.support.constraint:constraint-layout:1.0.2'
    testCompile 'junit:junit:4.12'
}
```

- Update the MainActivity to extend `android.app.Activity` rather than `AppCompatActivity`

```
public class MainActivity extends Activity
```

- Change to a Batman layout (no parents) by getting rid of `ConstraintLayout`, and adjusting the `TextView` to fill the screen and display text in the centre

```
<?xml version="1.0" encoding="utf-8"?>
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:text="Hello World!" />
```

- Delete `styles.xml` and remove the `android:theme` attribute from the ``<application>`` element in the `AndroidManifest`, as that relies on AppCompat.
- Delete `colors.xml`
- Sync gradle files

Let's generate an APK as we did before and see what's changed.

### 108 Kb bytes (87% reduction)
Holy cow, we just achieved nearly a 10x reduction in file size, starting from 786Kb, down to 108Kb. The only discernible change in our primitive application is that the Toolbar appears with a different color, as it's now using the OS default theme rather than one we supplied.

![No Support Library App Screenshot](/img/apkgolf/no-support-lib-app.png)

 What do the APK internals look like now?

The res directory takes up nearly 95% of the APK size, as we'd forgotten about all those launcher icons. If these icons were provided by our designer, then we could try converting them to WebP, which is a more efficient file format supported on API 15 and above. Fortunately, Google has already thought of this for our icons, and the images themselves have already been optimised. In an ordinary app, you could also try running [ImageOptim](https://imageoptim.com/mac) to optimise PNGs, and strip any unnnecessary metadata such as EXIF.

### Bad Citizenry
We don't *really* need to support multiple versions of a launch icon, as that's simply more of a courtesy to allow launchers to display similarly styled icons. In fact, we could be a really bad citizen, by just supplying a 1-pixel black dot, and adding it to the unqualified `res/drawable` folder.

To do this, we'll need to delete `android:roundIcon="@mipmap/ic_launcher_round"` from our manifest, and get rid of the unused mipmaps. We'll replace them with our 1x1 image that was made in Gimp and optimised with ImageOptim down to 67 bytes.

### 6808 bytes (94% reduction)
It's not surprising that we've got nearly a 95% reduction, as the res directory previously took up all that space and we've pretty much obliterated all our resources.

`META-INF.mf` now takes up 44% of our APK size, `classes.dex` takes up 25%, and the manifest takes up 15%. Ordinarily we'd aim for the biggest target, but things will get tricky there, so let's leave it for last.

<!-- TODO explain APK signing -->


### Low-level hanging fruit
Let's optimise `resources.arsc` first. It currently references:

- 1 layout file
- 1 String used to display the app name
- 1 launcher icon drawable


#### Layout file (6262 bytes, 9% reduction)
Let's try removing the layout file, and invoking the `TextView` directly. This tradeoff will reduce `resources.arsc` and res directory, but will increase the size of classes.dex, as we're now referencing `TextView` methods such as `setText` from the Android framework, rather than relying on XML layout inflation doing that for us.

```
TextView textView = new TextView(this);
textView.setText("Hello World!");
setContentView(textView);
```

Looks like we're down to 5710 bytes.

#### App Name (6034 bytes, 4% reduction)
Let's delete `res/values/strings.xml`, and replace `android:label` in the AndroidManifest with "A". This may seem like a small change, but will get rid of an entry in `resources.arsc`, remove a file from the res directory, and reduce the number of characters in the manifest.

#### Hello beautiful launcher icon (5300 bytes, 13% reduction)
But I thought we'd optimised the image as much as possible already?

That's true. I'm not aware of any way of getting a PNG below 67 bytes. And `resources.arsc` takes up a couple of hundred more bytes, as it needs to fulfil a certain file structure if we're going to reference an image from within our app.

<!-- TODO detail the resources.arsc format here!!! -->

https://android.googlesource.com/platform/frameworks/native/+/jb-dev/libs/utils/README


""""
During compilation, the aapt tool gathers application resources and
generates a resources.arsc file. Each resource name is assigned an
integer ID 0xppttiii (translated to a symbolic name via R.java), where
 * pp: corresponds to the package namespace (details below).
 * tt: corresponds to the resource type (string, int, etc). Every
       resource of the same type within the same package has the same
       tt value, but depending on available types, the actual numerical
       value may be different between packages.
 * iiii: sequential number, assigned in the order resources are found.


 The pp part of a resource ID defines a namespace. Android currently
 defines two namespaces:
  * 0x01: system resources (pre-installed in framework-res.apk)
  * 0x7f: application resources (bundled in the application .apk)
 ResourceTypes.cpp supports package IDs between 0x01 and 0x7f
 (inclusive); values outside this range are invalid.
""""

So what happens if we don't reference an image from our app, and rely on something that the Android Framework provides instead, using the 0x01 namespace? Let's update our manifest icon attribute to point at a framework resource, and delete our entire res directory.

![System app icon Screenshot](/img/apkgolf/system-app-icon.png)

```
android:icon="@android:drawable/btn_star"
```

#### Don't trust system resources
Our app now uses a single star for its launch icon, which is ideal, as that's exactly the review score we'd get if Google Play didn't fail our submission for publication.

We've got rid of our resources directly, and `resources.arsc` is no longer generated as we're not bundling any resources with our APK. That just leaves us with `classes.dex`, and `AndroidManifest.xml`, both of which take up around half of the space.

Beware: this will fail Google Play validation, and is a terrible idea for a production application. Considering that certain manufacturers have been known to [redefine system resources]((https://www.reddit.com/r/androiddev/comments/71fpru/android_color_resources_not_safe/)) such as `@android/color:white`, these framework resources can't be relied on anything apart from for hacks.

#### Manifest (5252 bytes, 1% reduction)
We haven't touched the manifest yet, so there are some easy pickings here, as it currently takes up around 20% of the space. There are a few optimisations here, namely removing:

```
android:allowBackup="true"
android:supportsRtl="true"
```

#### Proguard hack (4984 bytes, 5% reduction)
Our proguard hack earlier is keeping a few classes lying around which we don't need, such as BuildConfig and R. Let's refine that proguard rule and get rid of them.

![classes.dex](/img/apkgolf/classes-dex.png)

Our dex file now defines 1 class and 2 methods, and references 7 in total when framework methods are considered.

```
-keep class com.fractalwrench.MainActivity { *; }
```

#### Obfuscation (4936 bytes, 1% reduction)
Let's give our classes an obfuscated name. Proguard would do this for non-Activity files, but the manifest needs to know the name of the class to launch, so this isn't obfuscated by default.

`MainActivity -> c.java`
package name renamed to c.c (minimum of two required) (also build.gradle)

We definitely won't be able to submit our APK to Google Play now, but our hypothetical user doesn't care.

### META-INF (3307 bytes, 33% reduction)
`META-INF.mf` contains the v1 signature for the APK. Let's try generating with only the v2 signature instead, as this offers better protection as it signs the full APK, rather than just the JAR. It should also remove the `META-INF.mf`, because in v2 the signing is located at the end of the ZIP file, and isn't visible in the APK analyser tool.

To do this, we'll simply uncheck the v1 signature checkbox in the Android Studio UI, when generating a signed APK. Only signing with v1 produces an APK of 3511 bytes, whereas only signing with v2 produces an APK of 3307 bytes. In v2 the `CERT.RSA` and `CERT.SF` have disappeared. We have a winner!

APK signing V2:
https://source.android.com/security/apksigning/v2


## Where we're going, we won't need IDEs
It's time to edit our APK by hand. Creating an APK can be done in several steps, which are outlined below:

```
# 1. Creates an unsigned apk (zip file)
./gradlew assembleRelease

# 2. Run zipalign (technically optional)
$ANDROID_HOME/build-tools/26.0.1/zipalign -v -p 4 app-release-unsigned.apk app-release-aligned.apk

# 3. Run apksigner with v2 signature only, enter password
$ANDROID_HOME/build-tools/26.0.1/apksigner sign --v1-signing-enabled false --ks $HOME/fake.jks --out signed-release.apk app-release-unsigned.apk

# 4. Verify signature
$ANDROID_HOME/build-tools/26.0.1/apksigner verify signed-release.apk
```

Our unsigned and unaligned APK weighs in at 1902, which indicates that we're using at least 1Kb for the signing/aligning features.

<!-- TODO make an image/graphic? -->

TODO sources:

https://developer.android.com/studio/command-line/zipalign.html
https://developer.android.com/studio/command-line/apksigner.html
https://developer.android.com/studio/publish/app-signing.html#sign-manually


### Editing unzipped APK
After running `gradlew assembleRelease`, let's unzip the archive, then archive and sign the APK in the same way. This will prove we can manually edit the APK and run it on a real device.

```
unzip app-release-unsigned.apk -d app

# do any edits

zip -r app app.zip

# Sign as before
```

### File-size discrepancy (2764 bytes, 17% reduction)
Weird! Unzipping the unaligned APK and signing it manually appears to have knocked off 543 bytes by removing `META-INF/MANIFEST.MF`. I'm not entirely sure why this happens when done from the command line, so if anybody knows why, please get in touch!

### resources.arsc (2608 bytes, 6% reduction)
We are left with 3 files that are included into the signed APK. We can get rid of one, `resources.arsc`, because it's empty since we're not defining any resources.

That leaves us with the manifest and the `classes.dex` file, which each take up roughly half of the application size.

### ZEO (Zip engine optimisation) (2599 bytes, 0.5% reduction)
Let's change the application label to 'c', rather than 'A', and generate a signed APK. WTF? Why have we lost a byte here? both 'c' and 'A' are unicode characters which take up the same amount of space.

Oh wait, 'c' already appears in the manifest, within the activity name. The compression algorithm used to create an archive will reduce the file size further if some characters are more frequent than others. Let's exploit this with the following changes:

```
compileSdkVersion 26
    buildToolsVersion "26.0.1"
    defaultConfig {
        applicationId "c.c"
        minSdkVersion 26
        targetSdkVersion 26
        versionCode 26
        versionName "26"
    }
```

```
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="c.c">

    <application
        android:icon="@android:drawable/btn_star"
        android:label="c"
        >
        <activity android:name="c.c.c">
```

We can revisit this later on - for now we've reclaimed 9 bytes.

### Abandoning user requirements (2462 bytes, 5% reduction)
To hit the truly minimal APK, let's git rid of those pesky user requirements. Originally we said we were going to have an app with a launcher icon that when clicked would display "Hello World" on screen. Anyone who's made it this far is probably going to know how to use ADB, so let's remove the launch icon requirement. Here's our new manifest:

```
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="c.c">

    <application>
        <activity
            android:name="c"
            android:exported="true" />
    </application>
</manifest>
```

To launch the activity, we'll run:

```
adb shell am start -a android.intent.action.MAIN -n c.c/.c
```

### Where we're going, we don't need classes (2179 bytes, 12% reduction)
Let's take this to the logical conclusion, and get rid of our activity, replacing it with a custom `Application` class. This should still generate a valid, albeit useless APK. Our `classes.dex` file size will be reduced, as we are no longer referencing any TextView, Bundle, or Activity methods - only the Application constructor. Our manifest now looks like this:

```
package c.c;

import android.app.Application;

public class c extends Application {
}
```

```
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="c.c">
    <application android:name=".c" />
</manifest>
```
From now on, we can verify that our app has actually been installed by adb reporting success or failure. Or, we can have a look in the Settings app.

![Apk installation proof](/img/apkgolf/package-installation-proof.png)

### Dex Optimisation (1961 bytes, 10% reduction)

Overview of format:
https://source.android.com/devices/tech/dalvik/dex-format

I did a bunch of research into the Dex file format for this. But to cut a long story short, if your app doesn't launch an activity or perform a useful function, the only requirement for an APK to be installed is for the file to exist.

Therefore, we're going to open up the file in HexFiend, delete its contents, then save it as a zero-byte file, gaining us a 10% reduction.

### Do the stupid things (1777 bytes, 9% reduction)
After several hours researching how a binary XML manifest is encoded, I took the high-tech approach of systematically replacing bytes with 0, and seeing whether the APK installed.

Fun fact, the following passes validation on a Nexus 5X. Warning: if you do this in production, it will cause the Google Engineer responsible for maintaining the Android framework class `BinaryXMLParser.java` to scream very loudly into a pillow.

![Non-essential manifest parts](/img/apkgolf/non-essential-manifest-parts.png)

This doesn't change the bytes in the file, but if you remember our zip compression hack from earlier, this will reduce the overall size of the APK. It will also make it a lot easier to see what the important parts of the manifest are.

This also leaves us with a nice view of how the manifest file is structured using HexFiend, as we can hide the null bytes.

![Minified AndroidManifest](/img/apkgolf/minified-android-manifest.png)

### Done? (1757 bytes, 1% reduction)
Let's inspect the final APK.

![Name in signed APK](/img/apkgolf/name-in-signed-apk.png)

Huh, it seems like after all this time, I left my name in the APK. That will be at least a few bytes we can recover if we create another keystore. Let's exploit the zip compression hack too, by calling everything c.

![Keystore ccccccc](/img/apkgolf/cccccc.png)

### Stage 5: acceptance
I'm fairly happy with 1757 bytes as the smallest APK, even though I'm sure someone on the internet will have another low-level trick to beat me. If you do have a further optimisation, please get in touch!

In summary, there is such a thing as too much optimisation, and I should really have given up a couple of afternoons earlier and studied some Kotlin instead. But there you have it ladies and gentlemen. The world's smallest APK...so far.



There are various other things we could probably do to shave off a few more bytes, such as:

- Brute-force generation of keystores to improve compression
- Taking a less naive approach to AndroidManifest.xml and reducing bytes there
- Further Zip Compression hacks (count characters using wc, optimise on the most common char)

But this was only meant to take an afternoon to complete, so I'll leave that as an exercise for the listener.










Looking at the manifest in the unzipped APK, we can see that it's in a weird binary format rather than XML. This will make optimization a bit harder, so let's try and dig into what it's doing.
https://stackoverflow.com/questions/2097813/
https://justanapplication.wordpress.com/category/android/android-binary-xml/
https://github.com/clearthesky/apk-parser/blob/master/src/main/java/net/dongliu/apk/parser/parser/BinaryXmlParser.java


No docs I could find :'(
Mutating string values works ok, so there's probably no checksum enforced



<!-- TODO hexfiend pic  -->

Our manifest from the unsigned APK is in a binary format which doesn't appear to be documented. There appear to be a few interesting things that are revealed by its structure. The first 4 bytes signify a version number (38), and the next 2 bytes show the size of the file (660).

Let's try deleting a byte by setting the targetSdkVersion to 1, and updating the file size header to 659. Unfortunately this doesn't pass verification, so it looks like there's some extra complexity here which we'll have to revisit.

The next step is to substitute every item with dummy characters without changing the file size, to see if there's some sort of checksum in place. This will show which attributes cannot be removed. Surprisingly, it looks like we can substitute quite a few of the keys with no ill-effect.

Values that can't be changed:

```
manifest
package
```




"""
String has length in the first 2 bytes, repeated twice! (e.g. 1313minSdkVersion)

```
private static String getLengthPrefixedUtf8EncodedString(ByteBuffer encoded)
               throws XmlParserException {
           // If the length (in bytes) is 0x7f or lower, it is stored as a single uint8. Otherwise,
           // it is stored as a big-endian uint16 with highest bit set. Thus, the range of
           // supported values is 0 to 0x7fff inclusive.
```
"""




Writeup notes:
- Host repo with smallest APK ever
- Crazy hacks the reader can think of? Get in touch.
- Removing everything might not be feasible depending on your needs in Android, as the Support Lib has awesome functionality and makes it easy to develop. However, it's good to know how to do it.
- Perseverance (even when you think you've optimised something, you can probably go further)
- Took about 5 minutes to get 99% of the gains, and several Sunday afternoons to realise the rest. You have to decide whether it's worth the engineering effort.
- MEASURE EVERYTHING. You WILL be surprised by what takes up the most space, or takes the longest time to execute in your application.
- WTFs or things that don't make sense are often a clue
