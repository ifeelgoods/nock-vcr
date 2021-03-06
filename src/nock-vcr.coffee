nock = require 'nock'
fs = require 'fs'
util = require 'util'
path = require 'path'

ALL = 'ALL'
ONCE = 'ONCE'
NONE = 'NONE'

modes = { ALL, ONCE, NONE }

config =
  cassetteLibraryDir: 'test/cassettes'
  mode: process.env.NOCK_VCR_MODE ? ONCE

_currentCassette = null

flushNockRecorder = ->
    calls = nock.recorder.play()
    nock.recorder.clear()
    code = "module.exports = exports = function(nock) {"
    code += "\nvar refs = [];\n"
    for call, i in calls
      code += "\nrefs[#{i}] = #{call.substr(1)}"
    code += "\n\nreturn refs;"
    code += "\n};"
    return code

ensureCassetteLibraryDirExists = ->
  currentDir = '.'
  for dir in config.cassetteLibraryDir.split(path.sep)
    currentDir = path.resolve currentDir, dir
    fs.mkdirSync(currentDir) unless fs.existsSync(currentDir)
  return

class Cassette

  constructor: (name, options={})->
    unless name?
      throw new Error("A name is needed for the cassette.")

    Object.defineProperty @, 'name', value: name

    Object.defineProperty @, 'file', get: =>
      fileName = "#{ @name.split(/[^\w\/]+/).join('-').toLowerCase() }.js"
      filePath = path.join(config.cassetteLibraryDir, fileName)
      dir = filePath.substring(0, filePath.lastIndexOf('/') + 1)
      fs.mkdirSync dir unless fs.existsSync(dir)
      path.resolve filePath

    Object.defineProperty @, 'exists', get: =>
      fs.existsSync @file

    Object.defineProperty @, 'recording', get: =>
      recordMode = options.record ? config.mode ? ONCE
      switch recordMode
        when ALL then true
        when NONE then false
        else not @exists

  load: ->
    nock.cleanAll()
    nock.restore()
    if @recording then @rec() else @play()

  rec: ->
    nock.recorder.rec true

  play: ->
    nock.activate()
    if @exists
      name = require.resolve @file
      if require.cache[name]?
        delete require.cache[name]
      @refs = (require @file)(nock)

  eject: ->
    if @recording
      @write()
    else if @refs?
      @refs.forEach (ref, index) ->
        try
          ref.done()
        catch error
          if error.message.includes('Mocks not yet satisfied')
            console.warn "refs[#{ index }]", error.message
          else throw error

  write: ->
    calls = flushNockRecorder()
    ensureCassetteLibraryDirExists()
    fs.writeFileSync @file, calls, 'utf8'

insertCassette = (name, options={})->
  nock.recorder.setGeneratedBodyRequestFilters(options.generatedBodyRequestFilters ? [])
  nock.recorder.setGeneratedPathFilters(options.generatedPathFilters ? [])

  nock.cleanAll()
  if _currentCassette?
    throw new Error("Cassette '#{_currentCassette.name}' already loaded!")

  _currentCassette = new Cassette name, options
  _currentCassette.load()

ejectCassette = ->
  try
    _currentCassette?.eject()
  catch error
    throw error
  finally
    _currentCassette = null
    nock.cleanAll()

currentCassette = ->
  _currentCassette

module.exports = exports = { insertCassette, ejectCassette, currentCassette }
