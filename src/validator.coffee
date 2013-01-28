_ = require('underscore')
yaml = require('js-yaml')
utils = require('./utils')
async = require('async')
createSchema = require('json-gate').createSchema

# Convert a swagger type to a json-gate type.
#
# @param swaggerType [String] type found in swagger descriptor
# @param parameter [String] parameter name, for understandabe errors
# @param allowMultiple [Boolean] true if this parameter may have multiple values
# @param models [Object] associative array containing all possible models, model id used as key.
# @return the corresponding json-gate type.
# @throws an exception if the swagger type has no json-gate equivalent
convertType = (swaggerType, parameter, allowMultiple, models) ->
  unless swaggerType?
    throw new Error("No type found for parameter #{parameter}")
  # manage uninon types: may be a primitive, name of a model, or an anonymous model
  if _.isArray(swaggerType)
    return _.map(swaggerType, (type, i) ->
      if _.isObject(type)
        # anonymous model: register it inside models with a generated name
        id = utils.generate()
        type.id = id
        delete type.type
        swaggerType[i] = id
        models[id] = type
        type = id
      return convertType(type, parameter, allowMultiple, models)
    )

  lowerType = swaggerType.toLowerCase()
  type = null
  if allowMultiple
    type = 'array';
  else 
    switch lowerType
      when 'int', 'long', 'integer' then type = 'integer'
      when 'float', 'double', 'number' then type = 'number'
      when 'string', 'boolean', 'array', 'any', 'null', 'object' then type = lowerType
      when 'byte', 'file' then type = 'file'
      else
        if swaggerType of models
          type = 'object';
        else
          throw new Error("Unsupported type#{if parameter? then " for parameter #{parameter}" else ''}: #{swaggerType}")
  return type

# Convert a swagger model to a json-gate model.
# The swagger model references are resolved, and `allowableValues` are converted to `enum` or `min` + `max`.
#
# @param models [Object] associative array containing all possible models, model id used as key.
# @param model [Object] the converted model
# @param _stack: [Array] internal usage: _stack to avoid circualr dependencies
# @return the corresponding json-gate schema
# @throws an error if a circular reference is detected
convertModel = (models, model, _stack) ->
  result = {
    properties: {}
    additionalProperties: if _.isObject(model.additionalProperties) then model.additionalProperties else false
  }
  _stack ?= []
  # track circular references
  if model.id?
    if -1 isnt _stack.indexOf(model.id)
      _stack.push(model.id)
      throw new Error("Circular reference detected: #{_stack.join(' > ')}")
    _stack.push(model.id)

  # copy properties of the swagger model into the json-gate model
  _.extend(result.properties, model.properties)
  # perform property level conversion
  for name, prop of result.properties
    val = _.extend(prop, model.properties[name])
    # convert allowableValues
    if val.allowableValues?.valueType?
      switch val.allowableValues.valueType.toLowerCase()
        when 'range'
          val.minimum = val.allowableValues.min
          val.maximum = val.allowableValues.max
          delete val.allowableValues
        when 'list'
          val.enum = val.allowableValues.values
          delete val.allowableValues

    # resolve references
    ltype = if _.isString(val.type) then val.type.toLowerCase() else ''
    if val.type of models
      # type is a model id
      _.extend(val, convertModel(models, models[val.type], _stack))
      val.type = 'object'
    else if ltype in ['list', 'set', 'array'] and val.items?.$ref?
      # for lists, sets and arrays, items.$ref hold the referenced model id
      _.extend(val.items, convertModel(models, models[val.items.$ref], _stack))
      delete val.items.$ref
      val.type = 'array'
    else if ltype is 'object'
      # recursive properties
      _.extend(val, convertModel(models, val, _stack))
    else
      # convert primitive type
      val.type = convertType(val.type, null, false, models)
  
  return result

# Parse the descriptor to extract an associative array with known api routes (Express path used as key).
# For a given route, an associative array of known methods (upper case Http method names as key) contains 
# the expected parameters and body (for PUT and POST methods), as an array of parameterSpec.
# The descriptor content is supposed to have been previously validated by the generator middleware
#
# @param descriptor [Object] Swagger descriptor (Json).
# @return the analyzed routes.
analyzeRoutes = (descriptor) ->
  routes = {}
  for resource in descriptor.apis
    for api in resource.apis

      # Store a route for this api.
      route = {};
      routes[utils.pathToRoute(api.path)] = route;
      # Store a verb for this operation, unless no parameter defined
      for operation in api.operations when operation?.parameters?.length
        verb = []
        route[operation.httpMethod.toUpperCase()] = verb

        for spec in operation.parameters
          allowMultiple = spec.allowMultiple is true

          # Prepare json-schema to let json-gate validate the parameter
          schema =
            type: convertType(spec.dataType, spec.name, allowMultiple, descriptor.models)
            required: spec.required is true

          if spec.name?
            schema.title = spec.name;
          
          if spec.description?
            schema.description = spec.description;
          
          if schema.type is 'object'
            _.extend(schema, convertModel(descriptor.models, if spec.properties then spec else descriptor.models[spec.dataType]))
          
          # manager possible values interval
          if spec.allowableValues?.valueType?
            switch spec.allowableValues.valueType.toLowerCase()
              when 'range'
                schema.minimum = spec.min
                schema.maximum = spec.max
              when 'list'
                schema.enum = spec.values

          if allowMultiple
            schema.items = _.clone(schema)
            schema.items.type = convertType(spec.dataType, spec.name, false, descriptor.models)
            delete schema.items.title
            delete schema.items.description

          verb.push(
            kind: spec.paramType.toLowerCase()
            name: spec.name
            schema: createSchema(schema)
          )
  return routes


# Performs validation of the incoming request against the expected specification.
# The generator middleware **must** be used before this validator middleware.
# It will register the validated routes, and check the descriptor format.
# Only the routes specified inside the descriptor are validated, other routes are ignored.
#
# @param req [Object] the incoming request
# @param path [String] the matched route path
# @param specs [Array] an array of awaited parameters
# @param next [Function] express next processing function
# @throws an error if any of the awaited parameters or body is missing, misformated, or invalid regarding the specification
validate = (req, path, specs, next) ->
  # casted parameters
  req.input = {}
  # path parameter extraction will be performed later by express: we must perform it ourselves
  pathParamsNames = {}
  i = 0
  # create a regular expression to extract path parameters and isolate their names
  regex = new RegExp(path.replace(/:([^\/]+)/g, (match, key) ->
    pathParamsNames[key] = ++i
    return '([^\/]*)'
  ))

  process = () ->
    # validates all parameter in parrallel
    async.forEach(specs, (spec, done) ->
      type = spec.schema.schema.type
      value = null
      errPrefix = null

      switch spec.kind 
        when 'query'
          value = req.query[spec.name]
          errPrefix = "query parameter #{spec.name}"
        when 'header'
          value = req.headers[spec.name]
          errPrefix = "header #{spec.name}"
        when 'path'
          # extract the parameter value: 
          match = req.path.match(regex)
          value = match[pathParamsNames[spec.name]]
          if value
            value = decodeURIComponent(value)
          errPrefix = "path parameter #{spec.name}"
        when 'body'
          errPrefix = "body parameter #{spec.name}"
          if spec.name
            # named parameter: take it from parsed body, or from part
            if req.files and spec.name of req.files
              value = req.files[spec.name]
              # specific case of files: do not validate with json-gate
              return done(if type isnt 'byte' then "#{errPrefix} must is a file when it should be a #{type}");
            else
              value = req.body[spec.name]
              if type is 'byte'
                # do not accept body part if waiting for a file
                return done("#{errPrefix} must is a #{type} when it should be a file")
          else
            errPrefix = 'body'
            # unamed parameter: take all body
            value = req.body
        else
          throw new Error("unsupported parameter type #{spec.kind}")

      if type is 'array'
        # multiple values awaited
        if value isnt undefined
          value = if _.isArray(value) then value else if value then value.split(',') else value
          type = spec.schema.schema.items.type
          value = _.map(value, (v) -> return utils.cast(type, v))

      else
        # performs casting
        try
          value = utils.cast(type, value)
        catch err
          # Json error
          return done("#{errPrefix} #{err.message}")

      # validate single value
      spec.schema.validate(value, (err) ->
        if err?
          # wrap error with understandable message.
          err.message = "#{errPrefix} #{err.message.replace(/^JSON object /, '')}"
        else
          # enrich request
          unless spec.kind is 'body'
            req.input[spec.name] = value
          else
            # or body
            if spec.name?
              req.body[spec.name] = value
            else
              req.body = value
        done(err)
      )
    
    , next)

  # body parsing, if incoming request is not json, multipart of form-urlencoded
  unless req.is('json') or req.is('application/x-www-form-urlencoded') or req.is('multipart/form-data')
    # by default, no body
    delete req.body
    # TODO, set request encoding to the incoming charset or to utf8 by default
    req.on('data', (chunk) ->
      if(!req.body)
        req.body = ''
      req.body += chunk
    )

    # only process raw body at the end.
    return req.on('end', process)
  process()

# Validator function.
# Analyze the API descriptor to extract awaited parameters and bodiy
# When the corresponding Api is executed, validates the incoming request against the expected parameters and body, 
# and trigger comprehensive errors
#
# @param app [Object] the enriched Express application.
module.exports = (app) ->
  # validates inputs
  unless app?.handle and app?.set?
    throw new Error('No Express application provided')

  unless app.descriptor?
    throw new Error('No Swagger descriptor found within express application. Did you use swagger.generator middleware ?')

  routes = {}
  # analyze the descriptor
  try
    routes = analyzeRoutes(app.descriptor)
  catch err
    throw new Error("Failed to analyze descriptor: #{err.toString()}\n#{err.stack}")

  # Express middleware for validating incoming request.
  return (req, res, next) ->
    # first get the matching route
    route = req.app._router.matchRequest(req)
    # only for known urls and methods
    if route and route.path of routes and req.method.toUpperCase() of routes[route.path]
      return validate(req, route.path, routes[route.path][req.method.toUpperCase()], next)

    next()