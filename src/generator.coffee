_ = require('underscore')
utils = require('./utils')

# List of lowercase raw types that are not validated as models.
rawTypes = ['void', 'int', 'long', 'integer', 'float', 'double', 'number', 'string', 'boolean', 'array', 'any', 'null', 'byte', 'file']

# Validates the specification of a given parameters
#
# @param parameters [Array] list of existing parameters.
# @param models [Object] associative array containing all possible models, model id used as key.
# @param path [String] validate api's path (for understandable error messages).
# @param path [String] validate api's method (for understandable error messages).
# @throws if a parameter has no name
# @throws if parameter type is not specified or unknown
# @throws if a path parameter is optionnal
# @throws if a path parameter allow multiple
# @throws if declared path parameters number or names does not match the api.path declaration
# @throws if two parameters share the same name
# @throws if more than one body parameter has no name
# @throws if a query, header or path parameter has no name
validateParameters = (parameters, models, path, method) ->
  errorPrefix = "Api #{path} operation #{method}"
  # validates names unicity
  duplicates = _.chain(parameters)
    .pluck('name')                                # extract attribute name: ['p1', 'p2', 'p3', 'p1']
    .filter((p) -> p?)                            # remove anonymous parameters
    .countBy()                                    # group by name: {p1: 2, p2: 1, p3: 1
    .pairs()                                      # make an array: [['p1', 2], ['p2', 1], ['p3': 1]]
    .filter((arr) -> return arr[1] > 1)           # filter duplicates: [['p1', 2]]
    .map((arr) -> return arr[0])                  # extarct names: ['p1']
    .value()

  if duplicates.length > 0
    throw new Error("#{errorPrefix} has duplicates parameters: #{duplicates.join(',')}")

  # validates path parameter names and number
  pathParameters = _.filter(parameters, (p) -> return p?.paramType?.toLowerCase() is 'path')
  [__, routeParameters] = utils.extractParameters(utils.pathToRoute(path))
  routeParametersLength = _.keys(routeParameters).length
  if routeParametersLength isnt pathParameters.length
    throw new Error("#{errorPrefix} declares #{routeParametersLength} parameters in its path, and #{pathParameters.length} in its parameters array - you missed something")
  for name of routeParameters
    unless _.find(pathParameters, (p) -> return p.name is name)?
      throw new Error("#{errorPrefix} declares parameter #{name} in its path, but not in its parameters array - propably a typo")

  # validate anonymous parameter
  if _.filter(parameters, (p) -> return p?.paramType?.toLowerCase() is 'body' and !(p?.name?)).length > 1
    throw new Error("#{errorPrefix} has more than one anonymous body parameter - how is it possible M. Spock ?")

  for parameter in parameters
    unless parameter?.name? or parameter?.paramType?.toLowerCase() is 'body'
      throw new Error("#{errorPrefix} has a non body parameter with no name - are you a k-pop fan ?")

    switch parameter.paramType?.toLowerCase()
      when 'path'
        if parameter.required is false
          throw new Error("#{errorPrefix} path parameter #{parameter.name} cannot be optionnal - system_internal_error")
        if parameter.multipleAllowed is true
          throw new Error("#{errorPrefix} path parameter #{parameter.name} cannot allow multiple values - I'll be curious to see that")
      when 'body'
        # only on put an post
        unless method?.toLowerCase() in ['put', 'post']
          throw new Error("#{errorPrefix} does not allowed body parameters - do you really knows http ?")

        # only known dataType
        allowedDataTypes = ['byte', 'boolean', 'int', 'long', 'float', 'double', 'string', 'date', 'file']
        unless parameter.dataType?.toLowerCase() in allowedDataTypes or models[parameter.dataType]
          throw new Error("'#{parameter.dataType}' does not match an allowed dataType [#{allowedDataTypes}] nor a known model [#{Object.keys(models)}]")
      when 'header', 'query'
        # nothing to check
      else
        if parameter.paramType?
          throw new Error("#{errorPrefix} parameter #{parameter.name} type #{parameter.paramType} is not supported - 42")
        else
          throw new Error("#{errorPrefix} parameter #{parameter.name} has no type - what else ?")

  # TODO type known if arbitrary model, no anonymous types


