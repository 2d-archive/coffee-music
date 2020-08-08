{ EventEmitter } = require "events"
{ Socket } = require "./Socket"
fetch = require "node-fetch"

module.exports.Manager = class Manager extends EventEmitter
  constructor: (nodes, @send) ->
    super()

    @userId = null
    @nodes = new Map()

    for node in nodes
      @nodes.set node.id, new Socket this, node

  init: (userId) ->
    @userId = userId
    @nodes.forEach((n) -> n.connect())

  serverUpdate: (pk) ->
    player = @nodes.get("main").players.get pk.guild_id
    if player
      player._provide pk
      player._update()

  stateUpdate: (pk) ->
    player = @nodes.get("main").players.get pk.guild_id
    if player and pk.user_id is @userId
      if pk.channel_id is not player.channelId
        player.emit "move", pk.channel_id
        player.channelId = pk.channel_id

      player._provide pk
      player._update()

  search: (query, node) ->
    node = @nodes.get node

    data = await fetch "http://#{node.address()}/loadtracks?identifier=#{query}",
      headers:
        authorization: node.password

    return data.json()