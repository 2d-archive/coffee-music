{ MessageEmbed } = require "discord.js"
{ decode } = require "@lavalink/encoding"

module.exports.Queue = class Queue
  constructor: (@player, @message) ->
    @player.on "end", this._end.bind this
    @player.on "start", this._start.bind this

    @loop = null
    @tracks = []
    @previous = []
    @current = null

  shift: -> @current = @tracks.shift()
  finished: (type) ->
    switch type
      when "end"
        @player.disconnect()
        @player.node.players.delete @message.guild.id
        @message.channel.send "Queue has Ended :wave:"
        return

  start: ->
    this.shift()
    @player.play @current

  _start: (evt) ->
    info = decode evt.track
    embed = new MessageEmbed()
      .setAuthor(info.author)
      .setDescription("[#{info.title}](#{info.uri})")
      .setColor(0xc4549c)

    await @message.channel.send embed

  _end: (evt) ->
    if !evt or evt.reason is "REPLACED" then return
    if @loop is "song"
      @tracks.unshift @current
    else
      @previous.push @current
      this.shift()

    if !this.current
      if this.loop is "queue"
        @tracks = @previous
        @previous = []
        this.shift()
      else return this.finished "end"

    @player.play @current
