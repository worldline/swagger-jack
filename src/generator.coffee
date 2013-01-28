_ = require('underscore')
pathUtils = require('path')
utils = require('./utils')

descRoute = /\/api-docs.json(\/.*)?/
descPath = '/api-docs.json'

# Validates the specification of a given parameters
validateParam = (parameter, models) ->
  # TODO
  # path paramer: no required, no multipleAllowed, same number as in path, name exists in path
  # query parameter: ?
  # header parameter: ?
  # body parameter: only on 'put' and 'post' request, no multipleAllowed, if unamed, only one authorized
  # type known if arbitrary model


# Validates the specified model
validateModel = (model, id) ->
  # TODO
  return model

# Enrich the given descriptor with resources provided, and extract routes defined.
# Validates the descriptor content.
#
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
addRoutes = (descriptor, resources) ->
  routes = []
  descriptor.apis = []
  descriptor.models = {}
  # analyze each resources
  for resource in resources
    # check mandatory informations
    unless _.isObject(resource.api) and _.isObject(resource.controller)
      throw new Error("Resource must contain 'api' and 'controller' attributes")
    unless _.isString(resource.api.resourcePath)
      throw new Error('Resource without path - are you kidding')
      
    # add models
    if _.isObject(resource.api.models)
      for id, model of resource.api.models
        descriptor.models[id] = validateModel(model, id)
        
    # analyze each api within a given resource
    for api in resource.api.apis
      unless _.isString(api.path)
        throw new Error("Resource #{resource.api.resourcePath} has an api without path - D\'oh'") 
      
      for operation in api.operations
        # check mandatory informations
        unless _.isString(operation.httpMethod)
          throw new Error("Api #{api.path} has an operation without http method - what is the police doing ?")
        
        verb = operation.httpMethod.toLowerCase()
        unless verb in ['get', 'post', 'delete', 'put', 'options', 'head']
          throw new Error("Api #{api.path} operation #{operation.httpMethod} is not supported - I\'m so sorry Janice") 
          
        unless _.isString(operation.nickname)
          throw new Error("Api #{api.path} operation #{operation.httpMethod} does not specify a nickname - we cannot guess the corresponding controller method")
        
        # Validates parameters
        if _.isArray(operation.parameters)
          # validates names unicity
          duplicates = _.chain(operation.parameters)
            .pluck('name')                                # extract attribute name: ['p1', 'p2', 'p3', 'p1']
            .countBy()                                    # group by name: {p1: 2, p2: 1, p3: 1
            .pairs()                                      # make an array: [['p1', 2], ['p2', 1], ['p3': 1]]
            .filter((arr) -> return arr[1] > 1)           # filter duplicates: [['p1', 2]]
            .map((arr) -> return arr[0])                  # extarct names: ['p1']
            .value()

          if duplicates.length > 0
            throw new Error("Api #{api.path} operation #{operation.httpMethod} has duplicates parameters: #{duplicates.join(',')}")
          
          for parameter in operation.parameters
            validateParam(parameter, descriptor.models)
        
        route = utils.pathToRoute(api.path)
        unless operation.nickname of resource.controller
          throw new Error("Api #{api.path} nickname #{operation.nickname} cannot be found in controller")
        
        # load the relevant script that must contain the middelware
        routes.push({method:verb, path:route, middleware: resource.controller[operation.nickname]})
        console.log("found a route #{route} with verb #{verb} bound to exported method #{operation.nickname}")

    # enrich descriptor
    descriptor.apis.push(resource.api)
  
  return routes

# Generator function.
# Will respond to `/api-docs.json` and return a Swagger compliant json description of the current API.
# For each single resource inside the API, will also respond to `/api-docs.json/name` (where name is the resource's name).
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
module.exports = (app, descriptor, resources) ->
  # validates inputs
  unless app?.handle? and app?.set?
    throw new Error('No Express application provided')
  
  unless _.isObject(descriptor)
    throw new Error('Provided root descriptor is not an object')
  
  unless _.isArray(resources)
    throw new Error('Provided resources must be an array')
  
  try
    # enrich the descriptor with apis
    routes = addRoutes(descriptor, resources)
    # Creates middlewares, after a slight delay to let the router being registered
    # Otherwise, the generator middleware will be registered after the added routes
    _.defer( () ->
      for route in routes
        app[route.method](route.path, route.middleware)
    )
      
    # Add descriptor to express application for other middlewares
    app.descriptor = descriptor
   catch err
    throw new Error("Failed to create routes from resources: #{err.toString()}");
  

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
            path: descPath+api.resourcePath
            description: api.description
          })
      
      return res.json(result)
    
    next()