# Validates the specified model
validateModel = (model, id, models) ->
  # checks that model has an id
  if model.id isnt id
    throw new Error("model #{id} not declared with the same id")
  unless !_.isEmpty(model.properties) or model.additionalProperties or !_.isEmpty(model.items)
    throw new Error("model #{id} does not declares properties")
  if models[id]?
    throw new Error("model #{id} has already been defined")
  # TODO known references, no anonymous inner models
  return model

# Enrich the given descriptor with resources provided, and extract routes defined.
# Validates the descriptor content.
#
# @param prefix [String] url prefix used before path. Must begin with '/' and NOT contain trailing '/'
# @param descriptor [Object] Swagger descriptor (Json).
# @param resources [Array] array of resources, with their own descriptor, controller and models
# @return a list of routes to add, with objects containing `method`, `path` and `middleware`.
# @throws if no api is defined
# @throws if an api does not have any operations
# @throws if an operation hasn't any nickname
# @throws if an operation hasn't any Http method
# @throws if an operation isn't a get, put, post, delete, head or options Http method
# @throws if the NodeJS module denoted by the nickname of an operation cannot be loaded
# @throws if different parameters of the same operation has the same name
addRoutes = (prefix, descriptor, resources) ->
  routes = []
  descriptor.apis = []
  descriptor.models = {}
  # analyze each resources
  for resource in resources
    # check mandatory informations
    unless _.isObject(resource.api)
      throw new Error("Resource must contain 'api' attribute")

    # add models
    resource.api.models or= {}
    for id, model of resource.api.models
      descriptor.models[id] = validateModel(model, id, descriptor.models)

    # allow api without controllers, but do not generate routes
    if _.isObject(resource.controller)
      unless _.isString(resource.api.resourcePath)
        throw new Error('Resource without path - are you kidding')

      # analyze each api within a given resource
      for api in resource.api.apis
        unless _.isString(api.path)
          throw new Error("Resource #{resource.api.resourcePath} has an api without path - D\'oh'")
        unless 0 is api.path.indexOf resource.api.resourcePath
          throw new Error("Resource #{resource.api.resourcePath} has an api #{api.path} that did not match its own path - We beg your peer is sleeping'")

        continue unless _.isArray api.operations
        for operation in api.operations
          # check mandatory informations
          unless _.isString(operation.httpMethod)
            throw new Error("Api #{api.path} has an operation without http method - what is the police doing ?")

          verb = operation.httpMethod.toLowerCase()
          unless verb in ['get', 'post', 'delete', 'put', 'options', 'head']
            throw new Error("Api #{api.path} operation #{operation.httpMethod} is not supported - I\'m so sorry Janice")

          unless _.isString(operation.nickname)
            throw new Error("Api #{api.path} operation #{operation.httpMethod} does not specify a nickname - we cannot guess the corresponding controller method")

          # make sure the responseClass model is defined
          if operation.responseClass
            unless operation.responseClass.toLowerCase() in rawTypes
              resource.api.models[operation.responseClass] or= descriptor.models[operation.responseClass]
              unless resource.api.models[operation.responseClass]?
                throw new Error("responseClass #{operation.responseClass} doesn't match a model")
          else
            throw new Error("responseClass is mandatory. If no result expected, responseClass should be void")

          # Validates parameters
          if _.isArray(operation.parameters)
            # parameter validations
            validateParameters(operation.parameters, descriptor.models, api.path, operation.httpMethod)

            # make sure the dataType model is defined
            for parameter in operation.parameters
              if parameter.dataType and !(parameter.dataType in rawTypes)
                resource.api.models[parameter.dataType] or= descriptor.models[parameter.dataType]

          route = utils.pathToRoute(api.path)
          unless operation.nickname of resource.controller
            throw new Error("Api #{api.path} nickname #{operation.nickname} cannot be found in controller")

          # load the relevant script that must contain the middelware
          routes.push({method:verb, path:"#{prefix}#{route}", middleware: resource.controller[operation.nickname]})
          if /swagger/.test process.env?.NODE_DEBUG
            console.log("found a route #{prefix}#{route} with verb #{verb} bound to exported method #{operation.nickname}")

    # enrich descriptor
    descriptor.apis.push(resource.api)

  return routes

