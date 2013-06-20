_ = require('underscore')

module.exports = {

  # Convert a swagger path (with path param in {}) to an express route (with path param after :)
  #
  # @param path [String] swagger path
  # @return the corresponding express route
  pathToRoute: (original) ->
    route = (if original.match(/^\//) then '' else '/') + original.replace(/\{([^\}]+)\}/g, ':$1')
    return route.replace(/\/$/, '')

  # Case a string value into a given type.
  # The casted value will never be null, but can be undefined
  #
  # @param type [String] the expected value's type, as defined in json-gate
  # @param value [String] the string value, may be undefined but not null
  # @return the casted value, may be undefined but not null
  # @throws an error if the expected type is object, and the string value cannot be parsed into JSON
  cast: (type, value) ->
    switch type
      when 'number', 'integer'
        # all other values than undefined must be parsed. Empty string is not a number.
        original = value
        value = if value isnt undefined and value isnt '' then Number(value) else undefined
        value = if isNaN(value) then original else value
      when 'boolean'
        # all other values than undefined must be parsed
        switch value
          when 'true' then value = true
          when 'false' then value = false
      when 'object'
        if _.isString(value)
          value = JSON.parse(value)
    return value

  # Generate a random (and probably unic) name
  #
  # @return a 12 random name
  generate: () ->
    name = []
    while(name.length < 12)
      n = Math.floor(Math.random()*62)
      #        1-10                                   A-Z  a-z
      name.push(if n<10 then n else String.fromCharCode(n+(if n<36 then 55 else 61)))
    return name.join('')

  # Extract path parameters names from a given path
  # Returns two things.
  #
  # @param path [String] Express route, in which parameters are declared with ':'
  # @return the matching regular expression
  # @return an oject in which the extracted parameters are used as keys, and their respective position (0-based) as values
  extractParameters: (path) ->
    # path parameter extraction will be performed later by express: we must perform it ourselves
    pathParamsNames = {}
    i = 0
    # create a regular expression to extract path parameters and isolate their names
    regex = new RegExp(path.replace(/:([^\/]+)/g, (match, key) ->
      pathParamsNames[key] = ++i
      return '([^\/]*)'
    ))
    [regex, pathParamsNames]

  # Extract base path prefix (without protocol, host, port and trailing slash) of a given descriptor
  # Remove trailing slash from basePath within the descriptor
  #
  # @param descriptor [Object] descriptor from which base path is extracted
  # @return the corresponding base path, without trailing slash
  # @throw an error if found basepath is misformated
  extractBasePath: (descriptor) ->
    # remove trailing slash if needed
    descriptor.basePath = descriptor.basePath[..descriptor.basePath.length-2] if descriptor.basePath.match /\/$/
    # check url compliance
    match = descriptor.basePath.match /^https?:\/\/[^\/]+(?::\d+)?(\/.+)?$/
    unless match
      throw new Error("basePath #{descriptor.basePath} is not a valid url address")
    basePath = match[1] or ''
    # do not allow trailing slash
    basePath = basePath[..basePath.length-1] if basePath[basePath.length-1] is '/'
    basePath

}
