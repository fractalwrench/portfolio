---
title: "The machine that goes PING"
subtitle: "Detecting build completion with a custom Gradle Plugin"
date: 2018-01-15T17:00:00+01:00
---

[Gradle](https://gradle.org/) is an 800lb magical gorilla that can be incredibly intimidating at first glance.

We're going to harness some of Gradle's superpowers by writing a plugin that alerts us whenever a build completes.

Essentially, this guide will teach you how to turn a shiny MacBook Pro into a [machine that goes PING](https://youtu.be/NcHdF1eHhgc?t=160).

## What is Gradle

[Gradle](https://docs.gradle.org/4.4.1/userguide/userguide.html) is

https://developer.android.com/studio/build/index.html

<!-- TODO what is Gradle -->

### What is a Gradle Plugin?

You've been using it whether you knew it or not.
https://developer.android.com/studio/releases/gradle-plugin.html

<!-- TODO -->
https://en.wikipedia.org/wiki/Duck_typing
If it looks like a duck and quacks like a duck, it will throw a `RuntimeException` at the worst possible moment.


## Writing our own plugin

<!-- TODO Delivery Mechanisms -->

### Setting up the buildSrc folder

1. Create a new project in Android Studio

2. We'll use the `<projectDir>/buildSrc/src/main/groovy` folder to setup our plugin locally. This does mean that we can't use it outside the current project. Another option would be to edit our build.gradle file directly, which nearly all of us will have done, or to publish it on an external repository.
https://docs.gradle.org/current/userguide/custom_plugins.html#sec:packaging_a_plugin

3. Create `PingPlugin.groovy` with the following contents

```
import org.gradle.api.Plugin
import org.gradle.api.Project

class PingPlugin implements Plugin<Project> {
    void apply(Project project) {
        println("I'm a plugin!")
    }
}
```

4. Add `apply plugin: PingPlugin` at the top of our app module's `build.gradle`, then run `./gradlew assemble`. The output should contain "I'm a plugin", and will verify that everything's setup correctly.

### Adding a custom task

A plugin is useless without a task.

- What is a task? Where have we seen tasks before?
https://docs.gradle.org/current/userguide/tutorial_using_tasks.html


`project.tasks` allows us to access all the tasks in the project, which are normally displayed in the Gradle panel (SEE SCREENSHOT)

We can lookup a specific task by the following method:
`Task assembleTask = project.tasks.findByName("assemble")`

We can define our own task using a closure, and tell the build task to execute it last.
```
assembleTask.doLast {
    project.logger.lifecycle("I'm a plugin!")
}
```



Output when running assemble:
```
:app:assemble
I'm a plugin!
```

### Make it ping

https://freesound.org/people/thomasevd/sounds/125374/
CC Attribution License

1. Add audio.wav to `buildSrc/src/main/resources/audio.wav`

2.
Add following to gradle plugin in `doLast` (loads audio file and plays it):
```
InputStream is = getClass().classLoader.getResourceAsStream("audio.wav")

if (is == null) {
    project.logger.error("Could not find Audio File")
}
new AudioPlayer().play(is)
```
3. Add `AudioPlayer.java` to `src/main/groovy` directory:

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

### Build Variants

You may have noticed that this doesn't work for debug mode

AGP adds its own tasks during the configuration phase, we can detect these by adding ours after project evaluation

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

<!-- TODO this is broken for multiple outputs! use mustRunAfter on the collection of assemble tasks -->


### Plugin Extensions

https://docs.gradle.org/current/userguide/custom_plugins.html#sec:getting_input_from_the_build

Add to top of `PingPlugin.groovy`
```
class PingPluginExtension {
    String audioFile = "audio.wav" // use default value
}
```

Create extension within apply method:
```
project.extensions.create("pingPlugin", PingPluginExtension)
```

<!-- TODO explain how `android { buildTypes { release { }}}` would work -->

Download extra sound "foo.wav" and place in resources folder

Configure within app module:


```
pingPlugin {
    audioFile "foo.wav"
}
```

Update our play method

```
InputStream is = getClass().classLoader.getResourceAsStream(project.pingPlugin.audioFile)

```


### Converting to Gradle Script Kotlin

KOTLIN ALL THE THINGS
https://blog.gradle.org/kotlin-meets-gradle
https://github.com/gradle/kotlin-dsl

Better autocomplete/IDE features as statically typed

Samples Dir is best documentation atm:
https://github.com/gradle/kotlin-dsl/tree/master/samples

Kotlin Gradle Script is bundled in gradlew, newer = better (or at least more bleeding edge)

Everything suffixed with .kts


Not going to use it yet because highlighting is broken in Android Studio 3: https://github.com/gradle/kotlin-dsl/issues/584



### Publishing Final product

- Create separate project for plugin + add bintray gradle plugin to simplify upload process: https://github.com/bintray/gradle-bintray-plugin

- Add `META-INF/gradle-plugins/com.fractalwrench.pingmachine.properties` file pointing at class:
`implementation-class=com.fractalwrench.pingmachine.PingPlugin`


Link to github

Signup to Gradle plugin portal and coopy api key info to gradle folder on your machine:
https://plugins.gradle.org/docs/submit

Apply publishing plugin following instructions here
https://plugins.gradle.org/docs/publish-plugin

Javadoc fails, disable tasks by placing at bottom:
`tasks.withType(Javadoc).all { enabled = false }``

https://github.com/bintray/gradle-bintray-plugin


### Try it in a fresh Android Project
Get it on Github:
https://github.com/fractalwrench/the-machine-that-goes-ping

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

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes _PING_. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!
