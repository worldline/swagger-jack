# Swagger for Express

[Swagger](http://developers.helloreverb.com/swagger/) is a specification and complete framework implementation for describing, producing, consuming, and visualizing RESTful web services.

It provides:

* _specification_: to write descriptors of your API
* _tools_: based on this descriptors: friendly GUI for documentation, client libraries...

This nodeJs modules implements the swagger specification and offers you two middlewares to:

1. _generate_ your routes from a swagger descriptor, binding them to your own controller functions
2. _validate_ all the API inputs (query parameter, headers, bodies...)

## How can I use it ?

First, get the module, by referencing it inside your package.json:

```js
  "dependencies": {
    "express": "3.1.0",
    "swagger": "1.0.0"
  }
```

Then, when creating your Express application, import and configure the two middlewares:

```js
  var express = require('express'),
      swagger = require('swagger');

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
          path: '/api/user/'
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
Generator takes a general descriptor path (which is totally not constraint: put whatever you need in it), and an array of "resources".

A "resource" is composed by a resource descriptor, and the corresponding code.

The middleware will automatically add to your express application the routes found inside the descriptor, and bound them to the provided controller (it uses the `nickname` attribute). In this example, two routes are created:

1. `POST /api/user/` to create a user (controller method `create()`)
1. `GET /api/user/` to list existing users (controller method `list()`)

You can still register routes and middleware within your application, but they will not be documented nor validated. 

### Validator middleware

Validator will analyze the declared parameters of your descriptor, and validate the input.
It will handle parameter casting, range validation and declared model compliance (thank to the excellent [json-gate](https://github.com/oferei/json-gate)).

All casted values (except body parameters) are available inside the controller methods with the `req.input` associative array.
No matter if parameter is from path, query or header: it will be present inside `req.input`.

But you can still use the Express original function (beware: values are just strings).

Body is just validated, as it was already parsed into json by the `express.bodyParser` middleware.

If you do not need validation, no problem: just remove the validator middleware.

### Error middleware

Validation errors (and your custom business errors) are handled by the error middleware.
It uses the express's error mecanism: invoke the next() method with an argument.

Weither it's a string or an object, it will be serialized into a json response with an http status (500 by default).

For example:
```js
  .use(swagger.generator(app, 
      { // general descriptor ... }
      [{
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
      }])
```
Input validation errors are reported the same way.

You may not use the error middleware and provide your own.

### Power-tip !

Use js-yaml to store your descriptor in a separate file, and split your code into other controller modules:
```js
  var express = require('express'),
      swagger = require('swagger'),
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

## TODO How does it works ?

To be Done

## What about [swagger-node-express](https://github.com/wordnik/swagger-node-express) ?

Reverb folks (the ones who made Swagger) provide an express module to enhance your Express application by returning the swagger descriptor.

It provides a quick way to describe your code in Json and register your express routes.
To me it's very handy for a start, but has three problems:

1. your descriptor is inside your code, and splitted into parts, which makes it not easy to read
2. you do not use any more the marvellous express functions, but the one provided by swagger-node-epxress
3. it does not use the descriptor to automatize input validation, and you still have to cast and check your parameters


## License

Swagger is shipped with an MIT Licence. 

Copyright (c) 2013 Damien Feugas

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.