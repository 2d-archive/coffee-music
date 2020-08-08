{ EventEmitter } = require "events"

module.exports.Player = class Player extends EventEmitter
  @state = null
  @server = null

  constructor: (@guild, @node) ->
    super()

    @paused = false
    @position = 0
    @track = null
    @timestamp = null
    @playing = false
    @volume = 100

  connect: (channelId, options = { selfDeaf: true, selfMute: false }) ->
    @channelId = channelId

    @node.manager.send @guild,
      op: 4
      d:
        guild_id: @guild
        channel_id: channelId
        self_mute: options.selfMute
        self_deaf: options.selfDeaf

    return this

  disconnect: -> this.connect(null)

  send: (op, data = {}, priority = false) ->
    @node.send { data..., op, guildId: @guild }, priority
    return this

  ### Play a lavaplayer track ###
  play: (track, options = {}) ->
    return this.send "play", { track, options... }

  ### Set the pause state of the player ###
  pause: (state = true) ->
    @paused = state
    @playing = !state
    return this.send "pause", pause: state

  ### Resumes the player ###
  resume: ->
    return this.pause false

  ### Seek to a specific position in a track. ###
  seek: (position) ->
    return this.send "seek", { position }

  ### Sets the volume of the player ###
  setVolume: (volume = 100) ->
    @volume = volume
    return this.send "volume", { volume }

  ### Called whenever lavalink sends a message for this player. ###
  _playerMessage: (pk) ->
    switch pk.op
      when "event"
        switch pk.type
          when "TrackEndEvent"
            if pk.reason is not "REPLACED"
              @playing = false
            @timestamp = null
            @track = null
            this.emit "end", pk
          when "TrackExceptionEvent" then this.emit "error", pk
          when "TrackStartEvent"
            @playing = true
            @track = pk.track
            this.emit "start", pk
          when "TrackStuckEvent" then this.emit "stuck", pk
          when "WebSocketClosedEvent" then this.emit "closed", pk
      when "playerUpdate"
        if !pk.state then return
        @position = pk.state.position
        @timestamp = pk.state.time
    return

  ### Provide a voice server or state update to this player ###
  _provide: (pk) ->
    if pk.token then @server = pk else @state = pk
    return

  ### Send a voiceUpdate operation to lavalink ###
  _update: () ->
    if !@state or !@server then return

    this.send "voiceUpdate", {
      sessionId: @state.session_id,
      event: @server
    }, true

    delete @server
    delete @state