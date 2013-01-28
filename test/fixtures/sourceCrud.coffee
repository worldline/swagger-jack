_ = require 'underscore'
# in-memory crud
sources = []

module.exports =

  create: (req, res) ->
    added = req.body
    added.id = "#{new Date().getTime()}"
    sources.push added
    res.json added

  list: (req, res) ->
    res.json {size:sources.length, total:sources.length, from:0, hits:sources}

  getById: (req, res) ->
    source = _.find sources, (s) -> s.id is req.params.id
    return res.send 404 unless source?
    res.json source

  update: (req, res) ->
    source = _.find sources, (s) -> s.id is req.params.id
    return res.send 404 unless source?
    idx = sources.indexOf source
    sources[idx] = req.body
    sources[idx].id = req.params.id
    res.json sources[idx]

  remove: (req, res) ->
    source = _.find sources, (s) -> s.id is req.params.id
    return res.send 404 unless source?
    sources.splice sources.indexOf(source), 1
    res.send 204

  stat: (req, res) ->
    res.json
      total: sources.length
      names: _.pluck sources, 'name'