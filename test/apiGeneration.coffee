express = require('express')
assert = require('chai').assert
request = require('request')
http = require('http')
swagger = require('../')
pathUtils = require('path')
_  = require('underscore')

describe 'API generation tests', ->
  server = null
  host = 'localhost'
  port = 8090
  root = '/api'

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
      swagger.generator express(), {}, [{}]
    , /Resource must contain 'api' and 'controller' attributes/

  it 'should fail if on missing resource path', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api: {}
        controller: require './fixtures/sourceCrud'
      ]
    , /Resource without path/

  it 'should fail if on missing api path', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api:
          resourcePath: '/test'
          apis: [{}]
        ,
        controller: require './fixtures/sourceCrud'
      ]
    , /api without path/

  it 'should fail if on unsupported operation in descriptor', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api:
          resourcePath: '/test'
          apis: [
            path: '/'
            operations: [
              httpMethod: 'TOTO'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /operation TOTO is not supported/

  it 'should fail if on unknown nickname in descriptor', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api:
          resourcePath: '/test'
          apis: [
            path: '/'
            operations: [
              httpMethod: 'GET'
              nickname: 'doNotExist'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /nickname doNotExist cannot be found in controller/

  it 'should fail if on missing nickname in descriptor', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api:
          resourcePath: '/test'
          apis: [
            path: '/'
            operations: [
              httpMethod: 'GET'
            ]
          ]
        controller: require './fixtures/sourceCrud'
      ]
    , /does not specify a nickname/

  it 'should fail if on duplicate parameters in descriptor', ->
    assert.throws ->
      swagger.generator express(), {}, [
        api:
          resourcePath: '/test'
          apis: [
            path: '/'
            operations: [
              httpMethod: 'GET'
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
          .use(swagger.generator app, 
            apiVersion: '1.0',
            basePath: root
          , [
            api: require './fixtures/sourceApi.yml'
            controller: require './fixtures/sourceCrud'
          ,
            api: require './fixtures/streamApi.yml'
            controller: require './fixtures/sourceCrud'
          ])
      catch err
        return done err.stack

      server = http.createServer app
      server.listen port, host, done

    after (done) ->
      server.close()
      done()

    it 'should generated API be available', (done) ->
      # when using the generated APIs
      request.post
        url: 'http://'+host+':'+port+'/source'
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
          url: 'http://'+host+':'+port+'/source'
          json: true
        , (err, res, body) ->
          return done err if err?
          # then the API is working as expected
          assert.equal res.statusCode, 200, 'get source list API not available'
          assert.deepEqual body, {size:1, total:1, from:0, hits:[source]}
          source.desc = 'hou yeah'
          request.put
            url: 'http://'+host+':'+port+'/source/'+source.id
            json: true
            body: source
          , (err, res, body) ->
            return done err if err?
            # then the API is working as expected
            assert.equal res.statusCode, 200, 'put source API not available'
            assert.deepEqual body, source
            request.get
              url: 'http://'+host+':'+port+'/source/'+source.id
              json: true
            , (err, res, body) ->
              return done err if err?
              # then the API is working as expected
              assert.equal res.statusCode, 200, 'get source API not available'
              assert.deepEqual body, source
              assert.equal body.desc, 'hou yeah'
              request.del
                url: 'http://'+host+':'+port+'/source/'+source.id
                json: true
              , (err, res, body) ->
                return done err if err?
                # then the API is working as expected
                assert.equal res.statusCode, 204, 'delete source API not available'
                request.get
                  url: 'http://'+host+':'+port+'/source'
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
        url: 'http://'+host+':'+port+'/api-docs.json'
        json: true
      , (err, res, body) ->
        return done err if err?
        # then a json file is returned
        assert.equal res.statusCode, 200
        assert.deepEqual body,
          apiVersion: '1.0',
          basePath: '/api',
          apis: [
            path:"/api-docs.json/source"
          ,
            path:"/api-docs.json/stream"
          ]
          models: {}

        # when requesting the API description details
        request.get
          url: 'http://'+host+':'+port+'/api-docs.json/source'
          json: true
        , (err, res, body) ->
          return done err if err?
          # then a json file is returned
          assert.equal res.statusCode, 200
          assert.deepEqual body,
            apiVersion: '1.0'
            basePath: '/api'
            resourcePath: '/source'
            apis: [
              path: '/source'
              operations: [
                httpMethod: 'GET'
                nickname: 'list'
              ,
                httpMethod: 'POST'
                nickname: 'create'
              ]
            ,
              path: '/source/{id}'
              operations: [
                httpMethod: 'GET'
                nickname: 'getById'
              ,
                httpMethod: 'PUT'
                nickname: 'update'
              ,
                httpMethod: 'DELETE'
                nickname: 'remove'
              ]
            ]
          done()