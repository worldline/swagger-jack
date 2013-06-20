# Swagger for Express
[![Build Status](https://travis-ci.org/feugy/swagger-jack.png)](https://travis-ci.org/feugy/swagger-jack)


[Swagger](http://developers.helloreverb.com/swagger/) is a specification and complete framework implementation for describing, producing, consuming, and visualizing RESTful web services.

It provides:

* _specification_: to write descriptors of your API
* _tools_: based on this descriptors: friendly GUI for documentation, client libraries...

**Swagger-Jack** is a nodeJS modules that implements the swagger specification and offers you three middlewares to:

1. _generate_ your routes from a swagger descriptor, binding them to your own controller functions
2. _validate_ all the API inputs (query parameter, headers, bodies...)
3. report _errors_ in a consistent way


## How can I use it ?

First, get the module, by referencing it inside your package.json:

```js
  "dependencies": {
    "express": "3.1.0",
    "swagger-jack": "1.0.0"
  }
```

Then, when creating your Express application, import and configure the two middlewares:

```js
  var express = require('express'),
      swagger = require('swagger-jack');

  var app = express();
  
  app.use(express.bodyParser())
    .use(express.methodOverride())
    .use(swagger.generator(app, {
      // general descriptor part
      apiVersion: '2.0',
      basePath: 'http://my-hostname.com/api'
    }, [{
      // descriptor of a given resource
      api: {
        resourcePath: '/user'
        apis: [{
          path: '/user/'
          operations: [{
            httpMethod: 'POST',
            nickname: 'create'
          }, {
            httpMethod: 'GET',
            nickname: 'list'

          }]
        }]
      },
      // controller for this resource
      controller:
        create: function(req, res, next) {
          // create a new user...
        },
        list: function(req, res, next) {
          // list existing users...
        }
    }])
    .use(swagger.validator(app))
    .use(swagger.errorHandler())
  
  app.get "/api/unvalidated", function(req, res, next) {
    // not documented not validated
  }
  app.listen(8080);
```


### Generator middleware

Generator takes the following parameters:

1. your express application,
1. a general descriptor object (which is totally not constraint: put whatever you need in it), 
1. an array of "resources",
1. optionnal `options` (see below)

A "resource" is composed by a *resource* descriptor, and the corresponding code (what we called *controller*).

The middleware will automatically add to your express application the routes found inside the *resource* descriptor, and bound them to the provided *controller* (it uses the `nickname` attribute from the descriptor to bound the right controller's method).

In the previous example, two routes are created:

1. `POST /api/user/` to create a user (controller method `create()`)
1. `GET /api/user/` to list existing users (controller method `list()`)

As explained in the swagger specification, the descriptor `basePath` attribute is used as url prefix for every resources and their operations. 
You should not repeat it in resources paths and apis path.

The `resourcePath` in resource object is intended to be repeated in every api path.

If you just want to document some existing routes, just provide a resource descriptor, and no associated controller. 
Of course, no validation will be provided.

You can still register routes and middleware within your application, like you've used to. 
But they will not be documented nor validated.

The following options are available:

- descPath `String`: path of generated swagger descriptor. Must contain leading slash. Default to `/api-docs.json`, with `basePath` used as prefix.


### Validator middleware

Validator will analyze the declared parameters of your descriptor, and validate the input.
It will handle parameter casting, range validation and declared model compliance (thank to the excellent [json-gate](https://github.com/oferei/json-gate)).

All casted values (except body parameters) are available inside the controller methods with the `req.input` associative array.
No matter if parameter is from path, query or header: it will be present inside `req.input`.

You can still use the Express original function (`req.params`, `req.param()`, `req.headers`...), but beware: values are just strings.


Bodies are also validated, but parsing is done by express's bodyParser middleware: it takes in account json and multipart bodies. For other bodies kind, validator will read itself the body, and perfoms casting.

**Caution** You *must* use `express.bodyParser()` *before* `swagger.validator`. 

**Caution** You *can't* read the body by yourself (with *data*/*end* request events) for routes declared with `swagger.validator`. 

If you do not need validation, no problem: just remove the validator middleware.


### Error middleware

Validation errors (and your custom business errors) are handled by the error middleware.
It uses the express's error mecanism: invoke the next() method with an argument.

Weither it's a string or an object, it will be serialized into a json response with an http status (500 by default).

For example:

```js
  use(swagger.generator(app, { 
    // general descriptor ... 
  }, [{
    api: // resource descriptor...
    controller: {
      create: function(req, res, next) {
        if (// error check...) {
          var err = new Error('forbidden !');
          err.status = 403;
          return next(err);
        }
        // process ...
      }
    }
  }]))
```

Input validation errors are reported the same way.

You may not use the error middleware and provide your own.


### Power-tip !

Use js-yaml to store your descriptor in a separate file, and split your code into other controller modules:

```js
  var express = require('express'),
      swagger = require('swagger-jack'),
      yaml = require('js-yaml');
  
  var app = express();
  
  app.use(express.bodyParser())
    .use(express.methodOverride())
    .use(swagger.generator(app, 
      require('/api/general.yml'), 
      [{
        api: require('/api/users.yml'),
        controller: require('/controller/users')
      },{
        api: require('/api/commands.yml'),
        controller: require('/controller/commands')
      }])
    .use(swagger.validator(app))
    .use(swagger.errorHandler())
  
  app.listen(8080);
```


### Really hacky power-tip

For very specific cases, it's possible to use the validation function without request.

For example:

```js
  // init your application as usual
  var app = express();
  var validator; // don't init yet ! the generator was not invoked
  app.use(express.bodyParser())
    .use(express.methodOverride())
    .use(swagger.generator(app,
      ...
    , [{
      api: require('./fixtures/validatedApi.yml'),
      controller: require('./controller')
    ])
    // keep the validator middleware.
    .use(validator = swagger.validator(app))
    .use(swagger.errorHandler())

  ...

  // manually validate a "fake" url
  var casted = {};
  var url = '/api/queryparams';
  // method, Express path, url, query, headers, body, casted, callback
  validator.validate('GET', url, url, {param1:"-2", param2:"5.5"}, {}, {}, casted, function(err) {
    if (err) {
      // handle validation errors
    } else {
      // you can use casted values safely.
    }
  });
```

You still need to use an Express application and to declare generator and validator middlewares.

Documentation for the `validate()` function can be found [in the source code](https://github.com/feugy/swagger-jack/blob/master/src/validator.coffee#L216)


## TODO How does it works ?

To be Done


## What about [swagger-node-express](https://github.com/wordnik/swagger-node-express) ?

Reverb folks (the ones who made Swagger) provide an express module to enhance your Express application by returning the swagger descriptor.

It provides a quick way to describe your code in Json and register your express routes.
To me it's very handy for a start, but has three problems:

1. your descriptor is inside your code, and splitted into parts, which makes it not easy to read
2. you do not use any more the marvellous express functions, but the one provided by swagger-node-epxress
3. it does not use the descriptor to automatize input validation, and you still have to cast and check your parameters


## Changelog

### 1.6.2

- fix mising leading / on generated descriptor, when using non empty basePath  ([details](https://github.com/feugy/swagger-jack/issues/19))

### 1.6.1

- do not prepend basePath to api's path with swagger root descriptor ([details](https://github.com/feugy/swagger-jack/issues/19))
- enforce validator on api declared with basePath

### 1.6.0

- fix basePath handling, be more strict on operation path validation ([details](https://github.com/feugy/swagger-jack/issues/10))
- allow validation utilities to be used without Express's request object ([details](https://github.com/feugy/swagger-jack/issues/11))

### 1.5.0

- more strict check for mandatory data inside descriptors
- test missing models that are referenced in apis

### 1.4.2

- only expose relevant models inside the swagger descriptor for a given resource ([details](https://github.com/feugy/swagger-jack/pull/9))
- be less restrictive on model content ([details](https://github.com/feugy/swagger-jack/pull/8))

### 1.4.1

- check model id unicity to avoid erasure
- allow apis to contain unwired resources. Allow to document handy-managed routes

### 1.4.0

- use CakeFile for better build/test portability
- enhance documentation
- allow swagger descriptor path customization ([details](https://github.com/feugy/swagger-jack/issues/6))

### 1.3.1

- fix when req.body is undefined ([details](https://github.com/feugy/swagger-jack/pull/4))

### 1.3.0

- allow anonymous complex bodies to have multiple occurences 

### 1.2.0

- allow body parameter to be facultative
- fix packaging issues with coffee. Only contributors need to install it globally (as well as mocha)

### 1.1.0

- be more strict regarding multipart management 

### 1.0.1

- add some test on multipart/related body parsing 
- enhance documentation
- use [Travis CI](https://travis-ci.org/feugy/swagger-jack)


## License (MIT)

Swagger is shipped with an MIT Licence. 

Copyright (c) 2013 Atos Worldline

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


--------
### Addendum: what's with that name ?

We looked for a fun and yet eloquent name. But swagger.js was already used.
[Jack Swagger](http://www.wwe.com/superstars/jackswagger) is an american catch superstar, and we never heard about him before, but it perfectly fits your naming goals :)
