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
        value = if value isnt undefined then parseFloat(value) else undefined
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
}