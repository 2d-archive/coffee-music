# Imports
require "dotenv/config"
{ Client, MessageEmbed } = require "discord.js"
{ Logger, config } = require "@melike2d/logger"
{ Manager } = require "./lavalink/Manager"
{ Queue } = require "./Queue"
{ parse } = require "url"

# Main Code
logger = new Logger "main"
client = new Client()
manager = new Manager [{ host: "localhost", port: 2333, password: "youshallnotpass", id: "main" }], (id, pk) ->
  guild = client.guilds.cache.get id
  if guild then guild.shard.send pk else logger.error "Unknown guild: #{id}"

manager.on "nodeReady", (n) ->
  logger.info "Node #{n.id} is now ready."

client.on "message", (message) ->
  if !message.content.startsWith "kyu " then return
  if !message.guild then return

  [cmd, args...] = message.content.slice(4).split ///\s+///g
  switch cmd.toLowerCase()
    when "join"
      channel = message.member.voice.channel
      if !channel
        message.channel.send "join a voice channel ya noob"
        return

      node = manager.nodes.get "main"
      player = node.createPlayer message.guild.id
      player.queue = new Queue player, message
      player.connect channel.id

      embed = new MessageEmbed()
        .setColor(0xc4549c)
        .setDescription("Connected to **#{channel.name}**")

      await message.channel.send embed
    when "play"
      node = manager.nodes.get "main"
      player = node.players.get message.guild.id

      query = args.join(" ").trim()
      query = if ["https:", "http:"].includes(parse(query).protocol) then query else "ytsearch:#{query}"
      results = await manager.search query, "main"

      switch results.loadType
        when "TRACK_LOADED"
          song = results.tracks[0]
          player.queue.tracks.push(song.track)
          await message.channel.send(new MessageEmbed()
            .setColor(0xc4549c)
            .setDescription("Queued **[#{song.info.title}](#{song.info.uri})**"))
        when "SEARCH_RESULT"
          str = results.tracks[0..4].map (t, i) -> "`#{++i}`. **[#{t.info.title}](#{t.info.uri})**"
          embed = new MessageEmbed()
            .setColor(0xc4549c)
            .setDescription(str)

          msg = await message.channel.send embed
          filter = (m) -> m.author.id is message.author.id and ///^cancel|[1-5]$///i.test m.content
          await message.channel.awaitMessages(filter, {
            time: 15e3,
            max: 1,
          }).then((c) ->
            first = c.first()
            if !first or ///cancel///i.test first.content then return
            if first.deletable then first.delete({ timeout: 1000 })

            i = ///([1-5])///.exec first.content
            song = results.tracks[(parseInt i[1]) - 1]
            player.queue.tracks.push song.track
            await msg.edit embed.setDescription("Queued **[#{song.info.title}](#{song.info.uri})**")
          )

      if !player.playing and !player.paused then player.queue.start()
    when "skip"
      node = manager.nodes.get "main"
      player = node.players.get message.guild.id
      player.send "stop"

client.on "ready", () ->
  logger.info "#{client.user.tag} is now ready!"
  manager.init client.user.id

client.ws.on "VOICE_STATE_UPDATE", (pk) -> manager.stateUpdate pk
client.ws.on "VOICE_SERVER_UPDATE", (pk) -> manager.serverUpdate pk

client.login process.env.TOKEN
