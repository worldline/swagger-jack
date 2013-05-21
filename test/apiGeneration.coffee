require 'js-yaml'
express = require 'express'
assert = require('chai').assert
request = require 'request'
http = require 'http'
swagger = require '../'
pathUtils = require 'path'
_  = require 'underscore'

describe 'API generation tests', ->
  server = null
  host = 'localhost'
  port = 8090
  root = "http://#{host}:#{port}/api"

  it 'should fail if no Express application is provided', ->
    assert.throws ->
      swagger.generator()
    , /^No Express application provided/

  it 'should fail if plain object is provided', ->
    assert.throws ->
      swagger.generator {}
    , /^No Express application provided/

  it 'should fail if no descriptor provided', ->
    assert.throws ->
      swagger.generator express()
    , /^Provided root descriptor is not an object/

  it 'should fail if no api or controller provided for a resource', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [{}]
    , /Resource must contain 'api' attribute/

  it 'should fail on missing resource path', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api: {}
        controller: require './fixtures/sourceCrud'
      ]
    , /Resource without path/

  it 'should fail on missing api path', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [{}]
        controller: require './fixtures/sourceCrud'
      ]
    , /api without path/

  it 'should fail on model without id', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [path: '/test/1'],
          models: Response: {}
        controller: require './fixtures/sourceCrud'
      ]
    , /Response not declared with the same id/

  it 'should fail on model with invalid id', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [path: '/test/1'],
          models: Response: id: 'Toto'
        controller: require './fixtures/sourceCrud'
      ]
    , /Response not declared with the same id/

  it 'should fail on model without properties', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [path: '/test/1'],
          models: Response1: id: 'Response1'
        controller: require './fixtures/sourceCrud'
      ]
    , /Response1 does not declares properties/

  it 'should not fail on model with properties', ->
    swagger.generator express(),
      apiVersion: '1.0'
      basePath: root
    , [
      api:
        resourcePath: '/test'
        apis: [path: '/test/1'],
        models:
          Response1:
            id: 'Response1'
            properties: name: type: 'string'
      controller: require './fixtures/sourceCrud'
    ]

  it 'should not fail on model with additionalProperties', ->
    swagger.generator express(),
      apiVersion: '1.0'
      basePath: root
    , [
      api:
        resourcePath: '/test'
        apis: [path: '/test/1'],
        models:
          Response1:
            id: 'Response1'
            additionalProperties: {}
      controller: require './fixtures/sourceCrud'
    ]

  it 'should not fail on model with items', ->
    swagger.generator express(),
      apiVersion: '1.0'
      basePath: root
    , [
      api:
        resourcePath: '/test'
        apis: [path: '/test/1'],
        models:
          Response1:
            id: 'Response1'
            items: type: 'string'
      controller: require './fixtures/sourceCrud'
    ]

  it 'should fail on model already defined', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [path: '/test/1'],
          models:
            Response2:
              id: 'Response2'
              properties:
                name:
                  type: 'String'
        controller: require './fixtures/sourceCrud'
      ,
        api:
          resourcePath: '/test2'
          apis: [path: '/test2/1'],
          models:
            Response2:
              id: 'Response2'
              properties:
                name:
                  type: 'String'
        controller: require './fixtures/sourceCrud'
      ]
    , /Response2 has already been defined/

  it 'should fail on unsupported operation in descriptor', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'TOTO'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /operation TOTO is not supported/

  it 'should fail on unsupported operation in descriptor', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'TOTO'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /operation TOTO is not supported/

  it 'should fail on missing basePath', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /basePath is mandatory/

  it 'should fail on missing apiVersion', ->
    assert.throws ->
      swagger.generator express(),
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /apiVersion is mandatory/

  it 'should fail on missing responseClass', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /responseClass is mandatory. If no result expected, responseClass should be void/

  it 'should fail on missing nickname in descriptor', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            responseClass: 'void'
            operations: [
              httpMethod: 'GET'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /does not specify a nickname/

  it 'should fail on duplicate parameters in descriptor', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
              ,
                name: 'p2'
              ,
                name: 'p3'
              ,
                name: 'p1'
              ,
                name: 'p4'
              ,
                name: 'p3'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /has duplicates parameters: p1,p3/

  it 'should fail on parameter (not body) without name', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                paramType: 'query'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /parameter with no name/

  it 'should fail on parameter without paramType', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /parameter p1 has no type/

  it 'should fail on unknown type parameter', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
                paramType: 'unkown'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /parameter p1 type unkown is not supported/

  it 'should fail on optionnal path parameter', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test/{p1}'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
                paramType: 'path'
                required: false
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /path parameter p1 cannot be optionnal/

  it 'should fail on path parameter with multiple values', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test/{p1}'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
                paramType: 'path'
                multipleAllowed: true
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /path parameter p1 cannot allow multiple values/

  it 'should fail on path parameter disclosure between path and parameter array', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test/{p1}/{p2}/{p3}'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
                paramType: 'path'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /declares 3 parameters in its path, and 1 in its parameters array/

  it 'should fail on path parameter name disclosure between path and parameter array', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test/{p1}/{p2}'
            operations: [
              httpMethod: 'GET'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                name: 'p1'
                paramType: 'path'
              ,
                name: 'p3'
                paramType: 'path'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /declares parameter p2 in its path, but not in its parameters array/

  it 'should fail on two anonymous body parameters', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'POST'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                paramType: 'body'
              ,
                paramType: 'body'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /has more than one anonymous body parameter/

  it 'should fail on body parameters for other than put and post', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/test'
            operations: [
              httpMethod: 'DELETE'
              responseClass: 'void'
              nickname: 'stat'
              parameters: [
                paramType: 'body'
              ]
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /operation DELETE does not allowed body parameters/

  it 'should fail on api path that do not math resource path', ->
    assert.throws ->
      swagger.generator express(),
        apiVersion: '1.0'
        basePath: root
      , [
        api:
          resourcePath: '/test'
          apis: [
            path: '/doh'
            operations: [
              httpMethod: 'GET'
              nickname: 'stat'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /Resource \/test has an api \/doh that did not match its own path/

  it 'should preserve swaggerVersion', (done) ->
    # given a server with api and custom descriptor path
    app = express()
    app.use(express.cookieParser())
      .use(express.methodOverride())
      .use(express.bodyParser())
      .use(swagger.generator(app,
        swaggerVersion: '1.0'
        apiVersion: '1.0'
        basePath: root
      , []))
    server = http.createServer app
    server.listen port, host, _.defer((err) ->
      return done err if err?
      # when requesting the API description details
      request.get(
        url: 'http://'+host+':'+port+'/api/api-docs.json'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          swaggerVersion: "1.0"
          apiVersion: '1.0'
          basePath: 'http://localhost:8090/api'
          apis: []
          models: {}
        server.close()
        done()
      )
    )

  it 'should customize the generated descriptor path', (done) ->
    # given a server with api and custom descriptor path
    app = express()
    app.use(express.cookieParser())
      .use(express.methodOverride())
      .use(express.bodyParser())
      .use(swagger.generator(app,
        apiVersion: '1.0'
        basePath: root
      , [
        api: require './fixtures/streamApi.yml'
        controller: stat: (req, res) -> res.json status: 'passed'
      ], descPath: '/my-desc'))
    server = http.createServer app
    server.listen port, host, _.defer((err) ->
      return done err if err?
      # when requesting the API description details
      request.get(
        url: 'http://'+host+':'+port+'/api/my-desc'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          apiVersion: '1.0'
          basePath: root,
          swaggerVersion: "1.1"
          apis: [
            path: 'my-desc/stream'
          ]
          models: {}
        server.close()
        done()
      )
    )

  it 'should allow wired and not wired resources', (done) ->
    # given a server with wired and not wired api
    app = express()
    app.use(express.cookieParser())
      .use(express.methodOverride())
      .use(express.bodyParser())
      .use(swagger.generator(app,
        apiVersion: '1.0'
        basePath: root
      , [
        api: require './fixtures/streamApi.yml'
        controller: stat: (req, res) -> res.json status: 'passed'
      ,
        api: require './fixtures/notwired.yml'
      ]))
    server = http.createServer app
    server.listen port, host, _.defer((err) ->
      return done err if err?
      # when requesting the API description details
      request.get(
        url: 'http://'+host+':'+port+'/api/api-docs.json'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          swaggerVersion: "1.1"
          apiVersion: '1.0'
          basePath: root
          apis: [
            path: 'api-docs.json/stream'
          ,
            path: 'api-docs.json/source'
          ]
          models: {}
        # then the unwired resource details are available
        request.get(
          url: 'http://'+host+':'+port+'/api/api-docs.json/source'
          json: true
        , (err, res, body) ->
          return done err if err?
          assert.deepEqual body,
            swaggerVersion: "1.1"
            apiVersion: '1.0'
            basePath: root
            apis: [
              path: '/source/stats'
              operations: [
                httpMethod: 'GET'
                responseClass: 'void'
              ]
            ],
            models: {},
            resourcePath: '/source'
          server.close()
          done()
        )
      )
    )

  describe 'given a configured server with complex models', ->
    app = null

    # given a started server
    before (done) ->
      app = express()
      app.use(express.cookieParser())
        .use(express.methodOverride())
        .use(express.bodyParser())
        .use(swagger.generator(app,
          apiVersion: '1.0'
          basePath: root
        , [{
          api: require './fixtures/addressApi.yml'
          controller: passed: (req, res) -> res.json status: 'passed'
        },{
          api: require './fixtures/complexApi.yml'
          controller: passed: (req, res) -> res.json status: 'passed'
        }]))
        # use validator also because it manipulates models
        .use(swagger.validator(app))
      server = http.createServer app
      server.listen port, host, _.defer(done)

    after (done) ->
      server.close()
      done()

    it 'should reference models be untouched', (done) ->
      # when requesting the API description details
      request.get
        url: 'http://'+host+':'+port+'/api/api-docs.json/address'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          swaggerVersion: "1.1"
          apiVersion: '1.0'
          basePath: root
          resourcePath: '/address'
          apis: [
            path: '/address'
            operations: [
              httpMethod: 'POST'
              responseClass: 'Address'
              nickname: 'passed'
              parameters: [
                dataType: 'Address'
                paramType: 'body'
                required: true
              ]
            ]
          ],
          models:
            Address:
              id: 'Address'
              properties:
                zipcode:
                  type: 'long'
                street:
                  type: 'string'
                city:
                  type: 'string'

            SomethingElse:
              id: 'SomethingElse'
              properties:
                name:
                  type: 'string'
        done()

  describe 'given a properly configured and started server', ->
    app = null

    # given a started server
    before (done) ->
      app = express()
      # configured to use swagger generator
      try
        app.use(express.cookieParser())
          .use(express.methodOverride())
          .use(express.bodyParser())
          .use(swagger.generator(app,
            apiVersion: '1.0'
            basePath: root
          , [
            api: require './fixtures/sourceApi.yml'
            controller: require './fixtures/sourceCrud'
          ,
            api: require './fixtures/streamApi.yml'
            controller: require './fixtures/sourceCrud'
          ]))
          # use validator also because it manipulates models
          .use(swagger.validator(app))
      catch err
        return done err.stack

      server = http.createServer app
      server.listen port, host, _.defer(done)

    after (done) ->
      server.close()
      done()

    it 'should generated API be available', (done) ->
      # when using the generated APIs
      request.post
        url: 'http://'+host+':'+port+'/api/source'
        json: true
        body:
          name: 'source 1'
      , (err, res, body) ->
        return done err if err?
        # then the API is working as expected
        assert.equal res.statusCode, 200, 'post source API not available'
        assert.isNotNull body.id
        assert.equal body.name, 'source 1'
        source = body
        request.get
          url: 'http://'+host+':'+port+'/api/source'
          json: true
        , (err, res, body) ->
          return done err if err?
          # then the API is working as expected
          assert.equal res.statusCode, 200, 'get source list API not available'
          assert.deepEqual body, {size:1, total:1, from:0, hits:[source]}
          source.desc = 'hou yeah'
          request.put
            url: 'http://'+host+':'+port+'/api/source/'+source.id
            json: true
            body: source
          , (err, res, body) ->
            return done err if err?
            # then the API is working as expected
            assert.equal res.statusCode, 200, 'put source API not available'
            assert.deepEqual body, source
            request.get
              url: 'http://'+host+':'+port+'/api/source/'+source.id
              json: true
            , (err, res, body) ->
              return done err if err?
              # then the API is working as expected
              assert.equal res.statusCode, 200, 'get source API not available'
              assert.deepEqual body, source
              assert.equal body.desc, 'hou yeah'
              request.del
                url: 'http://'+host+':'+port+'/api/source/'+source.id
                json: true
              , (err, res, body) ->
                return done err if err?
                # then the API is working as expected
                assert.equal res.statusCode, 204, 'delete source API not available'
                request.get
                  url: 'http://'+host+':'+port+'/api/source'
                  json: true
                , (err, res, body) ->
                  return done err if err?
                  # then the API is working as expected
                  assert.equal res.statusCode, 200
                  assert.deepEqual body, {size:0, from:0, total:0, hits:[]}
                  done()

    it 'should API description be available', (done) ->
      # when requesting the API description
      request.get
        url: 'http://'+host+':'+port+'/api/api-docs.json'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          swaggerVersion: "1.1"
          apiVersion: '1.0'
          basePath: root
          apis: [
            path:"api-docs.json/source"
          ,
            path:"api-docs.json/stream"
          ]
          models: {}

        # when requesting the API description details
        request.get
          url: 'http://'+host+':'+port+'/api/api-docs.json/source'
          json: true
        , (err, res, body) ->
          return done err if err?
          # then a json file is returned
          assert.equal res.statusCode, 200
          assert.deepEqual body,
            swaggerVersion: "1.1"
            apiVersion: '1.0'
            basePath: root
            resourcePath: '/source'
            apis: [
              path: '/source'
              operations: [
                httpMethod: 'GET'
                responseClass: 'void'
                nickname: 'list'
              ,
                httpMethod: 'POST'
                responseClass: 'void'
                nickname: 'create'
              ]
            ,
              path: '/source/{id}'
              operations: [
                httpMethod: 'GET'
                responseClass: 'void'
                nickname: 'getById'
              ,
                httpMethod: 'PUT'
                responseClass: 'void'
                nickname: 'update'
              ,
                httpMethod: 'DELETE'
                responseClass: 'void'
                nickname: 'remove'
              ]
            ]
            models: {}
          done()