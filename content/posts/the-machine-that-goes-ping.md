---
title: "The machine that goes PING"
subtitle: "Detecting build completion with a custom Gradle Plugin"
date: 2018-01-15T17:00:00+01:00
---

[Gradle](https://gradle.org/) is an 800lb magical gorilla that can be incredibly intimidating at first glance.

We're going to harness some of Gradle's superpowers by writing a plugin that alerts us whenever a build completes.

Essentially, this guide will teach you how to turn a shiny MacBook Pro into a [machine that goes PING](https://youtu.be/NcHdF1eHhgc?t=160).

## What is Gradle

[Gradle](https://docs.gradle.org/4.4.1/userguide/userguide.html) is simply a tool that builds projects from source code, and provides a very flexible API for manipulating the build along the way. Gradle is the default build tool for Android projects, although alternatives like [Bazel](https://bazel.build/) and [Buck](https://buckbuild.com/) exist.

The key thing to remember about Gradle is that a project is formed of multiple tasks, all of which can have dependencies on one another.

Typically when we're developing an Android App, we'll perform a few different actions in the course of a day. We will want to build the project to ensure that our changes don't have compilation errors. We will want to run the project on an emulator to ensure that the app doesn't crash at runtime. If we're being good, we'll want to run tests on a device.

![Gradle Tasks Panel in Android Studio](/img/pingmachine/gradle_panel_tasks.PNG)

### Tasks

All of these actions correspond to [Gradle tasks](https://docs.gradle.org/4.4.1/userguide/tutorial_using_tasks.html#sec:projects_and_tasks). For example, building a simple module via Android Studio would ultimately invoke the `./gradlew build` task. If we want to run tests on our device, we could run the `connectedCheck` task, whose task dependency chain would compile all our Kotlin/Java code, package it into an APK, and run our tests via [adb](https://developer.android.com/studio/command-line/adb.html).

If you're confused about how this translates into a very flexible API, we're missing two pieces of very crucial information. One, Gradle allows you to lookup any task in the project using your build scripts. Two, it's possible to add our own custom tasks, and make them execute before or after certain tasks.

[Add dependencies to tasks](https://docs.gradle.org/4.4.1/userguide/more_about_tasks.html)

This is an incredibly powerful concept that lets us achieve things that would otherwise appear magical.

https://developer.android.com/studio/build/index.html

### What is a Gradle Plugin?

Surprise, you've been using a [Gradle Plugin](https://developer.android.com/studio/releases/gradle-plugin.html) in your project whether you knew it or not, in the form of the Android Gradle Plugin! Gradle isn't an Android Specific build tool, so the AGP adds Android-specific build tasks, such as Lint Checks, to each module that has `apply plugin 'com.android.application'` in its `build.gradle`.

A plugin is essentially just an easy way of modularising our custom tasks and sharing them with other developers. So let's write our own!

## Writing our own plugin
We'll start off by packaging our plugin in the `buildSrc` folder, although it would be possible to use a [standalone project](https://docs.gradle.org/4.4.1/userguide/custom_plugins.html#sec:packaging_a_plugin).

### Setting up the buildSrc folder

We'll start by creating a default Android project in Android Studio, and adding a folder at `<projectDir>/buildSrc/src/main/groovy`. This does mean that we can't use it outside the current project, so there will be some additional work when we publish the plugin to an external repository.

Once the folder has been created, we'll create `PingPlugin.groovy` and add the following contents:

```
import org.gradle.api.Plugin
import org.gradle.api.Project

class PingPlugin implements Plugin<Project> {
    void apply(Project project) {
        println("I'm a plugin!")
    }
}
```

Finally, we'll add `apply plugin: PingPlugin` at the top of our app module's `build.gradle`, then run `./gradlew assemble`. The `apply` method will be invoked with an instance of the `Project` whenever we run a build, so in this case the Gradle Console output should contain "I'm a plugin".

### Adding a custom task

It's time to add some crazy Gradle magic by adding a custom task. We'll start off by accessing all the existing tasks in the project, via `project.tasks`.

Next, we need to find the task that we're interested in, which in our case is `assemble`. If we weren't sure which task to use, we could run `./gradlew tasks`, which lists all tasks in the project, or consult the [AGP docs](https://google.github.io/android-gradle-dsl/current/). Let's lookup the assemble task using the following method:

```
Task assembleTask = project.tasks.findByName("assemble")
```

Finally, let's create our own task, and make it execute once the rest of the `assemble` task has completed:

```
assembleTask.doLast {
    project.logger.lifecycle("I'm a plugin!")
}
```

All together, this should look like the following:

```

class PingPlugin implements Plugin<Project> {
    void apply(Project project) {

      `Task assembleTask = project.tasks.findByName("assemble")`
        assembleTask.doLast {
            project.logger.lifecycle("I'm a plugin!")
        }

    }
}
```

And produce the following output on a successful build of our Android App:

```
:app:assemble
I'm a plugin!
```

### Make it ping

Our next step is to make the application play a sound, rather than log a message. To do this, we'll download a suitable [PING](https://freesound.org/people/thomasevd/sounds/125374/) sound that is under the CC Attribution License, and add it to our resources folder, at `buildSrc/src/main/resources/audio.wav`.

We can access this resource via the [`ClassLoader`](https://docs.oracle.com/javase/7/docs/api/java/lang/ClassLoader.html), and obtain an `InputStream`. Let's replace the code in our `doLast` task:

```
InputStream is = getClass().classLoader.getResourceAsStream("audio.wav")

if (is == null) {
    project.logger.error("Could not find Audio File")
}
new AudioPlayer().play(is)
```

The final step is to create `AudioPlayer.java` in the `src/main/groovy` directory. This utilises the `javax.sound` API to play our audio file, and blocks until the end of the clip is reached.

```
class AudioPlayer implements LineListener {

    private volatile boolean finished = false;

    synchronized void play(InputStream inputStream) throws InterruptedException {
        // convert the inputstream into an audioinputstream
        try (BufferedInputStream bis = new BufferedInputStream(inputStream);
             Clip clip = AudioSystem.getClip();
             AudioInputStream audioInputStream = AudioSystem.getAudioInputStream(bis)) {

            clip.open(audioInputStream);
            clip.setFramePosition(0); // start at beginning of track
            clip.addLineListener(this);
            clip.start();
            waitForPlaybackCompletion(); // block until at end of track
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public synchronized void update(LineEvent event) {
        LineEvent.Type type = event.getType();
        if (type == LineEvent.Type.CLOSE || type == LineEvent.Type.STOP) {
            finished = true;
            notifyAll();
        }
    }

    private synchronized void waitForPlaybackCompletion() throws InterruptedException {
        while (!finished) {
            wait();
        }
    }

}
```

If we assemble the app now, we should hear a ping at the end of the build!

### Build Variants

With great power comes great responsibility. You may have noticed that this doesn't work when running the app in debug mode from Android Studio, because this action doesn't execute the `assemble` task.

The reason for this is that Gradle has [3 build phases](https://docs.gradle.org/current/userguide/build_lifecycle.html#sec:build_phases): initialisation, configuration, and execution.

The Android Gradle Plugin adds its own tasks before the execution phase, most notably the `assembleDebug` and `assembleRelease` tasks.

To fix our oversight, we can ask Gradle to iterate through all the build variants in our project after these tasks have been added. For each variant, we can gain access to the assemble task for each output, and add on our own task to play the audio clip.

```
class PingPlugin implements Plugin<Project> {
    void apply(Project project) {
        project.afterEvaluate {
            project.android.applicationVariants.all { variant ->
                variant.outputs.each { output ->
                    playAudioOnBuildCompletion(output)
                }
            }
        }
    }

    private void playAudioOnBuildCompletion(output) {
        output.assemble.doLast {
            InputStream is = getClass().classLoader.getResourceAsStream("audio.wav")

            if (is == null) {
                project.logger.error("Could not find Audio File")
            }
            new AudioPlayer().play(is)
        }
    }
}
```

A minor bug with this naïve approach is that the ping will occur every time a variant is assembled when we're building multiple outputs. As with all bugs, this could be considered a feature if you use APK splits, product flavors, and intensely dislike all your coworkers.

 We can fix that at a later time - for now let's expose an extension that allows developers to control the behaviour of our plugin.

### Plugin Extensions

You're already [familiar with extensions](https://google.github.io/android-gradle-dsl/current/com.android.build.gradle.AppExtension.html), whether you know it or not. For example, most of us have set the `versionName` for our app before:

```
android {
    defaultConfig {
        versionName "3.5.7"
    }
}
```

The `android` extension is supplied as part of the AGP, and allows us to specify various build parameters without needing to hack on Gradle tasks ourselves.

#### Example

Creating our own extension should be [very straightforward](https://docs.gradle.org/current/userguide/custom_plugins.html#sec:getting_input_from_the_build
). Let's start by downloading an extra audio file, name it `"foo.wav"`, and place it in the resources folder.


At the top of `PingPlugin.groovy`, we can define our extension object:

```
class PingPluginExtension {
    String audioFile = "audio.wav" // use default value
}
```

Within the `apply` method, we'll create the extension in our project:

```
project.extensions.create("pingPlugin", PingPluginExtension)
```

We can then update our play method to access the `audioFile` field on the plugin:

```
InputStream is = getClass().classLoader.getResourceAsStream(project.pingPlugin.audioFile)

```

And finally, we could configure the plugin from our app's build script:

```
pingPlugin {
    audioFile "foo.wav"
}
```

For now, we'll skip adding an extension, and focus on publishing our plugin as a JAR, so that anybody else in the world can use it in their project.

### Publishing the final product

#### Standalone Project

We've outgrown the `buildSrc` folder. It's time to create a [standalone Android Studio project](
https://docs.gradle.org/current/userguide/custom_plugins.html#sec:custom_plugins_standalone_project) for the plugin.

We'll start by deleting all the auto-generated Android code and app module, which we won't be needing. We will then copy our `src/main` directory across to the root of the new project.




A couple of additional steps are required in order to build a standalone project. First, we need to add a few dependencies that were previously implicit:

```
plugins {
    id 'groovy'
}

dependencies {
    compile gradleApi()
    compile localGroovy()
    compile 'com.android.tools.build:gradle:3.0.1'
}
```

Secondly, we need to tell Gradle where the plugin has been implemented. This is achieved by adding a properties file that contains the canonical class name. For our project, we would need to create a file called `META-INF/gradle-plugins/com.fractalwrench.pingmachine.properties`, and point at the following class:

```
implementation-class=com.fractalwrench.pingmachine.PingPlugin
```


#### Automated publishing

We're going to publish to the Gradle Plugin Portal, so will need to sign up for an account, and setup an API key as [detailed here](https://plugins.gradle.org/docs/submit). Fortunately a [publishing plugin](https://plugins.gradle.org/docs/publish-plugin) is available which automates the entire process into one task.

We can apply the plugin by adding the Plugin Portal's maven repository:

```
buildscript {
    repositories {
        maven {
            url "https://plugins.gradle.org/m2/"
        }
    }
    dependencies {
        classpath "com.gradle.publish:plugin-publish-plugin:0.9.9"
    }
}
apply plugin: "com.gradle.plugin-publish"
```

And then we can configure the plugin with our project information through its extension:

```
pluginBundle {
    website = 'https://fractalwrench.co.uk'
    vcsUrl = 'https://github.com/fractalwrench/the-machine-that-goes-ping.git'

    plugins {
        pingPlugin {
            id = 'com.fractalwrench.pingmachine'
            description = 'Makes a ping noise on build completion'
            displayName = 'Ping Machine'
            tags = ['android']
            version = '1.0.0'
        }
    }
}

// JavaDoc errors may fail the publish task, so disable it
tasks.withType(Javadoc).all { enabled = false }
```

We'll make our final checks, then publish by running the `./gradlew publishPlugins` task.

### Try it in a fresh Android Project
Congratulations, we've just published a gradle plugin! Now we need to apply it to our Android project:

```
buildscript {
  repositories {
    maven {
      url "https://plugins.gradle.org/m2/"
    }
  }
  dependencies {
    classpath "gradle.plugin.com.fractalwrench:PingPlugin:1.0.0"
  }
}

apply plugin: "com.fractalwrench.pingmachine"
```

Whenever we build our project, we should hear a ping. You can view the [source on Github ](https://github.com/fractalwrench/the-machine-that-goes-ping) for a full example.

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes _PING_. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!
