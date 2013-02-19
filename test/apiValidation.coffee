require 'js-yaml'
express = require 'express'
assert = require('chai').assert
request = require 'request'
http = require 'http'
fs = require 'fs'
swagger = require '../'
pathUtils = require 'path'
_  = require 'underscore'

server = null
host = 'localhost'
port = 8090
root = '/api'

# test function: send an Http request (a get) and expect a status and a json body.
getApi = (name, params, headers, status, expectedBody, done, extra) ->
  request.get
    url: "http://#{host}:#{port+root}/#{name}"
    qs: params
    headers: headers
    json: true
  , (err, res, body) ->
    return done err if err?
    assert.equal res.statusCode, status, "unexpected status when getting #{name}, body:\n#{JSON.stringify body}"
    if _.isFunction extra
      extra res, body, done
    else
      assert.deepEqual body, expectedBody, "unexpected body when getting #{name}"
      done()

# test function: send an Http request (a post) and expect a status and a json body.
postApi = (name, headers, body, status, expectedBody, done) ->
  request.post
    url: "http://#{host}:#{port+root}/#{name}"
    headers: headers
    body: body
    encoding: 'utf8'
  , (err, res, body) ->
    return done err if err?
    try
      body = JSON.parse body
    catch err
      return done "failed to parse body:#{err}\n#{body}"
    assert.equal res.statusCode, status, "unexpected status when getting #{name}, body:\n#{JSON.stringify body}"
    assert.deepEqual body, expectedBody, "unexpected body when getting #{name}"
    done()

# test function: send an Http request (a post) and expect a status and a json body.
uploadFilePostApi = (name, file, status, done) ->
  req = request.post
    url: "http://#{host}:#{port+root}/#{name}"
  , (err, res, body) ->
    return done err if err?
    assert.equal res.statusCode, status, "unexpected status when getting #{name}, body:\n#{JSON.stringify body}"
    done()
  req.form().append 'file', fs.createReadStream file

# test function: send an Http request (a post multipart/form-data) and expect a status and a json body.
multipartApi = (name, formdata, parts, status, expectedBody, done) ->
  req =
    url: "http://#{host}:#{port+root}/#{name}",
    multipart: []
    encoding: 'utf8'
  if formdata
    req.headers = 
      'content-type': 'multipart/form-data'
  for part, i in parts
    req.multipart.push
      'content-disposition': "form-data; name=\"#{parts[i].name}\""
      body: parts[i].body 

  request.post req, (err, res, body) ->
    return done err if err?
    try
      body = JSON.parse(body);
    catch err
      return done "failed to parse body:#{err}\n#{body}"

    assert.equal res.statusCode, status, "unexpected status when getting #{name}, body:\n#{JSON.stringify body }"
    assert.deepEqual body, expectedBody, "unexpected body when getting #{name}"
    done()

