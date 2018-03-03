---
title: "Converting JSON to Kotlin"
subtitle: "Automatically generating Kotlin data classes using Square's Kotlin Poet"
date: 2018-01-31T00:00:00+00:00
---

Have you ever got bored writing Kotlin classes which serialise a JSON payload?

Me too. Fortunately, we're going to write a Kotlin app that [automates the whole process](https://imgs.xkcd.com/comics/the_general_problem.png), using Square's awesome [KotlinPoet](https://github.com/square/kotlinpoet) library.

## Why build a new library?
There are a couple of existing options for converting JSON to Kotlin, such as [jsonschema2pojo](http://www.jsonschema2pojo.org/) and [JsonToKotlinClass](https://github.com/wuseal/JsonToKotlinClass), but none of them fit my usecase of being able to generate Kotlin from a browser in one click.

A few other reasons include:

- I thought it'd be an interesting project to learn Kotlin with.
- There aren't enough guides on creating multi-target Kotlin applications.
- I can't use Google effectively and didn't know about most of the existing projects until I'd finished.

The end result is Json2Kotlin, a small library (<1k loc) which has a command line and Spring Boot binding. Hopefully due to its size, you'll find it relatively easy to understand what's going on! On top of the obvious functionality, the project also achieves:

- Automatically determine nullable fields and represent them as nullable in Kotlin
- Grouping similar JSON objects into one Kotlin class type, and allows changing the default strategy
- Simple API for altering the generated source code (e.g. to support GSON serialised annotations)

Let's jump into how the library was constructed.

## Building a Kotlin Library

We'll start by generating an empty Kotlin project, and add a Core, Command Line, and Spring Boot module. The core module will define a public API of two parts, and hide everything else. Firstly, we'll need a method to initiate conversion:

```
fun convert(input: InputStream, output: OutputStream, args: ConversionArgs)
```

Secondly, we'll also need a simple way of modifying the source generation process, to support the various JSON serialisers available. The delegate pattern is a good fit for this:

```
class Kotlin2JsonConverter(private val buildDelegate: SourceBuildDelegate = GsonBuildDelegate()) {
}
```

Both the Spring Boot and Command Line modules will depend on the core module, which allows us to dog-food our own API.

## Converting to Kotlin

JSON is [deceptively complex](https://tools.ietf.org/html/rfc8259), particularly when we want to map it onto another type system. Primitive fields like Strings and Booleans are simple enough to convert, but there are a surprising number of edge cases. For example:

- Detecting null/omitted JSON fields.
- Converting JSON keys into a valid Kotlin identifier.
- Handling nested objects.
- Handling an array as the root element (and cursing the REST API developer who thought that would be a good idea).
- Picking names for elements in JSON arrays.
- Ensuring that JSON objects are grouped correctly, even when fields are null or omitted.

Thankfully we're only creating a Minimal Viable Product, so all we need to worry about is making sure that our approach generally works ok. If the project gains traction, we can address some of the more obscure edge cases later on.

To start converting JSON to Kotlin, we'll determine our general algorithmic approach to the problem, then write tests and iteratively develop features.

### Algorithmic approach

JSON is a [tree](https://en.wikipedia.org/wiki/Tree_(data_structure), where any of the array or object nodes could potentially have child nodes. We could start at the root node and work our way to the bottom, but this could lead to a scenario where we need to de-duplicate class types. For example, the object field in the following JSON should correspond to the following Kotlin code:

```
{
  "obj": {
    "foo": "something"
  },
  "another": {
    "foo": "another field"
  }
}
```

```
data class Example(val obj: Obj, val another: Obj)
data class Obj(val foo: String)
```

This may seem like a pointless distinction at this point. And indeed, it is completely feasible to convert the `obj` field, then `another`, then recursively de-duplicate the two generated types into one.

However, if we start at the bottom of the tree, then we can process all the objects in one level of the tree at a time, and de-duplicate them before moving up one level. Using this approach, we will see that the two objects should be grouped into `Obj`. When we move onto the next level, `Obj` will be an available type, and we won't have to bother with complex de-duplication at the end.

Therefore, our approach will be something like follows:

1. Sanitise input and [generate a JSON tree using GSON](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/JsonReader.kt)
2. Use [breadth-first search](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/ReverseJsonTreeTraverser.kt) to add each JSON node onto a Stack, along with some additional metadata.
3. Perform the dirty business of [generating Type information](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/TypeSpecGenerator.kt), by [grouping common objects](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/GroupingStrategy.kt) depending on their number of common keys, and [de-duplicating generated types](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/TypeReducer.kt)
4. Popping the stack of [generated type information](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/SourceFileWriter.kt) and writing it to an `OutputStream`.

That sounds hard! Before we get started, we'd better write some tests.

## Parameterised Test Cases

There a lot of potential JSON structures, but at the end of the day all we want to  check that given a JSON input, the correct Kotlin output is generated. This makes them a prime candidate for [JUnit parameterised tests](https://github.com/junit-team/junit4/wiki/parameterized-tests).

Here's a simplified version of our test, which parameterises the two filenames:

```
@RunWith(Parameterized::class)
class JsonConverterTest(val expectedFilename: String, val jsonFilename: String) {

    companion object {
        @JvmStatic
        @Parameterized.Parameters
        fun filenamePairs(): Collection<Array<String>> {
            return listOf(arrayOf("HelloWorld.kt", "hello_world.json"))
        }
    }
}
```

A test run will be generated for each pair of parameters. Therefore, all that is write the code to convert JSON to Kotlin, and compare the generated source code against the expected:

```
@Test
fun testJsonToKotlinConversion() {
    val outputStream = ByteArrayOutputStream()
    jsonConverter.convert(json, outputStream, ConversionArgs())
    val generatedSource = String(outputStream.toByteArray())
    val expectedContents = fileReader.readContents(expectedFilename)
    Assert.assertEquals(msg, expectedContents)
}
```

This assumes that the files are present in `src/test/resources`, as we can obtain an `InputStream` via the `ClassLoader`:

```
val inputStream = ResourceFileReader::class.java.classLoader.getResourceAsStream("HelloWorld.kt")
```

The [full test](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/test/kotlin/com/fractalwrench/json2kotlin/JsonConverterTest.kt) takes this even further, by recursively detecting any JSON/Kotlin files within the resources directory. This means we can just add a pair of JSON and Kotlin files, and we'll automatically have a test case.

### What to test

There are a few obvious things to test, such as handling invalid JSON, and serialising real-world payloads. However, we'll also want to add coverage for some of the following scenarios:

- Conversion Arguments supplied by the user
- Ordering of generated fields
- Name generation in arrays
- Handling of Nullity
- JSON object grouping
- Any edge cases detected during development
- Serialisation of Primitives, Arrays, and Objects

JSON is hard, so we'll broadly follow TDD, and gradually add tests as we pass features. For example, to check that a String serialised correctly, we would write the following test case:

```
{
  "strField": "Foo"
}
```

```
import kotlin.String

data class StrExample(val strField: String)
```

The latest test suite is available [here](https://github.com/fractalwrench/json-2-kotlin/tree/master/core/src/test/resources/valid)


## Implementation

### Tree traversal

We'll start by implementing a [breadth-first search](https://en.wikipedia.org/wiki/Breadth-first_search) to add each non-primitive JSON node to a stack.

```
private fun buildStack(bfsStack: Stack<TypedJsonElement>, parent: JsonElement, key: String?) {
    val queue = LinkedList<TypedJsonElement>()
    queue.add(TypedJsonElement(parent, key!!, 0))

    while (queue.isNotEmpty()) {
        val element = queue.poll()
        bfsStack.push(element)

        val complexChildren = with(element) {
            when {
                isJsonObject -> convertParent(asJsonObject, level + 1)
                isJsonArray -> convertParent(asJsonArray, jsonKey, level + 1)
                else -> Collections.emptyList()
            }
        }
        queue.addAll(complexChildren)
    }
}
```

We can then take the stack, and process all the nodes in one level at a time, generating a [TypeSpec](https://square.github.io/kotlinpoet/0.x/kotlinpoet/com.squareup.kotlinpoet/-type-spec/) that is used by KotlinPoet to generate a class.

```
fun generateTypeSpecs(bfsStack: Stack<TypedJsonElement>): Stack<TypeSpec> {
    val typeSpecs = Stack<TypeSpec>()
    var level = -1
    val levelQueue = LinkedList<TypedJsonElement>()

    while (bfsStack.isNotEmpty()) {
        val pop = bfsStack.pop()

        if (level != -1 && pop.level != level) {
            processTreeLevel(levelQueue, typeSpecs)
        }
        levelQueue.add(pop)
        level = pop.level
    }
    processTreeLevel(levelQueue, typeSpecs)
    return typeSpecs
}
```

### Group common objects
Now that we have all the JSON nodes in one level of the tree, we can group any common objects together. We'll use a really simple strategy, where 1/5 or more of the keys must match between two objects for them to have the same type. We'll also make this transitive - i.e., if the object pairs A+B and B+C match, then A+C also match.

```
// builds a list of common objects, implementation omitted
fun groupCommonJsonObjects(jsonElements: MutableList<TypedJsonElement>): List<List<TypedJsonElement>>

internal fun defaultGroupingStrategy(lhs: TypedJsonElement, rhs: TypedJsonElement): Boolean {
    val lhsKeys = lhs.asJsonObject.keySet()
    val rhsKeys = rhs.asJsonObject.keySet()
    val lhsSize = lhsKeys.size
    val rhsSize = rhsKeys.size
    val emptyClasses = (lhsKeys.isEmpty() || rhsKeys.isEmpty())

    val maxKeySize = if (lhsSize > rhsSize) lhsSize else rhsSize
    val commonKeyCount = if (emptyClasses) 1 else lhsKeys.intersect(rhsKeys).size

    return (commonKeyCount * 5) >= maxKeySize // at least a fifth of keys must match
}
```

We'll also make it easy to alter the grouping strategy at a later date, by accepting a function reference as a constructor parameter:

```
// typealias used to make method signature more human-readable
internal typealias GroupingStrategy = (lhs: TypedJsonElement, rhs: TypedJsonElement) -> Boolean
internal class JsonFieldGrouper(private val groupingStrategy: GroupingStrategy = ::defaultGroupingStrategy)
```






### Convert tree level

- We now know all the Types of each Json Element, so can generate Kotlin source.
- We will do this using KotlinPoet
- Delegate will be called whenever creating a property/class
- BuildClass will memoize the constructed types
- Add TypeSpec to stack for ordering purposes
- Write results to OutputStream


Conversion:
- Support GSON because that's what I use, but make it extensible for others to add to if they wish






## Command Line

So we've implemented everything exactly according to plan, 100% bug free, and now it's time to write some wrappers around our API. We'll add separate modules for both a command line tool, and a Spring Boot application.

Add a dependency on the core project, and the Apache Commons CLI, which does all the hard work of parsing command line args: https://commons.apache.org/cli/usage.html

```
implementation project(":core")
implementation "commons-cli:commons-cli:1.4"
```

Configure JAR generation to run correctly:

```
mainClassName = "com.fractalwrench.json2kotlin.AppKt"

jar {
    manifest {
        attributes "Main-Class": "$mainClassName"
    }
    from {
        configurations.compile.collect { it.isDirectory() ? it : zipTree(it) }
    }
}
distributions {
    main {
        baseName = 'json2kotlin'
    }
}
```

Build steps:

1. Run assemble: `./gradlew assemble`
2. Extract dist at `cmdline/build/distributions/json2kotlin.zip`
3. Execute file: `./json2kotlin/bin/cmdline`

### Testing it out

We should be able to convert a JSON file to a Kotlin file automagically. Let's test it out.

<!-- TODO test -->

## Spring Boot

[Spring Boot](https://projects.spring.io/spring-boot/) is a Java Framework that can be used to create web applications, and has recently been adding a lot of Kotlin support. Developing a web application will be a little more involved, because we'll be hosting it on the internet, and it's a well-known fact that everyone on the internet is a horrible human being who wants to break everything.

Dev things:

- Max limit for payload size
- Concurrent use by multiple users
- Reject invalid JSON on frontend + backend
- Rate-limit requests to stop Denial of Service
- Make a pretty page
- Download generated source
- Cross-browser compatibility
- SEO
- Big shiny paypal button for everyone to ignore

Ops things:

- Register domain and generate SSL certificate
- Host web application on internet
- Attempt to scale in the event of heavy traffic (hi HN!)
- Monitoring downtime/warnings

I'm sure glad that my day-job isn't as a web developer.


### Development


#### Basic Boilerplate

1. Create a template REST API application if not familiar already https://spring.io/guides/gs/rest-service/
<!-- TODo -->

```
@Controller
class ConversionController {

    @GetMapping("/")
    fun displayConversionForm(): String {
        return "conversion"
    }
```

2. Add a HTML file named "conversion" under `src/main/resources/static/templates`, Spring will automagically detect the template and serve it when the endpoint is requested.

3. Add any static resources (CSS, images, etc) under the same directory

4. View results in web browser

#### Converting JSON

We're already depending on the Core project, so it should be the case of accepting a post request that contains a few parameters and a valid JSON payload. To do that we'll need a new endpoint. We can then convert the payload using our regular JSON converter, then return the Kotlin source as the output. In addition, we'll need to rate-limit, reject invalid input, etc.


<!-- TODO -->


### Deployment

We're going to deploy using AWS, which has a free tier that should satisfy the needs of most hobby projects: https://aws.amazon.com/free/

Quick refresher:

Elastic Beanstalk: Controls all the AWS services required to build a scalable application. EC2 instances will scale in response to incoming traffic
EC2: Elastic Cloud Compute, basically a instance that hosts our JAR application in the cloud. Has a JVM environment already setup
Elastic Load Balancer: Divides traffic between the available EC2 instances depending on how busy they are.
Route 53: allows us to register a domain name, and configure the DNS to point towards an Elastic Beanstalk application
AWS Cert manager: creates a certificate for a domain that we own

<!-- TODO -->


### Try it today
You can view the complete source for this project on [Github](https://github.com/fractalwrench/json-2-kotlin).

### Thank You
I hope you've enjoyed learning about Kotlin source generation, and will sleep easy at night in the knowledge that you never have to write data classes by hand again. If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!
