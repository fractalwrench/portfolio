---
title: "Converting JSON to Kotlin"
subtitle: "Automatically generating JSON data classes with Kotlin Poet"
date: 2018-01-31T00:00:00+00:00
---

We're going to write a tool that converts JSON into a Kotlin source file.

This will be similar to the jsonschema2pojo tool, which does something similar for Java.
http://www.jsonschema2pojo.org/


In the process we're going to learn a lot about Square's wonderful Kotlin Poet Library. https://github.com/square/kotlinpoet

<!-- TODO -->


## Setup

1. Think of a cool name
2. Give up and use `json-2-kotlin` instead
3. Create an empty project in IntelliJ, setup Git etc



### Converter

Let's add an abstraction layer, so that we can implement different forms of conversion (e.g. GSON, Moshi, Jackson) at a later stage

<!-- TODO rename? -->
```
interface JsonConverter {
    fun convert(input: InputStream): OutputStream
}
```


### Testing

- We want to test by inputting JSON, and asserting that the `OutputStream` matches the expected Kotlin class byte for byte.

We can add JSON and Kotlin files to our test `resources` folder this way, and parameterise a unit test which really contains very little code






### Try it today
<!-- TODO -->
You can view the complete source for this project on [Github](https://github.com/fractalwrench/the-machine-that-goes-ping).

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes PING. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!

If you'd like to receive notifications about new blog posts, please subscribe to our mailing list!
