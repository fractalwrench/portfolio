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

https://github.com/junit-team/junit4/wiki/parameterized-tests

```
@RunWith(Parameterized::class)
class JsonConverterTest(val expectedFilename: String, val jsonFilename: String) {

    private val fileReader = ResourceFileReader()
    private val jsonConverter = DataClassJsonConverter()

    companion object {
        @JvmStatic
        @Parameterized.Parameters
        fun filenamePairs(): Collection<Array<String>> {
            return listOf(
                    arrayOf("HelloWorld.kt", "hello_world.json")
            )
        }
    }

    /**
     * Takes a JSON file and converts it into the equivalent Kotlin class, then compares to expected output.
     */
    @Test
    fun testJsonToKotlinConversion() {
        val json = fileReader.readContents(jsonFilename)
        val outputStream = ByteArrayOutputStream()
        jsonConverter.convert(json, outputStream)

        val generatedSource = String(outputStream.toByteArray())
        val expectedContents = fileReader.readContents(expectedFilename)

        val msg = "Generated file doesn't match expected file \'$expectedFilename\'"
        Assert.assertEquals(msg, expectedContents, generatedSource)
    }
}
```

We could execute the same code that checks the expected response against an arbitrary number of source files + kotlin files.


### Generating Test Cases

First things first, let's look at the JSON spec and get some suitable test cases.

JSON format:
https://tools.ietf.org/html/rfc7159


We'll need an intermediate representation of all the objects in the JSON tree, to determine any commonality between object types, and to find nullable fields

Test using GSON for now
https://stackoverflow.com/questions/44117970



We'll use TDD by splitting the test cases into functional areas, then adjust all our tests/implementation as we go.



Before we do all this, we're going to write a JSON Parser (link to second blog post)



<!-- TODO write a JSON parser?!? -->


#### Invalid Data

Invalid data should result in an empty `OutputStream`. Our application can detect this as an error case and inform the user accordingly

- Null (lol no, stop thinking like a Java Dev)
- Empty String
- Invalid JSON

#### Name-Value Pairs

- Name-Value Pairs should map onto one of the following primitives (String, Int, Double, Bool, Any?) as an intermediate type
- If a value equals `null`, it should be given an intermediate type (more on that later) of `Any?` as we don't have enough information to discern the type.

#### Arrays
- Arrays should map onto the following types: (String, Int, Double, Bool, Any?)
- Arrays should use the correct type for nested Arrays of the same object (Array<T>)
- Arrays should use the correct type for nested Objects of the same type (Array<T>)
- Arrays should use `Any` if a nested array has different non-null objects
- Arrays should use `Any?` if a nested array has different objects, some of which can be null
- The file should map correctly if it starts with an array (unusual case, but valid JSON)
- Empty arrays should be detected

#### Objects
- Nested objects should be mapped as a separate class
- If a nested object has the same type as the parent object, it should be mapped as the same class
- Objects of the same type which have exclusively non-null fields should map onto non-null fields (check on all possible data types)
- Objects of the same type which have some nullable fields should map onto non-null fields (check on all possible data types)

#### Generated Source Files
- The top-level class should take a user-specified name
- Multiple classes should be defined in the same file

#### Field Test
- JSON conversion should pass validation against some commonly used APIs
- Actually serialise real API JSON into some Kotlin classes + check values


#### Library Specific Source

- Add a delegate property to constructor which is called before each class/field is generated
- Add on annotations etc



### Try it today
<!-- TODO -->
You can view the complete source for this project on [Github](https://github.com/fractalwrench/the-machine-that-goes-ping).

### Thank You
I hope you've enjoyed learning about creating custom Gradle Plugins, and have upgraded your workstation to a machine that goes PING. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!

If you'd like to receive notifications about new blog posts, please subscribe to our mailing list!
