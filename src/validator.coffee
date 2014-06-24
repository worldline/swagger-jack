_ = require('underscore')
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
    type = 'array'
  else
    switch lowerType
      when 'int', 'long', 'integer' then type = 'integer'
      when 'float', 'double', 'number' then type = 'number'
      when 'string', 'boolean', 'array', 'any', 'null', 'object' then type = lowerType
      when 'byte', 'file' then type = 'file'
      else
        if swaggerType of models
          type = 'object'
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
  # copy the stack so that any "branch" of the validation tree is independent
  _stack = _stack.slice()
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
    _.extend(prop, model.properties[name])
    # convert allowableValues
    if prop.allowableValues?.valueType?
      switch prop.allowableValues.valueType.toLowerCase()
        when 'range'
          if prop.allowableValues.min? and prop.allowableValues.max?
            prop.minimum = prop.allowableValues.min
            prop.maximum = prop.allowableValues.max
            if prop.minimum > prop.maximum then throw new Error "min value should not be greater tha max value in #{name}"
          else
            throw new Error "missing allowableValues.min and/or allowableValues.max parameters for allowableValues.range of #{name}"
          delete prop.allowableValues
        when 'list'
          if prop.allowableValues.values? and _.isArray(prop.allowableValues.values)
            prop.enum = prop.allowableValues.values
          else
            throw new Error "allowableValues.values is missing or is not an array for allowableValues.list of #{name}"
          delete prop.allowableValues

    # resolve references
    ltype = if _.isString(prop.type) then prop.type.toLowerCase() else ''
    if prop.type of models
      # type is a model id
      _.extend(prop, convertModel(models, models[prop.type], _stack))
      prop.type = 'object'
    else if ltype in ['list', 'set', 'array'] and prop.items?.$ref?
      # for lists, sets and arrays, items.$ref hold the referenced model id
      _.extend(prop.items, convertModel(models, models[prop.items.$ref], _stack))
      delete prop.items.$ref
      prop.items.type = 'object'
      prop.type = 'array'
    else if ltype is 'object'
      # recursive properties
      _.extend(prop, convertModel(models, prop, _stack))
    else
      # convert primitive type
      prop.type = convertType(prop.type, null, false, models)

  return result

# Parse the descriptor to extract an associative array with known api routes (Express path used as key).
# For a given route, an associative array of known methods (upper case Http method names as key) contains
# the expected parameters and body (for PUT and POST methods), as an array of parameterSpec.
# The descriptor content is supposed to have been previously validated by the generator middleware
#
# @param prefix [String] url prefix used before path. Must begin with '/' and NOT contain trailing '/'
# @param descriptor [Object] Swagger descriptor (Json).
# @return the analyzed routes.
analyzeRoutes = (prefix, descriptor) ->
  routes = {}
  for resource in descriptor.apis
    for api in resource.apis

      # Store a route for this api.
      route = {}
      routes[prefix+utils.pathToRoute(api.path)] = route
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
            schema.title = spec.name

          if spec.description?
            schema.description = spec.description

          if schema.type is 'object'
            _.extend(schema, convertModel(descriptor.models, if spec.properties then spec else descriptor.models[spec.dataType]))

          # manager possible values interval
          if spec.allowableValues?.valueType?
            switch spec.allowableValues.valueType.toLowerCase()
              when 'range'
                if spec.allowableValues.min? and spec.allowableValues.max?
                  schema.minimum = spec.allowableValues.min
                  schema.maximum = spec.allowableValues.max
                  if schema.minimum > schema.maximum then throw new Error "min value should not be greater tha max value in #{spec.name}"
                else
                  throw new Error "missing allowableValues.min and/or allowableValues.max parameters for allowableValues.range of #{spec.name}"
              when 'list'
                if spec.allowableValues.values? and _.isArray(spec.allowableValues.values)
                  schema.enum = spec.allowableValues.values
                else
                  throw new Error "allowableValues.values is missing or is not an array for allowableValues.list of #{spec.name}"

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

