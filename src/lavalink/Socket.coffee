ws = require "ws"
{ Logger } = require "@melike2d/logger"
{ Player } = require "./Player"

module.exports.Socket = class Socket
  constructor: (@manager, data) ->
    @id = data.id
    @host = data.host
    @port = data.port
    Object.defineProperty this, "password",
      value: data.password

    @queue = []
    @resumeKey = null
    @remaining = 5
    @players = new Map
    @logger = new Logger "nodes",
      defaults:
        name: @id

  address: ->
    return "#{@host}#{if @port then ":#{@port}" else ""}"

  connected: ->
    return @ws and @ws.readyState is ws.OPEN

  createPlayer: (guildId) ->
    exists = @players.get guildId
    if exists then return exists

    player = new Player guildId, this
    @players.set guildId, player

    return player

  connect: ->
    headers =
      authorization: this.password,
      "User-Id": @manager.userId,
      "Num-Shards": 1
    if @resumeKey is not null then headers["Resume-Key"] = @resumeKey

    @ws = new ws "ws://#{this.address()}", { headers };
    @ws.onopen = this._open.bind(this)
    @ws.onmessage = this._message.bind(this);
    @ws.onerror = this._error.bind(this);
    @ws.onclose = this._close.bind(this);

  send: (pk, priority = false) ->
    cb = (res, rej) ->
      tq = { pk: JSON.stringify(pk), res, rej }
      if priority then @queue.unshift tq else @queue.push tq
      if this.connected() then this.checkQueue()

    return new Promise(cb.bind this)

  checkQueue: ->
    if @queue.length is 0 then return

    while @queue.length > 0
      next = @queue.shift()
      if !next then return
      @ws.send next.pk, (e) ->
        if e
          @manager.emit "nodeError", this, e
          next.rej e
        else next.res()

  configureResuming: ->
    @resumeKey = Math.random().toString(32)
    return this.send { op: "configureResuming", key: @resumeKey }, true

  _open: ->
    this.checkQueue()
    this.configureResuming()
    @manager.emit "nodeReady", this

  _error: (err) ->
    error = if err and err.error then err.error else err
    @manager.emit "nodeError", this, error

  _close: (evt) ->
    if evt.code is not 1000 and evt.reason is not "destroy"
      await this._reconnect()
    else
      @manager.emit "nodeClose", this

  _message: ({ data }) ->
    pk = null

    if Array.isArray(data) then data = Buffer.concat data else if data instanceof ArrayBuffer then data = Buffer.from data

    try
      pk = JSON.parse data
    catch e
      @logger.error e
      return

    switch pk.op
      when "stats" then @stats = pk
      else
        player = @players.get pk.guildId
        if player then player._playerMessage pk

  _reconnect: ->
    if @remaining is not 0
      @remaining--
      try
        this.connect()
        @remaining = 5
      catch e
        @manager.emit "nodeError", this, e
        setTimeout this._reconnect.bind(this), 15000
    else
      @manager.nodes.delete this.id
      @manager.emit "nodeClose", this