# Generator function.
# Will respond to `/api-docs.json` and return a Swagger compliant json description of the current API.
# For each single resource inside the API, will also respond to `/api-docs.json/name` (where name is the resource's name).
# Path to descriptor is configured by default to `/api-docs.json` but can be also parametrized
#
# The provided descriptor is the root attributes of the swagger descriptor, for example:
#   "apiVersion":"0.2",
#   "basePath":"http:#mydomain.com/api"
#
# The following array contains descriptor and code for each resource.
# A resource descriptor is analyzed and the corresponding routes are registered within the specified Express application.
#
# @param app [Object] the enriched Express application.
# @param descriptor [Object] root attributes of the swagger descriptor
# @param resources [Array] array of supported resources. Contains:
# @option resources api [Object] the swagger descriptor for this resource. Operations nicknames must refer to controller's exported method.
# @option resources controller [Object] controller's code, registered inside Express as routes. Nicknames refer to the controller properties.
# @option resources model [Object] TODO
# @param options [Object] generator options. May contains:
# @option options descPath [String] path to generated descriptor file. Must contain leading slash. Default to `/api-docs.json`
module.exports = (app, descriptor, resources, options = {}) ->
  # validates inputs
  unless app?.handle? and app?.set?
    throw new Error('No Express application provided')
  unless _.isObject(descriptor)
    throw new Error('Provided root descriptor is not an object')
  unless _.isArray(resources)
    throw new Error('Provided resources must be an array')
  unless descriptor.basePath
    throw new Error('basePath is mandatory')
  unless descriptor.apiVersion
    throw new Error('apiVersion is mandatory')

  basePath = utils.extractBasePath(descriptor)

  options.descPath or= "api-docs.json"
  # no leading slash on desc path
  options.descPath = options.descPath[1..] if options.descPath[0] is '/'

  descRoute = new RegExp("^#{basePath}/#{options.descPath}(/.*)?")

  # check mandatory descriptors
  unless descriptor.swaggerVersion
    descriptor.swaggerVersion = '1.1'

  try
    # enrich the descriptor with apis
    routes = addRoutes(basePath, descriptor, resources)
    # Creates middlewares, after a slight delay to let the router being registered
    # Otherwise, the generator middleware will be registered after the added routes
    _.defer(() ->
      for route in routes
        app[route.method](route.path, route.middleware)
    )

    # Add descriptor to express application for other middlewares
    app.descriptor = descriptor
  catch err
    err2 = new Error("Failed to create routes from resources: #{err.toString()}")
    err2.stack = err.stack
    throw err2

  # Express middleware for serving the descRoute.
  return (req, res, next) ->

    match = descRoute.exec(req.path)
    if match?
      # ignore all other request than the descriptor path
      result = _.clone(descriptor)
      if match[1]?
        resource = _.find(descriptor.apis, (res) -> return match[1] is res.resourcePath)
        unless resource?
          return res.send(404)

        result.resourcePath = resource.resourcePath
        result.apis = resource.apis
        result.models = resource.models
       else
        # just the root
        result.apis = _.map(result.apis, (api) ->
          return {
            path: '/'+options.descPath+api.resourcePath
            description: api.description
          })

      return res.json(result)

    next()