# Validator function.
# Analyze the API descriptor to extract awaited parameters and body
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

  basePath = utils.extractBasePath(app.descriptor)

  # Express middleware for validating incoming request.
  middleware = (req, res, next) ->
    # first get the matching route
    route = req.app._router.matchRequest(req)
    # only for known urls and methods
    if route and route.path of @handle.routes and req.method.toUpperCase() of @handle.routes[route.path]

      process = =>
        # casted parameters
        req.input = {}
        @handle.validate(req.method.toUpperCase(), route.path, req.path, req.query, req.headers, req, req.input, next)

      # read body
      return process() if req.is('json') or req.is('application/x-www-form-urlencoded') or req.is('multipart/form-data')
      # body parsing, if incoming request is not json, multipart or form-urlencoded
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

    next()

  middleware.routes = {}
  # analyze the descriptor
  try
    # make a deep copy to avoid manipulation on the descriptor
    middleware.routes = analyzeRoutes(basePath, JSON.parse(JSON.stringify(app.descriptor)))
  catch err
    throw new Error("Failed to analyze descriptor: #{err.toString()}\n#{err.stack}")

  # Export validation function to allow non-Express usages
  # Performs validation of the incoming request against the expected specification.
  # The generator middleware **must** be used before this validator middleware.
  # It will register the validated routes, and check the descriptor format.
  # Only the routes specified inside the descriptor are validated, other routes are ignored.
  #
  # @param method [String] uppercase http method
  # @param path [String] the matched route path, in Express format (use ':' for path parameters, and with leading '/')
  # @param url [String] the incoming request url (to extract path parameters)
  # @param query [Object] associative array of query parameters: parameter name as key.
  # @param headers [Object] associative array of headers: header name as key.
  # @param bodyContainer [Object] object that contains the body, either plain/associative array (attribute `body`) or files (attribute `files`) where file name are used as keys.
  # Also used as output parameter: casted values will replace the original one.
  # @param input [Object] associative array of casted parameters: must be initialized, and populated by the validate() function
  # @param next [Function] express next processing function
  # @option next err [Error] an error if any of the awaited parameters or body is missing, misformated, or invalid regarding the specification
  middleware.validate = (method, path, url, query, headers, bodyContainer, input, next) ->
    # path parameter extraction will be performed later by express: we must perform it ourselves
    [regex, pathParamsNames] = utils.extractParameters(path)
    specs = @routes[path][method]

    # validates all parameter in parrallel
    async.forEach(specs, (spec, done) ->
      type = spec.schema.schema.type
      value = null
      errPrefix = null

      switch spec.kind
        when 'query'
          value = query[spec.name]
          errPrefix = "query parameter #{spec.name}"
        when 'header'
          value = headers[spec.name]
          errPrefix = "header #{spec.name}"
        when 'path'
          # extract the parameter value:
          match = url.match(regex)
          value = match[pathParamsNames[spec.name]]
          if value
            value = decodeURIComponent(value)
          errPrefix = "path parameter #{spec.name}"
        when 'body'
          errPrefix = "body parameter #{spec.name}"
          if spec.name
            # named parameter: take it from parsed body, or from file part
            if type is 'file'
              value = bodyContainer.files?[spec.name]
              # specific case of files: do not validate with json-gate
              return done if !(value?) and spec.schema.schema.required then new Error "#{errPrefix} is required"
            else
              if bodyContainer.body
                value = bodyContainer.body[spec.name]
              else
                value = undefined
          else
            errPrefix = 'body'
            # unamed parameter: take all body
            value = bodyContainer.body
        else
          throw new Error "unsupported parameter type #{spec.kind}"

      if type is 'array'
        # multiple values awaited
        if value isnt undefined
          value = if _.isArray(value) then value else if _.isString(value) then value.split(',') else [value]
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
            input[spec.name] = value
          else
            # or body
            if spec.name?
              bodyContainer.body[spec.name] = value
            else
              bodyContainer.body = value
        done(err)
      )

    , (err) ->
      # if an error is found, use the 400 Http code (BAD_REQUEST)
      err?.status = 400
      next(err)
    )

  return middleware
