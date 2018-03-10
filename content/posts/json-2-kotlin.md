---
title: "Converting JSON to Kotlin"
subtitle: "Generating Kotlin data classes using Square's KotlinPoet"
date: 2018-03-09T00:00:00+00:00
---

Have you ever got bored writing Kotlin classes which serialise a JSON payload?

Me too. Fortunately, we're going to write a Kotlin library that [automates the whole process](https://imgs.xkcd.com/comics/the_general_problem.png), using Square's awesome [KotlinPoet](https://github.com/square/kotlinpoet).

We're then going to create a command-line tool and Spring Boot application and deploy both to production.

## Creating the core Kotlin Library
We'll start by generating an empty Kotlin project with a module named `core`.

This module will contain all the conversion code, so we should define an API that encapsulates most of the gory details. Firstly, we'll need a method that converts a JSON `InputStream` to a Kotlin `OutputStream`:

```
fun convert(input: InputStream, output: OutputStream, args: ConversionArgs)
```

We'll also want to modify the source code at the time of generation, as several JSON serialisation libraries require annotations like `@SerializedName`. To achieve this we'll provide callbacks via a delegate:

```
class Kotlin2JsonConverter(
    private val buildDelegate: SourceBuildDelegate = GsonBuildDelegate()
)
```

For our Spring Boot and command-line applications, we'll create separate modules which both depend on the `core` module. More on that later.

### JSON Conversion Algorithms
JSON is a [tree](https://en.wikipedia.org/wiki/Tree_data_structure), where each array and object node could contain child nodes.

We'll start at the bottom level of the tree, group similar nodes together, and build a Kotlin class for each group. representation. We'll then jump up a level until we reach the root of the tree.

#### A conversion example
That all sounds very abstract. Consider the following JSON:

```
{
  "obj": {
    "foo": "a string value"
  },
  "another": {
    "foo": "another string value"
  },
  "primitive": true
}
```

We can clearly see that both objects at the bottom of the tree have a key of `foo`, and a type of `String`:

```
{
  "foo": "a string value"
},
{
  "foo": "another string value"
}

```

Therefore we'll group them together, and represent them with a single Kotlin type:

```
data class Obj(val foo: String)
```


When we reach the next level, we can immediately see that there are two fields of type `Obj`, and one primitive field of type `Boolean`:

```
{
  "obj": Obj,
  "another": Obj,
  "primitive": Boolean
}
```

And as we've reached the root node, we've finished converting our JSON to Kotlin:

```
data class Example(val obj: Obj, val another: Obj, val primitive: Boolean)
data class Obj(val foo: String)
```

#### JSON is simple, right?

Of course, it's not always as easy as our example. JSON is [deceptively complex](https://tools.ietf.org/html/rfc8259), and there are a surprising number of scenarios which we'll need to address. For example:

- What happens if a field is null or omitted?
- How should JSON keys be converted into valid Kotlin identifiers?
- What happens if objects have matching fields, which use different types?
- How should objects be grouped together, if they don't share 100% of the same keys?

Sounds hard! We'd better write some tests.

## Parameterised Test Cases for Source Code generation

Generally speaking, we want to verify that given a JSON input, the correct Kotlin output is generated. As we're going to test many different JSON structures, we'll avoid duplicating code by writing [JUnit parameterised tests](https://github.com/junit-team/junit4/wiki/parameterized-tests).

Here's a simplified version of our test, which parameterises two filenames:

```
@RunWith(Parameterized::class)
class JsonConverterTest(val expectedFilename: String,
                        val jsonFilename: String) {

    companion object {
        @JvmStatic
        @Parameterized.Parameters
        fun filenamePairs(): Collection<Array<String>> {
            return listOf(arrayOf("HelloWorld.kt", "hello_world.json"))
        }
    }
}
```

JUnit will run the test once for each parameter pair. Therefore, all we need to do is write a test that performs the conversion, and verifies that the generated source code is correct.

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

For example, the test case may verify an input matches an output similar to this:
```
{"foo":"Hello World!"}
data class Example(val foo: String)
```

This test assumes that a JSON input file and Kotlin output file are present in `src/test/resources`, and reads the expected contents via the `ClassLoader`:

```
val classLoader = ResourceFileReader::class.java.classLoader
val inputStream = classLoader.getResourceAsStream("HelloWorld.kt")
```

The [full test](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/test/kotlin/com/fractalwrench/json2kotlin/JsonConverterTest.kt) takes this even further, by recursively detecting JSON/Kotlin files within the resources directory. This means we can just add a pair of JSON and Kotlin files, and we'll automatically have a test case.

The latest test suite is available on the [Github repository](https://github.com/fractalwrench/json-2-kotlin/tree/master/core/src/test/resources/valid).



## Implementing the Json2Kotlin converter
Before we look at our approach in more detail, let's summarise the steps:

1. Sanitise input and [generate a JSON tree using GSON](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/JsonReader.kt)
2. Use [breadth-first search](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/ReverseJsonTreeTraverser.kt) to push each JSON node onto a Stack, along with some additional metadata.
3. Traverse in reverse level order and [generate type information](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/TypeSpecGenerator.kt), [group common objects](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/GroupingStrategy.kt) then [reduce common objects to a single type types](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/TypeReducer.kt).
4. Pop the stack of [generated type information](https://github.com/fractalwrench/json-2-kotlin/blob/master/core/src/main/kotlin/com/fractalwrench/json2kotlin/SourceFileWriter.kt) and write it to an `OutputStream`.

### JSON Tree traversal

We'll start by implementing a [breadth-first search](https://en.wikipedia.org/wiki/Breadth-first_search) that pushes non-primitive JSON nodes to a stack.

```
private fun buildStack(bfsStack: Stack<TypedJsonElement>,
                       parent: JsonElement,
                       key: String?) {
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

We'll then pop from the stack and process JSON nodes. For each level, we'll generate a [TypeSpec](https://square.github.io/kotlinpoet/0.x/kotlinpoet/com.squareup.kotlinpoet/-type-spec/) for each distinct object grouping.

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
Our grouping strategy will be very simple. For objects to belong to the same type, they must share 1/5 or more of the same keys. The only exception to this will be an empty class, which will be considered to share 1 key automatically.

```
// builds a list of common objects, implementation omitted
fun groupCommonJsonObjects
(jsonElements: MutableList<TypedJsonElement>): List<List<TypedJsonElement>>

internal fun defaultGroupingStrategy(lhs: TypedJsonElement,
                                     rhs: TypedJsonElement): Boolean {
    val lhsKeys = lhs.asJsonObject.keySet()
    val rhsKeys = rhs.asJsonObject.keySet()
    val lhsSize = lhsKeys.size
    val rhsSize = rhsKeys.size
    val emptyClasses = (lhsKeys.isEmpty() || rhsKeys.isEmpty())

    val maxKeySize = if (lhsSize > rhsSize) lhsSize else rhsSize
    val commonKeyCount = if (emptyClasses) {
        1
    } else  {
        lhsKeys.intersect(rhsKeys).size
    }

    // at least a fifth of keys must match
    return (commonKeyCount * 5) >= maxKeySize
}
```

We'll also make it easy to alter the grouping strategy at a later date, by accepting a function reference as a constructor parameter:

```
// typealias used to make method signature more human-readable
typealias GroupingStrategy =
 (lhs: TypedJsonElement, rhs: TypedJsonElement) -> Boolean
class JsonFieldGrouper(private val strategy: GroupingStrategy = ::myStrategy)
```

### Generating KotlinPoet TypeSpecs
Now that our objects are grouped, we can generate type representations using KotlinPoet. We'll start by building a `TypeSpec`:

```
private fun buildClass(commonElements: List<TypedJsonElement>,
                       fields: Collection<String>): TypeSpec.Builder {

    val identifier = commonElements.last().kotlinIdentifier
    val classBuilder = TypeSpec.classBuilder(identifier.capitalize())
    val constructor = FunSpec.constructorBuilder()

    if (fields.isNotEmpty()) {
        val fieldTypeMap = typeReducer.findDistinctTypes(fields,
                                                         commonElements,
                                                         jsonElementMap)
        fields.forEach {
            buildProperty(it, fieldTypeMap,
                          commonElements, classBuilder, constructor)
        }
        classBuilder.addModifiers(KModifier.DATA)
        classBuilder.primaryConstructor(constructor.build())
    }

    delegate.prepareClass(classBuilder, commonElements.last())
    return classBuilder
}
```

There's quite a lot going on here. First, we create a `TypeSpec.Builder`, which holds the information used to build a class.

We then add the `data` modifier, build a constructor, and for each JSON field, call the `buildProperty` method:

```
private fun buildProperty(fieldKey: String,
                          fieldTypeMap: Map<String, TypeName>,
                          commonElements: List<TypedJsonElement>,
                          classBuilder: TypeSpec.Builder,
                          constructor: FunSpec.Builder) {

    val kotlinIdentifier = fieldKey.toKotlinIdentifier()
    val typeName = fieldTypeMap[fieldKey]

    val initializer = PropertySpec.builder(kotlinIdentifier, typeName!!)
                                  .initializer(kotlinIdentifier)
    delegate.prepareProperty(initializer, kotlinIdentifier,
                            fieldKey, commonElements)

    classBuilder.addProperty(initializer.build())
    constructor.addParameter(kotlinIdentifier, typeName)
  }
```

We add a property for each JSON field by generating a `PropertySpec`. For our case, all we need to include is the Kotlin identifier, and the property's Kotlin type, which is represented by `TypeName`.

The typename may be a Kotlin Standard Library type such as `String?`, but could also be a type generated earlier on, such as `Foo`.

Each `TypeSpec` will be pushed to a Stack, where it will eventually be written to an `OutputStream` as a Kotlin source file.

## Writing a Kotlin command-line application
Our conversion tool is working pretty nicely now, so we'll start writing a command-line app. We'll add a dependency on the `core` module and the [Apache Commons CLI](https://commons.apache.org/cli/usage.html), which does all the hard work of parsing arguments:

```
compile project(":core")
compile "commons-cli:commons-cli:1.4"
```

### Handling command line arguments
We'll start off by supporting `help` and `input` arguments:

```
private fun prepareOptions(): Options {
    return with(Options()) {
        addOption(Option.builder("input")
                .desc("The JSON file input")
                .numberOfArgs(1)
                .build())
        addOption(Option.builder("help")
                .desc("Displays help on available commands")
                .build())
    }
}
```

We should handle each argument in our main method. If the arguments were invalid or not present, then we'll print a message indicating that was the case, otherwise we'll attempt to convert the JSON to Kotlin:

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
            val input = inputFile.inputStream()
            val output = outputFile.outputStream()
            Kotlin2JsonConverter().convert(input, output, ConversionArgs())
            println("Generated source available at '$outputFile'")
        } else {
            println("Failed to find file '$inputFile'")
        }
    }
} catch (e: ParseException) {
    println("Failed to parse arguments: ${e.message}")
}
```

### Distributing a Kotlin command-line application

JVM languages run pretty much anywhere in a JAR, and Gradle has a few tasks which simplify the process. Our build file needs a few modifications, such as specifying the location of our main class:

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

We will then run the following task to distribute and test our application:

```
./gradlew assemble
unzip cmdline/build/distributions/json2kotlin.zip -d json2kotlin
./cmdline -input /c/Users/<User>/json2kotlin/bin/test.json
```

Onto Spring Boot.

## Writing a Spring Boot app in Kotlin
[Spring Boot](https://projects.spring.io/spring-boot/) is a Java Framework that can be used to create web applications, and has recently announced first-class Kotlin support.

### Adding a controller for GET requests
We'll start off by creating an empty Spring Boot Web project by following Pivotal's very [handy guide](https://spring.io/guides/gs/rest-service/). We'll create a class annotated with `Controller`, and setup a `RequestMapping` to the root endpoint:

```
@Controller
class ConversionController {
    @GetMapping("/")
    fun displayConversionForm(model: Model): String {
        model.addAttribute("conversionForm", ConversionForm())
        model.addAttribute("kotlin", "class Example")
        return "conversion"
    }
}
```

There's a lot of magic going on here.

Behind the scenes, Spring will route HTTP requests to our `displayConversionForm` method, which adds the generated Kotlin source as an attribute of a `Model`.

The method then returns a view, which corresponds to a HTML template stored under `src/main/resources/static/templates`:

```
<html>
  <head></head>
  <body>
    <textarea th:text="${kotlin}"></textarea>
  </body>
</html>
```

The HTML template is then processed by [Thymeleaf](https://www.thymeleaf.org/), which binds the `Model` to the `View` by evaluating any [expressions](https://docs.spring.io/spring/docs/4.3.12.RELEASE/spring-framework-reference/html/expressions.html) in the `th`. The result is returned as an HTTP response to the user:

```
<html>
  <head></head>
  <body>
    <textarea text="class Example"></textarea>
  </body>
</html>
```

### Adding a POST request mapping
We're getting slightly ahead of ourselves here, as the generated Kotlin can't be displayed until a user submits their JSON input. Therefore we need to display a form to the user, which will POST the JSON to our `/` endpoint:

```
<form id="jsonForm"
      th:action="@{/}"
      th:object="${conversionForm}"
      method="post"
      onsubmit="return validateForm()">
  <textarea maxlength="10000"
            placeholder="Paste JSON here..."
            th:field="*{json}"></textarea>
    <input type="reset" value="Reset"/>
    <input type="submit" value="Convert"/>
</form>
```

You may have noticed that the HTML form binds the `conversionForm` attribute in our previous method. When a POST request is submitted, the `conversionForm` method parameter will contain the text entered into the `field` attribute in our `<textarea>` element:

```
@PostMapping("/")
fun convertToKotlin(model: Model,
                    @ModelAttribute conversionForm: ConversionForm): String {
    val os = ByteArrayOutputStream()
    Kotlin2JsonConverter().convert(conversionForm.json, os, ConversionArgs())
    model.addAttribute("kotlin", String(os.first.toByteArray()))
    return displayConversionForm(model)
}
```

### Building a pretty HTML page
We'll skip a few steps here that include adding front-end validation, download/copy options, and slaying CSS dragons. If you're interested in how this functionality works, I'd encourage you to browse through the [Spring module](https://github.com/fractalwrench/json-2-kotlin/tree/master/spring/src/main) of the project.

## Deploying a Kotlin Spring Boot app to AWS Elastic Beanstalk
We're going to deploy to AWS using the [free tier](https://aws.amazon.com/free/), which meets the needs of most hobby projects. Some level of familiarity with AWS is assumed from here on out, but here's a quick refresher of the services we'll use:

- [Elastic Beanstalk](https://aws.amazon.com/elasticbeanstalk/): Controls all the AWS services required to build a scalable application.
- [EC2](https://aws.amazon.com/ec2/): Provides on-demand containers which run our JVM application in the cloud.
- [Elastic Load Balancer](https://aws.amazon.com/elasticloadbalancing/): Directs traffic between EC2 instances depending on how busy they are.
- [Route 53](https://aws.amazon.com/route53/): Allows us to register a domain name and point the DNS at an Elastic Beanstalk application.

### Building a deployable JAR
The first step we'll take is to update our JAR to contain the necessary information to run, as we did for our command-line application:

```
jar {
    baseName = 'json2kotlin'
    version = '0.1.0'
    manifest {
        attributes 'Main-Class': 'AppKt'
    }
    from { configurations.compile.collect {
      it.isDirectory() ? it : zipTree(it) }
    }
}
```

We'll also want to add [Spring Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/production-ready-enabling.html) as a dependency, as it exposes several endpoints that provide useful information for devops.

```
compile("org.springframework.boot:spring-boot-starter-actuator")
```

Finally, we'll need to update our server port in `application.properties` so that it can communicate with the load balancer:

```
server.port=8888
```

### Registering a domain
The next step is to register a domain name, in this case `json2kotlin.co.uk`, by following the [AWS guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/registrar.html).

After the rest of setup is completed, we'll [configure a hosted zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-beanstalk-environment.html#routing-to-beanstalk-environment-create-alias-procedure
), which routes requests to our Elastic Beanstalk environment.

### Setting up an Elastic Beanstalk environment
We now need to setup an Elastic Beanstalk environment, which can be achieved by following this [very helpful blog](https://aws.amazon.com/blogs/devops/deploying-a-spring-boot-application-on-aws-using-aws-elastic-beanstalk/) from AWS. `./gradlew bootRepackage` will generate a JAR of our Spring Boot application.

Our application will use a load balancer, which will automatically scale up EC2 instances in the face of heavy traffic.

It is *vital* that we setup a health check, as otherwise the load balancer will assume that all the instances are unhealthy, and all our requests will timeout. Fortunately, Spring Actuator contains a ready-made `/health` endpoint, so we'll tell AWS to use this.


## Setup crash reporting with Bugsnag
There are probably a few bugs lurking in our application, so our next step is to add an error-detection SDK that reports any uncaught exceptions that occur in the wild. I chose [Bugsnag](https://www.bugsnag.com/) for this task, because:

- It supports both Kotlin and JavaScript, as well as [most languages under the sun](https://www.bugsnag.com/platforms/)
- It's free for open-source/small projects
- My JavaScript is awful and I'm anticipating a lot of browser compatibility errors

_(Full disclaimer, I work for Bugsnag, so you can blame me if anything goes wrong)_

## The end result
The [final web application is available here](http://json2kotlin.co.uk/), or alternatively you can grab the command-line tool from [Github](https://github.com/fractalwrench/json-2-kotlin/releases/latest).

You can also browse the [complete source of this project](https://github.com/fractalwrench/json-2-kotlin) on GitHub. At less than 1000 lines of code, this would be a nice project to wrap your head around if you're looking to submit pull requests, issues, or just general feedback!

## Thank You
I hope you've enjoyed learning about Kotlin source generation, and will sleep easy at night in the knowledge that you'll never have to write data classes by hand again.

If you have any questions, feedback, or would like to suggest a topic for me to write about, please [get in touch via Twitter](https://twitter.com/fractalwrench)!
