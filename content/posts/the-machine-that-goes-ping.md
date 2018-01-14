---
title: "The machine that goes PING"
subtitle: "Developing a Gradle Plugin that detects build completion"
date: 2018-01-14T00:00:00+00:00
---

[Gradle](https://gradle.org/) is an 800lb magical gorilla that can be incredibly intimidating at first glance.

We're going to harness some of Gradle's superpowers by writing a plugin that alerts us whenever a build completes.

Essentially, this guide will teach you how to turn a shiny MacBook Pro into a [machine that goes PING](https://youtu.be/NcHdF1eHhgc?t=160).

## What is Gradle

[Gradle](https://docs.gradle.org/4.4.1/userguide/userguide.html) is simply a tool that builds a project, and provides a very flexible API for manipulating each step of the process. It's the default build tool for Android projects, although alternatives like [Bazel](https://bazel.build/) and [Buck](https://buckbuild.com/) exist.

Typically when we're developing an Android App, we'll perform a few different actions in the course of a day. We will build the app to ensure that our changes haven't introduced compilation errors. We will run the app on an emulator to ensure that the app doesn't crash at runtime. If we're being good, we'll run instrumented tests on a device.

All of these actions are performed by executing [Gradle tasks](https://docs.gradle.org/4.4.1/userguide/tutorial_using_tasks.html#sec:projects_and_tasks).

### Gradle Tasks

So what is a Gradle Task, and why are they so flexible? The Task Panel in Android Studio allows us to observe some of the available tasks, and there are a lot:

![Gradle Tasks Panel in Android Studio](/img/pingmachine/gradle_panel_tasks.PNG)

Tasks such as `build` obviously compile our source code. The `clean` task will clear our build cache. But what about something like `connectedCheck`, which runs tests on a connected device?

#### Task Dependencies

Let's think about the prerequisites. Before running instrumented tests on our device, we first need to build our source code, package an APK, and install it via [adb](https://developer.android.com/studio/command-line/adb.html). Rather than redefine all this functionality, the `connectedCheck` task could instead declare a dependency on the build, package, and install tasks, and then run whatever custom logic is needed.

There are multiple ways to [add dependencies to tasks](https://docs.gradle.org/4.4.1/userguide/more_about_tasks.html), such as `doLast`, which will execute as the last part of a task. It's also possible to add dependencies and order task execution, through the use of `dependsOn` and `mustRunAfter`.

If you're confused about how this translates into a very flexible API, we're missing two pieces of very crucial information. One, Gradle allows you to lookup any existing task in the project. Two, it's possible to add our own custom tasks to a project, and make them execute before or after existing tasks by [adding task dependencies](https://docs.gradle.org/4.4.1/userguide/more_about_tasks.html#sec:adding_dependencies_to_tasks).

This is an incredibly powerful concept that allows us to achieve things that would otherwise appear magical.

### Gradle Plugins

Surprise, you've been using a [Gradle Plugin](https://developer.android.com/studio/releases/gradle-plugin.html) in your project whether you knew it or not, in the form of the Android Gradle Plugin! Gradle isn't an Android Specific build tool, so the AGP adds Android-specific build tasks, such as Lint Checks, to each module that has `apply plugin 'com.android.application'` in its `build.gradle`.

A plugin is essentially just an easy way of modularising custom tasks and sharing them with other developers. So let's write our own!

## Writing our own plugin

We'll start by creating a default Android project in Android Studio, and adding a folder at `<projectDir>/buildSrc/src/main/groovy`. This does mean that we can't use the plugin outside the current project, so there will be some additional work when we publish to an external repository.

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

Finally, we'll add `apply plugin: PingPlugin` at the top of our app module's `build.gradle`, then run `./gradlew assemble`. The `apply` method will be invoked with an instance of `Project` whenever we run a build, so the Gradle Console output should contain `"I'm a plugin"`.

### Adding a custom Gradle task

Our plugin is currently quite useless, so let's add some crazy Gradle magic by writing a custom task. We'll start off by accessing all the existing tasks in the project, via `project.tasks`.

Next, we need to lookup the task that we're interested in, which in our case is `assemble`. If we weren't sure which task to use, we could run `./gradlew tasks`, which lists all tasks in the project, or consult the [AGP docs](https://google.github.io/android-gradle-dsl/current/).

```
Task assembleTask = project.tasks.findByName("assemble")
```

Finally, let's create our own task with a closure, and make it execute once the rest of the `assemble` task has completed by specifying `doLast`:

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

And will produce the following output on a successful build of our Android App:

```
:app:assemble
I'm a plugin!
```

### Make it ping

Our next step is to make the application play a sound, rather than log a message. To do this, we'll download a suitable [PING](https://freesound.org/people/thomasevd/sounds/125374/) audio clip that is under the CC Attribution License, and add it to our resources folder, at `buildSrc/src/main/resources/audio.wav`.

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

### Android Build Variants

With great power comes great responsibility, and great potential for snafus. You may have noticed that this doesn't work when running the app in debug mode from Android Studio, because this action doesn't execute the `assemble` task.

The reason for this is that Gradle has [3 build phases](https://docs.gradle.org/current/userguide/build_lifecycle.html#sec:build_phases): initialisation, configuration, and execution.

The Android Gradle Plugin adds its own tasks before the execution phase, most notably the `assembleDebug` and `assembleRelease` tasks.

To fix our oversight, we can ask Gradle to iterate through all the build variants in our project after these tasks have been added. For each variant, we can find the assemble task for each output, and add a dependency on an audio playback task.

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

We can fix this at a later time - for now let's expose an extension that allows developers to control the behaviour of our plugin.

### Gradle Plugin Extensions

You're already [familiar with extension objects](https://docs.gradle.org/current/userguide/custom_plugins.html#sec:getting_input_from_the_build), whether you know it [or not](https://google.github.io/android-gradle-dsl/current/com.android.build.gradle.AppExtension.html). For example, most of us have set the `versionName` for our app before:

```
android {
    defaultConfig {
        versionName "3.5.7"
    }
}
```

The `android` extension is supplied as part of the AGP, and allows us to specify various build parameters without needing to hack on internal Gradle tasks.

### Creating a Gradle Plugin Extension

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

And finally, we can configure the plugin from our app's build script:

```
pingPlugin {
    audioFile "foo.wav"
}
```

For now, we'll skip adding an extension, and focus on publishing our plugin as a JAR, so that anybody else in the world can use it in their project.

## Publishing a Gradle Plugin

### Standalone Project

We've outgrown the `buildSrc` folder. It's time to create a [standalone project](
https://docs.gradle.org/current/userguide/custom_plugins.html#sec:custom_plugins_standalone_project) for the plugin.

We'll start by creating an empty Android Studio project, and deleting all the auto-generated Android code and app module, which we won't be needing. We will then copy our `src/main` directory across to the project root.

A couple of additional steps are required. Firstly, we need to add a few dependencies that were previously implicit:

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

Secondly, we need to tell Gradle where the plugin is. This is achieved by adding a properties file to the META-INF directory. For our project, we would need to create a file called `META-INF/gradle-plugins/com.fractalwrench.pingmachine.properties`, with the following contents:

```
implementation-class=com.fractalwrench.pingmachine.PingPlugin
```

### Publishing to the Gradle Plugin Portal

We're going to publish to the Gradle Plugin Portal, so will need to sign up for an account, and setup an API key as [detailed here](https://plugins.gradle.org/docs/submit). Fortunately a [publishing plugin](https://plugins.gradle.org/docs/publish-plugin) is available which automates the upload process into one Gradle task.

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

And then configure our project information through its extension:

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
Congratulations, we've just published a gradle plugin! Now we can apply it to any Android project, and hear a ping whenever we build:

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

You can view the complete source for this project on [Github](https://github.com/fractalwrench/the-machine-that-goes-ping).

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes PING. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!

If you'd like to receive notifications about new blog posts, please subscribe to our mailing list!
