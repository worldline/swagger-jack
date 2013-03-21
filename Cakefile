# Cakefile used to provide a portable build and test system.
# The only requirement is to have Coffee-script globally installed,
# and to have retrieved the npm dependencies with `npm install`
#
# Available tasks:
# * build - compiles coffee-script from src to lib
# * test - runs all tests with mocha (configuration in test/mocha.opts)
# * clean - removed generated lib folder
fs = require 'fs'
_ = require 'underscore'
rimraf = require 'rimraf'
async = require 'async'
{join} = require 'path'
{spawn} = require 'child_process'

isWin = process.platform.match(/^win/)?

task 'build', 'compile coffee-script source files', ->
  _launch 'coffee', ['-b', '-c', '-o', 'lib', 'src'], {}, ->
    if isWin then rimraf '-p', -> 

task 'test', 'run tests with mocha', ->
  _launch 'mocha', [], {NODE_ENV: 'test'}

task 'clean', 'removes hyperion/lib folder', ->
  rimraf 'lib', (err) ->
    console.error err if err?
    process.exit if err? then 1 else 0

_launch = (cmd, options=[], env={}, callback) ->
  # look into node_modules to find the command
  cmd = "#{cmd}.cmd" if isWin
  cmd = join 'node_modules', '.bin', cmd
  # spawn it now, useing modified environement variables and caller process's standard input/output/error
  app = spawn cmd, options, stdio: 'inherit', env: _.extend({}, process.env, env)
  # invoke optionnal callback if command succeed
  app.on 'exit', (code) ->
    return callback() if code is 0 and callback?
    process.exit code