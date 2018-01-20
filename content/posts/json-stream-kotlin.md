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
- Needed to fulfil a very specific use-case of automatically converting JSON to a Kotlin source file, other library implementations didn't quite feel right as they have a larger API surface and focus more on mapping onto existing Kotlin classes
- Wanted to learn more about the JSON specification and all the interesting edge cases! https://tools.ietf.org/html/rfc7159
- I foolishly disregarded everybody's advice that you should never write your own parser

## Setup
1. Create an empty project in IntelliJ, setup Git etc

## Defining our API







### Try it today
<!-- TODO -->
You can view the complete source for this project on [Github](https://github.com/fractalwrench/the-machine-that-goes-ping).

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes PING. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!

If you'd like to receive notifications about new blog posts, please subscribe to our mailing list!