describe 'API validation tests', ->

  it 'should fail if no express application is provided', ->
    assert.throws ->
      swagger.validator {}
    , /No Express application provided/

  it 'should fail if provided applicatino was not analyzed', ->
    assert.throws ->
      swagger.validator express()
    , /No Swagger descriptor found within express application/

  it 'should circular references be detected at statup', ->
    assert.throws ->
      app = express()
      # configured to use swagger generator
      app.use(express.bodyParser())
        .use(express.methodOverride())
        .use(swagger.generator app, {}, [
          api: require './fixtures/circular.yml'
          controller: returnBody: (req, res) -> res.json body:req.body
        ])
        .use(swagger.validator(app))
        .use(swagger.errorHandler())
    , /Circular reference detected: CircularUser > AddressBook > CircularUser/

  describe 'given a properly configured and started server', ->

    # given a started server
    before (done) ->
      app = express()
      # configured to use swagger generator
      app.use(express.bodyParser())
        .use(express.methodOverride())
        .use(swagger.generator app, {}, [
          api: require './fixtures/validatedApi.yml'
          controller:
            passed: (req, res) -> res.json status: 'passed'
            returnParams: (req, res) -> res.json req.input
            returnBody: (req, res) -> res.json body:req.body
        ])
        .use(swagger.validator app)
        .use(swagger.errorHandler())

      app.get "#{root}/unvalidated", (req, res) -> res.json status:'passed'

      server = http.createServer app
      server.listen port, host, done

    after (done) ->
      server.close()
      done()

    it 'should unvalidated API be available', (done) ->
      getApi 'unvalidated', null, {}, 200, {status:'passed'}, done

    it 'should validated API without parameters be available', (done) ->
      getApi 'noparams/18', null, {}, 200, {status:'passed'}, done

    describe 'given an api accepting query parameters', ->

      it 'should required be checked', (done) ->
        getApi 'queryparams', null, {}, 400, {message: 'query parameter param1 is required'}, done

      it 'should optionnal be allowed', (done) ->
        query = param1:10
        getApi 'queryparams', query, {}, 200, query, done

      it 'should integer and float be parsed', (done) ->
        query = param1:-2, param2:5.5
        getApi 'queryparams', query, {}, 200, query, done

      it 'should float not accepted as integer', (done) ->
        getApi 'queryparams', {param1:3.2}, {}, 400, {message: 'query parameter param1 is a number when it should be an integer'}, done

      it 'should empty string not accepted for a number', (done) ->
        getApi 'queryparams?param1=', null, {}, 400, {message: 'query parameter param1 is a string when it should be an integer'}, done

      it 'should string not accepted for a number', (done) ->
        getApi 'queryparams', {param1:'yeah'}, {}, 400, {message: 'query parameter param1 is a string when it should be an integer'}, done

      it 'should multiple parameter accept single value', (done) ->
        getApi 'queryparams', {param1:0, param3:true}, {}, 200, {param1: 0, param3: [true]}, done

      it 'should multiple parameter accept multiple value', (done) ->
        getApi 'queryparams?param1=0&param3=true&param3=false', {}, {}, 200, {param1: 0, param3: [true, false]}, done

      it 'should multiple parameter accept coma-separated value', (done) ->
        getApi 'queryparams', {param1:0, param3:'true,false'}, {}, 200, {param1: 0, param3: [true, false]}, done

      it 'should multiple be checked', (done) ->
        getApi 'queryparams', {param1:0, param3: [true, 'toto']}, {}, 400, {message: 'query parameter param3 property \'[1]\' is a string when it should be a boolean'}, done

      it 'should complex json be parsed', (done) ->
        obj =
          id: 10
          name: 'jean'
          addresses: [
            city: 'lyon'
            street: 'bd vivier merles'
            zipcode: 69006
          ] 
        getApi 'complexqueryparam', {user:JSON.stringify obj}, {}, 200, {user:obj}, done

    describe 'given an api accepting header parameters', ->

      it 'should required be checked', (done) ->
        getApi 'headerparams', null, {}, 400, {message: 'header param1 is required'}, done

      it 'should optionnal be allowed', (done) ->
        headers = param1: 10
        getApi 'headerparams', null, headers, 200, headers, done

      it 'should long and boolean be parsed', (done) ->
        headers = 
          param1: -2
          param2: false
        getApi 'headerparams', null, headers, 200, headers, done

      it 'should double not accepted as integer', (done) ->
        getApi 'headerparams', null, {param1:3.2}, 400, {message: 'header param1 is a number when it should be an integer'}, done

      it 'should empty string not accepted for a boolean', (done) ->
        getApi 'headerparams', null, {param1: 0, param2:''}, 400, {message: 'header param2 is a string when it should be a boolean'}, done

      it 'should string not accepted for a boolean', (done) ->
        getApi 'headerparams', null, {param1: 0, param2:'yeah'}, 400, {message: 'header param2 is a string when it should be a boolean'}, done

      it 'should multiple parameter accept single value', (done) ->
        getApi 'headerparams', null, {param1:0, param3:1.5}, 200, {param1: 0, param3: [1.5]}, done

      it 'should multiple parameter accept multiple value', (done) ->
        getApi 'headerparams', null, {param1:-2, param3: '2.1, -4.6'}, 200, {param1:-2, param3: [2.1, -4.6]}, done

      it 'should multiple be checked', (done) ->
        getApi 'headerparams', null, {param1:0, param3: [true, 1.5]}, 400, {message: 'header param3 property \'[0]\' is a string when it should be a number'}, done

      it 'should complex json be parsed', (done) ->
        obj =
          id: 10
          name: 'jean'
          addresses: [
            city: 'lyon'
            street: 'bd vivier merles'
            zipcode: 69006
          ] 
        getApi 'complexheaderparam', null, {user:JSON.stringify obj}, 200, {user:obj}, done

    describe 'given an api accepting path parameters', ->

      it 'should required be checked', (done) ->
        getApi 'pathparams', null, {}, 404, 'Cannot GET /api/pathparams', done

      it 'should int and boolean be parsed', (done) ->
        getApi 'pathparams/10/true', null, {}, 200, {param1:10, param2:true}, done

    describe 'given an api accepting body parameters', ->

      it 'should plain text body be parsed', (done) ->
        postApi 'singleintbody', {'Content-Type': 'text/plain'}, '1000', 200, {body:1000}, done

      it 'should plain text body be checked', (done) ->
        postApi 'singleintbody', {'Content-Type': 'text/plain'}, 'toto', 400, {message: 'body is a string when it should be an integer'}, done

      it 'should plain text body be required', (done) ->
        postApi 'singleintbody', {'Content-Type': 'text/plain'}, undefined, 400, {message: 'body is required'}, done

      it 'should primitive json body be parsed', (done) ->
        postApi 'singleintbody', {'Content-Type': 'application/json'}, '[-500]', 200, {body:-500}, done

      it 'should primitive json body be checked', (done) ->
        postApi 'singleintbody', {'Content-Type': 'application/json'}, '[true]', 400, {message: 'body is an array when it should be an integer'}, done

      it 'should primitive json body be required', (done) ->
        postApi 'singleintbody', {'Content-Type': 'application/json'}, undefined, 400, {message: 'Bad Request'}, done

      it 'should form-encoded body be required', (done) ->
        postApi 'multiplebody', {'Content-Type': 'application/x-www-form-urlencoded'}, undefined, 400, {message: 'body parameter param1 is required'}, done

      it 'should multi-part body be required', (done) ->
        multipartApi 'multiplebody', true, [{name: 'param', body: 'toto'}], 400, {message: 'body parameter param1 is required'}, done

      it 'should form-encoded body be parsed and casted down', (done) ->
        postApi 'multiplebody', {'Content-Type': 'application/x-www-form-urlencoded'}, 'param1=10&param2=true,false', 200, {body:{param1: 10, param2: [true, false]}}, done

      it 'should multi-part/related body not be parsed', (done) ->
        multipartApi 'multiplebody', false, [
            name: 'param1'
            body: '-5' 
          ,
            name: 'param2'
            body: 'false,true' 
          ], 400, {message: 'body parameter param1 is required'}, done

      it 'should multi-part/form-data body be parsed and casted down', (done) ->
        multipartApi 'multiplebody', true, [
            name: 'param1'
            body: '-5' 
          ,
            name: 'param2'
            body: 'false,true' 
          ], 200, {body:{param1: -5, param2: [false, true]}}, done

      it 'should multi-part body parameter be optionnal', (done) ->
        multipartApi 'multiplebody', true, [{name: 'param1', body: '0'}], 200, {body:{param1: 0}}, done

      it 'should complex json body be parsed', (done) ->
        obj =
          id: 10
          name: 'jean'
          addresses: [
            city: 'lyon'
            street: 'bd vivier merle'
            zipcode: 69006
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 200, {body:obj}, done

    describe 'given an api accepting model parameter', ->

      it 'should complex json body be checked', (done) ->
        obj =
          id: 11
          firstName: 'jean'
          lastName: 'dupond'
          addresses: [] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'firstName' is not explicitly defined and therefore not allowed"}, done

      it 'should complex json body refs be checked', (done) ->
        obj =
          id: 12
          name: 'Damien'
          addresses: [
            ville: 'lyon',
            street: 'bd vivier merle'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'addresses.[0].ville' is not explicitly defined and therefore not allowed"}, done

      it 'should range list value be checked', (done) ->
        obj =
          id: 12
          name: 'Damien'
          addresses: [
            city: 'strasbourd'
            zipcode: 67000
            street: 'bd vivier merle'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'addresses.[0].city' is not in enum"}, done

      it 'should range interval value be checked', (done) ->
        obj =
          id: 12
          name: 'Damien'
          addresses: [
            city: 'lyon'
            zipcode: 100000
            street: 'bd vivier merle'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'addresses.[0].zipcode' is 100000 when it should be at most 99999"}, done

      it 'should required attributes be checked', (done) ->
        obj =
          name: 'Damien'
          addresses: [
            city: 'lyon'
            zipcode: 69003
            street: 'bd vivier merle'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'id' is required"}, done

      it 'should primitive values be parsed', (done) ->
        obj =
          id: true
          name: 'Damien'
          addresses: [
            city: 'lyon'
            zipcode: 69003
            street: 'bd vivier merle'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'id' is a boolean when it should be an integer"}, done

      it 'should additionnal attribute not be allowed', (done) ->
        obj =
          id: 20
          name: 'Damien'
          addresses: [
            city: 'lyon'
            zipcode: 69003
            street: 'bd vivier merle'
            other: 'coucou'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'addresses.[0].other' is not explicitly defined and therefore not allowed"}, done

      it 'should optionnal attribute be allowed', (done) ->
        obj =
          id: 30
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 200, {body: obj}, done

      it 'should complex attribute not be checked', (done) ->
        obj =
          id: 20
          name: 'Damien'
          stuff:
            name: 10
          addresses: [
            city: 'lyon'
            zipcode: 69003
            street: 'bd vivier merle'
            other: 'coucou'
          ] 
        postApi 'complexbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'stuff.name' is an integer when it should be a string"}, done

      it 'should classical json-schema specification be usabled', (done) ->
        obj =
          id: 20
          other: 'Damien'
          phone: '000-1234'
        postApi 'jsonschemabody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 400, {message: "body property 'phone' does not match pattern"}, done

      it 'should any be accepted as type within models', (done) ->
        obj =
          id: 20
          name: []
          phone: '00000-1234'
        postApi 'jsonschemabody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 200, {body:obj}, done

      it 'should accept union type', (done) ->
        obj =
          id: 1
          name:
            first: 'jean'
            last: 'dupond'

        postApi 'unionbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 200, {body:obj}, (err) ->
          return done err if err?
          obj.name = 'jean dupond'
          postApi 'unionbody', {'Content-Type': 'application/json'}, JSON.stringify(obj), 200, {body:obj}, done


      it 'should accept upload file', (done) ->

        file = pathUtils.join __dirname, 'fixtures/circular.yml'
        uploadFilePostApi 'upload', file, 200, (err) ->
          return done err if err?
          done();

          # TODO post, put, delete, model list-set-arrays
