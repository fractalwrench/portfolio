---
title: "Converting JSON to Kotlin"
subtitle: "Generating Kotlin data classes using Square's KotlinPoet"
date: 2018-01-31T00:00:00+00:00
---

Have you ever got bored writing Kotlin classes which serialise a JSON payload?

Me too. Fortunately, we're going to write a Kotlin tool that [automates the whole process](https://imgs.xkcd.com/comics/the_general_problem.png), using Square's awesome [KotlinPoet](https://github.com/square/kotlinpoet) library.

We're also going to take a greenfield Kotlin project all the way to production, by deploying a Spring Boot app on AWS, and creating a command line tool for local use.

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

## Creating the core Kotlin Library

We'll start by generating an empty Kotlin project, and add a Core, Command Line, and Spring Boot module. The core module will define a public API of two parts, and hide everything else. Firstly, we'll need a method to initiate conversion:

```
fun convert(input: InputStream, output: OutputStream, args: ConversionArgs)
```

Secondly, we'll also need a simple way of modifying the source generation process, to support the various JSON serialisers available. The delegate pattern is a good fit for this:

```
class Kotlin2JsonConverter(
    private val buildDelegate: SourceBuildDelegate = GsonBuildDelegate()
)
```

Both the Spring Boot and Command Line modules will depend on the core module, which allows us to dog-food our own API.

## Converting JSON to Kotlin

JSON is [deceptively complex](https://tools.ietf.org/html/rfc8259), particularly when we want to map it onto another type system. Primitive fields like Strings and Booleans are simple enough to convert, but there are a surprising number of edge cases. For example:

- Detecting null/omitted JSON fields.
- Converting JSON keys into a valid Kotlin identifier.
- Handling nested objects.
- Handling an array as the root element (and cursing the REST API developer who thought that would be a good idea).
- Picking names for elements in JSON arrays.
- Ensuring that JSON objects are grouped correctly, even when fields are null or omitted.

Thankfully we're only creating a Minimal Viable Product, so all we need to worry about is making sure that our approach generally works ok. If the project gains traction, we can address some of the more obscure edge cases later on.

To start converting JSON to Kotlin, we'll determine our general algorithmic approach to the problem, then write tests and iteratively develop features.

### JSON Conversion Algorithms

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

## Parameterised Test Cases for Source Code generation

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

### Test case coverage

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


## Implementing the Json2Kotlin converter

### JSON Tree traversal

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

### Grouping common objects
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

### Converting a JSON tree to Kotlin classes, one level at a time
<!-- TODO clarify that level is processed one at a time -->
Now that we know which objects share the same type, we can generate the type information using KotlinPoet. We'll start by creating a `TypeSpec` for our class:

```
private fun buildClass(commonElements: List<TypedJsonElement>, fields: Collection<String>): TypeSpec.Builder {
    val identifier = commonElements.last().kotlinIdentifier
    val classBuilder = TypeSpec.classBuilder(identifier.capitalize())
    val constructor = FunSpec.constructorBuilder()

    if (fields.isNotEmpty()) {
        val fieldTypeMap
                = typeReducer.findDistinctTypes(fields, commonElements, jsonElementMap)
        fields.forEach {
            buildProperty(it, fieldTypeMap, commonElements, classBuilder, constructor)
        }
        classBuilder.addModifiers(KModifier.DATA) // non-empty classes allow data modifier
        classBuilder.primaryConstructor(constructor.build())
    }

    delegate.prepareClass(classBuilder, commonElements.last())
    return classBuilder
}
```

There are a couple of things to note here. First is that we call to a delegate after the class is prepared, as this will allow us to modify the generated source code as needed. In the default case, this will add GSON annotations.

The other main thing to notice is the KotlinPoet builder, which record the required information. For each JSON field, we want to add a property to the `classBuilder` instance, so will build a property:



```
private fun buildProperty(fieldKey: String,
                          fieldTypeMap: Map<String, TypeName>,
                          commonElements: List<TypedJsonElement>,
                          classBuilder: TypeSpec.Builder,
                          constructor: FunSpec.Builder) {

    val kotlinIdentifier = fieldKey.toKotlinIdentifier()
    val typeName = fieldTypeMap[fieldKey]
    val initializer =
            PropertySpec.builder(kotlinIdentifier, typeName!!).initializer(kotlinIdentifier)
    delegate.prepareProperty(initializer, kotlinIdentifier, fieldKey, commonElements)
    classBuilder.addProperty(initializer.build())
    constructor.addParameter(kotlinIdentifier, typeName)
  }
```

The typename is simply the type of the property as determined at an earlier stage, whether it be `String`, `Any?`, or `Foo`.

After a `TypeSpec` for a class is constructed, it will be added to a map for each JSON object on this level, which effectively memoises the type for later lookups.

Our type will also be added to a Stack, where it will eventually be written to an `OutputStream` as a generated source file, and save us from the tedium of having to convert JSON to Kotlin by hand.


### Testing an example

<!-- TODO a bit abstract, use a complex but understandable example -->


## Writing a command Line Kotlin tool

Several weeks later, and we've implemented everything exactly according to plan, 100% bug free and perfectly documented (haha). So now it's time to write some wrappers around our API. We'll add separate modules for both a command line tool, and a Spring Boot application.

For our command line app, we'll add a dependency on the core project and the [Apache Commons CLI](https://commons.apache.org/cli/usage.html), which does all the hard work of parsing arguments:

```
compile project(":core")
compile "commons-cli:commons-cli:1.4"
```

### Handling command line arguments

The hardest part is deciding what options to expose, as this will be part of our public API. Less is more, so let's support the following options for now:

```
private fun prepareOptions(): Options {
    return with(Options()) {
        addOption(Option.builder("input")
                .desc("The JSON file input")
                .numberOfArgs(1)
                .build())
        addOption(Option.builder("packageName")
                .desc("The package name for the generated Kotlin file")
                .numberOfArgs(1)
                .build())
        addOption(Option.builder("help")
                .desc("Displays help on available commands")
                .build())
    }
}
```

We will then parse the arguments from our main methods, and execute the correct branch accordingly. If the arguments were invalid or not present, then we'll print a message to indicate that this was the case:

```
try {
    val cmd = parser.parse(prepareOptions(), args)

    if (cmd.hasOption("help") || !cmd.hasOption("input")) {
        printHelp(options)
    } else {
        val parsedOptionValue = cmd.getParsedOptionValue("input") as String
        val inputFile = Paths.get(parsedOptionValue).toFile()

        if (inputFile.exists()) {
            val outputFile = findOutputFile(inputFile)
            Kotlin2JsonConverter().convert(inputFile.inputStream(), outputFile.outputStream(), ConversionArgs())
            println("Generated source available at '$outputFile'")
        } else {
            println("Failed to find file '$inputFile'")
        }
    }
} catch (e: ParseException) {
  println("Failed to parse arguments: ${e.message}")
}
```

<!-- TODO test out and add screenshot? -->

### Distributing a Kotlin command-line tool

The advantage of a JVM language is that it should run pretty much anywhere in a JAR.

Gradle has a few additional tasks which simplify the generation process. We'll start by modifying our build file to contain the following information which is used to generate a valid JAR:

```
apply plugin: 'application'

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

We will then run the following steps to build and distribute our application:

1. Run assemble: `./gradlew assemble`
2. Extract dist at `cmdline/build/distributions/json2kotlin.zip`
3. Execute file: `./json2kotlin/bin/cmdline`

Onto Spring Boot.

## Writing a Spring Boot app in Kotlin

[Spring Boot](https://projects.spring.io/spring-boot/) is a Java Framework that can be used to create web applications, and has recently been adding a lot of Kotlin support. Developing a web application will be a little more involved, because we'll be hosting it on the internet, and it's a well-known fact that everyone on the internet is a horrible human being who wants to break everything. We also have to consider concurrent usage, and how to prevent & reject invalid payload submissions.

### Adding a controller for GET requests
We'll start off by creating an empty Spring Boot Web project by following Pivotal's very [handy guide](https://spring.io/guides/gs/rest-service/). After setting up the boilerplate, we'll create a class annotated with `Controller`, and setup a `RequestMapping` to the root of our project, like so:

```
@Controller
class ConversionController {

    @GetMapping("/")
    fun displayConversionForm(model: Model): String {
        model.addAttribute("conversionForm", ConversionForm())
        model.addAttribute("kotlin", "class Example")
        return "conversion"
    }
```

There's a lot of magic going on here. Behind the scenes, Spring will route HTTP requests to the specified path to our `displayConversionForm` method. This methods adds our Kotlin source as an attribute to a `Model`, then returns a view, which corresponds to a HTML template stored under `src/main/resources/static/templates`:

```
<html>
  <head></head>
  <body>
    <textarea th:text="${kotlin}"></textarea>
  </body>
</html>
```

The template is processed by [Thymeleaf](https://www.thymeleaf.org/), and any [expressions](https://docs.spring.io/spring/docs/4.3.12.RELEASE/spring-framework-reference/html/expressions.html) in the `th` namespace are resolved to HTML. This is then returned to the user, and rendered in the browser, as something like the following:

```
<html>
  <head></head>
  <body>
    <textarea text="class Example"></textarea>
  </body>
</html>
```

### Adding a POST request mapping

We're getting slightly ahead of ourselves here, as we can't display the generated Kotlin to the user until they submit their JSON input. We'll be achieving this by displaying a form to the user, which makes a POST request containing the JSON input to our endpoint:

```
<form id="jsonForm" action="#" th:action="@{/}" th:object="${conversionForm}"
              method="post" onsubmit="return validateForm()">
  <textarea maxlength="10000" placeholder="Paste JSON here..." th:field="*{json}"></textarea>
  <p><input type="reset" value="Reset"/> <input type="submit" value="Convert"/></p>
</form>
```

You may have noticed that the form object is bound to the `conversionForm` we added in our previous method, which contains a `json` field. We'll accept and convert this in our Controller:

```
@PostMapping("/")
fun convertToKotlin(model: Model, @ModelAttribute conversionForm: ConversionForm): String {
    val os = ByteArrayOutputStream()
    Kotlin2JsonConverter().convert(inputStream, os, ConversionArgs())
    model.addAttribute("kotlin", String(os.first.toByteArray()))
    return displayConversionForm(model)
}
```

### Building a pretty HTML page
We'll skip a few steps here that include adding front-end validation, download/copy options, and slaying CSS dragons.

If you're interested more in how the web functionality works, I'd encourage you to browse through the [Spring module](https://github.com/fractalwrench/json-2-kotlin/tree/master/spring/src/main) of the project. Please excuse my stone-age JavaScript - we appear to have reached a technological singularity and I simply can't keep up with the rate at which new JavaScript frameworks are being released.

## Deploying a Kotlin Spring Boot app to AWS Elastic Beanstalk

We're going to deploy using AWS, which has a [free tier](https://aws.amazon.com/free/) that should satisfy the needs of most hobby projects. Some level of familiarity with AWS is assumed from here on out, but here's a quick refresher of the services we'll be using:

[Elastic Beanstalk](https://aws.amazon.com/elasticbeanstalk/): Controls all the AWS services required to build a scalable application. EC2 instances will scale in response to incoming traffic
[EC2](https://aws.amazon.com/ec2/): Elastic Cloud Compute, basically a instance that hosts our JAR application in the cloud. Has a JVM environment already setup
[Elastic Load Balancer](https://aws.amazon.com/elasticloadbalancing/): Divides traffic between the available EC2 instances depending on how busy they are.
[Route 53](https://aws.amazon.com/route53/): allows us to register a domain name, and configure the DNS to point towards an Elastic Beanstalk application

### Registering a domain

1. Register domain (here's one I bought earlier) https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/registrar.html

2. Configure a hosted zone for the domain, using an ALIAS record: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-beanstalk-environment.html#routing-to-beanstalk-environment-create-alias-procedure

3. Wait 24h for DNS to propagate (usually a lot faster)

### Building a deployable JAR

Deploying a Kotlin Spring Boot JAR can be achieved broadly by following this [very helpful blog](https://aws.amazon.com/blogs/devops/deploying-a-spring-boot-application-on-aws-using-aws-elastic-beanstalk/) from AWS. Unfortunately a few of the steps don't seem to work with the default configuration, so we'll also have to take some additional steps.

### Updating JAR metadata
Let's update our build script to use the correct main class name, so that Java can locate our main method.

```
jar {
    baseName = 'json2kotlin'
    version = '0.1.0'
    manifest {
        attributes 'Main-Class': 'AppKt'
    }
    from { configurations.compile.collect { it.isDirectory() ? it : zipTree(it) } }
}
```

### Scaling our application with a load balancer
Our application will use a load balancer which should automatically scale server instances in the face of heavy traffic (Hi HN!). Depending on your anticipated traffic, you could skip this step altogether.

First, we'll set our server port in `application.properties` to the following value:

```
server.port=8888
```

Secondly, we'll point the load balancer and update the health check to use this port, by following [these instructions](https://pragmaticintegrator.wordpress.com/2016/08/04/configuring-the-elastic-load-balancer-of-your-elastic-beanstalk-application/).

Most importantly, we'll need to set up a health check, as this allows the load balancer to determine which instances are healthy. We could hit the root of our application but that's quite an expensive check. Instead, we'll [enable Spring Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/production-ready-enabling.html) which will enable a simple `/health` endpoint.

### Setup crash reporting with Bugsnag
There are probably a few bugs lurking in our application, so the next step is to add a solution that monitors any uncaught exceptions that occur in the wild. I chose [Bugsnag](https://www.bugsnag.com/) for this task, because:

- It supports both Kotlin and JavaScript, as well as [most languages under the sun](https://www.bugsnag.com/platforms/)
- It's free for open-source/community plans
- I suck at JavaScript and am anticipating a _lot_ of errors

As a full disclaimer, I work for Bugsnag, so you can blame me if anything goes wrong.

### Try it today

Finally, we'll run `bootRepackage` to generate a JAR of our application, and deploy it.

We should be greeted by a beautiful application, which you can find [here](http://json2kotlin.co.uk/). You can also view the complete source for this project on [Github](https://github.com/fractalwrench/json-2-kotlin).

### Thank You
I hope you've enjoyed learning about Kotlin source generation, and will sleep easy at night in the knowledge that you never have to write data classes by hand again.

If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!
