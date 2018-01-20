---
title: "Streaming JSON with Kotlin"
subtitle: "Writing a streamable JSON reader and writer with Kotlin"
date: 2018-01-31T00:00:00+00:00
---

We're going to write a tool that reads JSON from an InputStream, and writes it to an OutputStream.

This is useful for large files where memory is an issue, and seemed like a cool project to get started with Kotlin!

We're also going to use this to automatically convert JSON to Kotlin classes!


## Why roll our own?

- Event Driven Model should use less memory than other implementations which map onto Kotlin classes
- Faster, don't need to wait for the entire file to be downloaded to start parsing (mobile connections)
- Fine-grained control at the cost of more code
- Needed to fulfil a very specific use-case of automatically converting JSON to a Kotlin source file. Other library implementations didn't quite feel right as they have a larger API surface and focus more on mapping onto existing Kotlin classes, rather than having an event-driven model where the type is automatically provided.
- Wanted to learn more about the JSON specification and all the interesting edge cases! https://tools.ietf.org/html/rfc7159
- I foolishly disregarded everybody's advice that you should never write your own parser

## Setup
1. Create an empty project in IntelliJ, setup Git etc

## Defining our API


### Reading

We'll use the delegation pattern which is supported by Kotlin, as this is a good match for our event-driven model:
https://kotlinlang.org/docs/reference/delegation.html

```
class JsonReader(private val delegate: ReadDelegate): ReadDelegate by delegate {

    @Throws(IllegalStateException::class) // thrown when document ends
    fun read(stream: InputStream) {
    }
}

interface ReadDelegate {
    fun beginObject(name: String)
    fun endObject()
    fun beginArray(name: String)
    fun endArray()
    fun foundString(name: String, value: String)
    fun foundInt(name: String, value: Int)
    fun foundNumber(name: String, value: Number)
    fun foundBoolean(name: String, value: Boolean)
    fun foundAny(name: String, value: Any?)
}
```

### Writing

We'll use a similar approach for the writer:

```
class JsonWriter {

    @Throws(IllegalStateException::class)
    fun write(streamable: JsonStreamable, stream: OutputStream) {
        streamable.stream(this);
    }

    fun beginObject(name: String) {}
    fun endObject() {}
    fun beginArray(name: String) {}
    fun endArray() {}
    fun writeString(name: String, value: String?) {}
    fun writeInt(name: String, value: Int?) {}
    fun writeNumber(name: String, value: Number?) {}
    fun writeBoolean(name: String, value: Boolean?) {}
    fun writeAny(name: String, value: Any?) {}
    fun writeJsonStreamable(name: String, value: JsonStreamable?) {}

}

interface JsonStreamable {
    fun stream(writer: JsonWriter)
}
```

The `JsonStreamable` interface adds an extra bit compared to our Read API. The intention is that classes will implement this interface

This exploits the visitor pattern: https://en.wikipedia.org/wiki/Visitor_pattern#Java_example

We have defined how we write individual JSON fields in one place, but each class may want to write different numbers of fields with different values.

`JsonStreamable` also allows nesting, so we can write the entire JSON tree this way




### Try it today
<!-- TODO -->
You can view the complete source for this project on [Github](https://github.com/fractalwrench/the-machine-that-goes-ping).

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes PING. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!

If you'd like to receive notifications about new blog posts, please subscribe to our mailing list!
