# ##The plugin code

# Your plugin must export a single function, that takes one argument and returns a instance of
# your plugin class. The parameter is an envirement object containing all pimatic related functions
# and classes. See the [startup.coffee](http://sweetpi.de/pimatic/docs/startup.html) for details.
module.exports = (env) ->

  # ###require modules included in pimatic
  # To require modules that are included in pimatic use `env.require`. For available packages take 
  # a look at the dependencies section in pimatics package.json

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'

  M = env.matcher
  _ = env.require('lodash')
  
  # Require the XBMC(kodi) API
  {TCPConnection, XbmcApi} = require 'xbmc'

  
#    silent: true      # comment out for debug!


  # ###KodiPlugin class
  class KodiPlugin extends env.plugins.Plugin

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #  
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins` 
    #     section of the config.json file 
    #     
    # 
    init: (app, @framework, @config) =>
      env.logger.info("Kodi plugin started")
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("KodiPlayer", {
        configDef: deviceConfigDef.KodiPlayer, 
        createCallback: (config) => new KodiPlayer(config)
      })

      @framework.ruleManager.addActionProvider(new KodiPauseActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new KodiPlayActionProvider(@framework))
      #@framework.ruleManager.addActionProvider(new MpdVolumeActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new KodiPrevActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new KodiNextActionProvider(@framework))





  class KodiPlayer extends env.devices.Device
    _state: null
    _currentTitle: null
    _currentArtist: null
    _volume: null
    connection: null

    actions: 
      play:
        description: "starts playing"
      pause:
        description: "pauses playing"
      stop:
        description: "stops playing"
      next:
        description: "play next song"
      previous:
        description: "play previous song"
      volume:
        description: "Change volume of player"

    attributes:
      currentArtist:
        description: "the current playing track artist"
        type: "string"   
      currentTitle:
        description: "the current playing track title"
        type: "string"
      state:
        description: "the current state of the player"
        type: "string"
      volume:
        description: "the volume of the player"
        type: "string"

    template: "musicplayer"

    constructor: (@config) ->
      @name = @config.name
      @id = @config.id

      connection = new TCPConnection
        host: @config.host
        port: @config.port
        verbose: true

      @kodi = new XbmcApi
        debug: env.logger.debug

      @kodi.setConnection connection  
      #  connection: connection
      @kodi.on 'connection:open',                        => 
        env.logger.info 'Kodi connected'
        @_updateInfo()
        
      @kodi.on 'connection:close',                       -> env.logger.info 'Kodi Disconnected'
      @kodi.on 'connection:notification', (notification) => 
        env.logger.debug 'Received notification:', notification
        @_updateInfo()
        # return @_updateInfo().catch( (err) =>
        #   env.logger.error "Error updateinfo: #{err}"
        #   env.logger.debug err
        # )
        

      super()

    getState: () ->
      return Promise.resolve @_state

    getCurrentTitle: () -> Promise.resolve(@_currentTitle)
    getCurrentArtist: () -> Promise.resolve(@_currentTitle)
    getVolume: ()  -> Promise.resolve(@_volume)
    play: () -> @kodi.player.playPause()
    pause: () -> @kodi.player.playPause()
    stop: () -> @kodi.player.stop()
    previous: () -> @kodi.player.previous()
    next: () -> @kodi.player.next() 
    setVolume: (volume) -> env.logger.debug 'setVolume not implemented'

    _updateInfo: -> Promise.all([@_getStatus(), @_getCurrentSong()])

    _setState: (state) ->
      if @_state isnt state
        @_state = state
        @emit 'state', state

    _setCurrentTitle: (title) ->
      if @_currentTitle isnt title
        @_currentTitle = title
        @emit 'currentTitle', title

    _setCurrentArtist: (artist) ->
      if @_currentArtist isnt artist
        @_currentArtist = artist
        @emit 'currentArtist', artist

    _setVolume: (volume) ->
      if @_volume isnt volume
        @_volume = volume
        @emit 'volume', volume

    _getStatus: () ->
      env.logger.debug 'get status'
      @_setState 'state'

    _getCurrentSong: () ->
      env.logger.debug '_getCurrentSong '
      @kodi.player.getCurrentlyPlaying (info) =>
        env.logger.debug info
        @_setCurrentTitle(if info.title? then info.title else "")
        @_setCurrentArtist(if info.artist? then info.artist else "")

    _sendCommandAction: (action) ->
      @kodi.input.ExecuteAction action

  # Pause play volume actions
  class KodiPauseActionProvider extends env.actions.ActionProvider 
  
    constructor: (@framework) -> 
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    parseAction: (input, context) =>

      retVar = null

      kodiPlayers = _(@framework.deviceManager.devices).values().filter( 
        (device) => device.hasAction("play") 
      ).value()

      if kodiPlayers.length is 0 then return

      device = null
      match = null

      onDeviceMatch = ( (m, d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match('pause ')
        .matchDevice(kodiPlayers, onDeviceMatch)
        
      if match?
        assert device?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiPauseActionHandler(device)
        }
      else
        return null

  class KodiPauseActionHandler extends env.actions.ActionHandler

    constructor: (@device) -> #nop

    executeAction: (simulate) => 
      return (
        if simulate
          Promise.resolve __("would pause %s", @device.name)
        else
          @device.pause().then( => __("paused %s", @device.name) )
      )
  
  class KodiPlayActionProvider extends env.actions.ActionProvider 
  
    constructor: (@framework) -> 
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    parseAction: (input, context) =>

      retVar = null

      kodiPlayers = _(@framework.deviceManager.devices).values().filter( 
        (device) => device.hasAction("play") 
      ).value()

      if kodiPlayers.length is 0 then return

      device = null
      match = null

      onDeviceMatch = ( (m, d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match('play ')
        .matchDevice(kodiPlayers, onDeviceMatch)
        
      if match?
        assert device?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiPlayActionHandler(device)
        }
      else
        return null

  class KodiPlayActionHandler extends env.actions.ActionHandler

    constructor: (@device) -> #nop

    executeAction: (simulate) => 
      return (
        if simulate
          Promise.resolve __("would play %s", @device.name)
        else
          @device.play().then( => __("playing %s", @device.name) )
      )


  class KodiNextActionProvider extends env.actions.ActionProvider 

    constructor: (@framework) -> 
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    parseAction: (input, context) =>

      retVar = null
      volume = null

      kodiPlayers = _(@framework.deviceManager.devices).values().filter( 
        (device) => device.hasAction("play") 
      ).value()

      if kodiPlayers.length is 0 then return

      device = null
      valueTokens = null
      match = null

      onDeviceMatch = ( (m, d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match(['play next', 'next '])
        .match(" song ", optional: yes)
        .match("on ")
        .matchDevice(kodiPlayers, onDeviceMatch)

      if match?
        assert device?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiNextActionHandler(device)
        }
      else
        return null
        
  class KodiNextActionHandler extends env.actions.ActionHandler
    constructor: (@device) -> #nop

    executeAction: (simulate) => 
      return (
        if simulate
          Promise.resolve __("would play next track of %s", @device.name)
        else
          @device.next().then( => __("play next track of %s", @device.name) )
      )      

  class KodiPrevActionProvider extends env.actions.ActionProvider 

    constructor: (@framework) -> 
    # ### executeAction()
    ###
    This function handles action in the form of `execute "some string"`
    ###
    parseAction: (input, context) =>

      retVar = null
      volume = null

      kodiPlayers = _(@framework.deviceManager.devices).values().filter( 
        (device) => device.hasAction("play") 
      ).value()

      if kodiPlayers.length is 0 then return

      device = null
      valueTokens = null
      match = null

      onDeviceMatch = ( (m, d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match(['play previous', 'previous '])
        .match(" song ", optional: yes)
        .match("on ")
        .matchDevice(kodiPlayers, onDeviceMatch)

      if match?
        assert device?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiNextActionHandler(device)
        }
      else
        return null
        
  class KodiPrevActionHandler extends env.actions.ActionHandler
    constructor: (@device) -> #nop

    executeAction: (simulate) => 
      return (
        if simulate
          Promise.resolve __("would play previous track of %s", @device.name)
        else
          @device.previous().then( => __("play previous track of %s", @device.name) )
      ) 
      


  # Create a instance of  Kodiplugin
  kodiPlugin = new KodiPlugin
  # and return it to the framework.
  return kodiPlugin