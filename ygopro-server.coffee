net = require 'net'
http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
os = require 'os'
crypto = require 'crypto'
exec = require('child_process').exec
execFile = require('child_process').execFile
spawn = require('child_process').spawn
spawnSync = require('child_process').spawnSync
rmdir = require 'rimraf'

# dummy class to be overwritten if bot token is provided
botServer = {
	connect: -> {},
	write: -> {},
	write2: -> {},
}

# 三方库
_ = global._ = require 'underscore'
_.str = require 'underscore.string'
_.mixin(_.str.exports())

request = require 'request'

bunyan = require 'bunyan'
log = global.log = bunyan.createLogger name: "srvpro-hel"

moment = global.moment = require 'moment'
moment.updateLocale('zh-cn', {
  relativeTime: {
    future: '%s内',
    past: '%s前',
    s: '%d秒',
    m: '1分钟',
    mm: '%d分钟',
    h: '1小时',
    hh: '%d小时',
    d: '1天',
    dd: '%d天',
    M: '1个月',
    MM: '%d个月',
    y: '1年',
    yy: '%d年'
  }
})

import_datas = global.import_datas = [
  "abuse_count",
  "ban_mc",
  "vpass",
  "rag",
  "rid",
  "is_post_watcher",
  "retry_count",
  "name",
  "pass",
  "name_vpass",
  "is_first",
  "lp",
  "card_count",
  "is_host",
  "pos",
  "surrend_confirm",
  "kick_count",
  "deck_saved",
  "main",
  "side",
  "side_interval",
  "side_tcount",
  "selected_preduel",
  "last_game_msg",
  "last_game_msg_title",
  "last_hint_msg",
  "start_deckbuf",
  "ready_trap",
  "join_time",
  "replays_sent"
]

merge = require 'deepmerge'

loadJSON = require('load-json-file').sync

#heapdump = require 'heapdump'

# 配置
# 导入旧配置
if not fs.existsSync('./config')
  fs.mkdirSync('./config')

setting_save = global.setting_save = (settings) ->
  fs.writeFileSync(settings.file, JSON.stringify(settings, null, 2))
  return

setting_change = global.setting_change = (settings, path, val) ->
  # path should be like "modules:welcome"
  log.info("setting changed", path, val) if _.isString(val)
  path=path.split(':')
  if path.length == 0
    settings[path[0]]=val
  else
    target=settings
    while path.length > 1
      key=path.shift()
      target=target[key]
    key = path.shift()
    target[key] = val
  setting_save(settings)
  return

# 读取配置
try
  config = loadJSON('./config/config.json')
catch
  config = {}
settings = global.settings = config

#import old configs
imported = false
#reset http.quick_death_rule from true to 1
if settings.modules.http.quick_death_rule == true
  settings.modules.http.quick_death_rule = 1
  imported = true
#import the old enable_priority hostinfo
if settings.hostinfo.enable_priority or settings.hostinfo.enable_priority == false
  if settings.hostinfo.enable_priority
    settings.hostinfo.duel_rule = 3
  else
    settings.hostinfo.duel_rule = 4
  delete settings.hostinfo.enable_priority
  imported = true
#finish
if imported
  setting_save(settings)
if settings.bot_token.length > 0
  botServer = require('./botserver.js')
  botServer.connect(settings.bot_token)

# 读取数据
default_data = loadJSON('./data/default_data.json')
try
  tips = global.tips = loadJSON('./config/tips.json')
catch
  tips = global.tips = default_data.tips
  setting_save(tips)
try
  dialogues = global.dialogues = loadJSON('./config/dialogues.json')
catch
  dialogues = global.dialogues = default_data.dialogues
  setting_save(dialogues)
try
  badwords = global.badwords = loadJSON('./config/badwords.json')
catch
  badwords = global.badwords = default_data.badwords
  setting_save(badwords)
try
  duel_log = global.duel_log = loadJSON('./config/duel_log.json')
catch
  duel_log = global.duel_log = default_data.duel_log
  setting_save(duel_log)
try
  chat_color = global.chat_color = loadJSON('./config/chat_color.json')
catch
  chat_color = global.chat_color = default_data.chat_color
  setting_save(chat_color)

# load the lflist of current date
lflists = global.lflists = []
# expansions/lflist
try
  for list in fs.readFileSync('ygopro/expansions/lflist.conf', 'utf8').match(/!.*/g)
    date=list.match(/!([\d\.]+)/)
    continue unless date
    lflists.push({date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})
catch
# lflist
try
  for list in fs.readFileSync('ygopro/lflist.conf', 'utf8').match(/!.*/g)
    date=list.match(/!([\d\.]+)/)
    continue unless date
    lflists.push({date: moment(list.match(/!([\d\.]+)/)[1], 'YYYY.MM.DD').utcOffset("-08:00"), tcg: list.indexOf('TCG') != -1})
catch

if settings.modules.heartbeat_detection.enabled
  long_resolve_cards = global.long_resolve_cards = loadJSON('./data/long_resolve_cards.json')

# 组件
ygopro = global.ygopro = require './ygopro.js'
roomlist = global.roomlist = require './roomlist.js' if settings.modules.http.websocket_roomlist

if settings.modules.i18n.auto_pick
  geoip = require('geoip-country-lite')

# 获取可用内存
memory_usage = global.memory_usage = 0
get_memory_usage = get_memory_usage = ()->
  prc_free = exec("free")
  prc_free.stdout.on 'data', (data)->
    lines = data.toString().split(/\n/g)
    line = lines[0].split(/\s+/)
    new_free = if line[6] == 'available' then true else false
    line = lines[1].split(/\s+/)
    total = parseInt(line[1], 10)
    free = parseInt(line[3], 10)
    buffers = parseInt(line[5], 10)
    if new_free
      actualFree = parseInt(line[6], 10)
    else
      cached = parseInt(line[6], 10)
      actualFree = free + buffers + cached
    percentUsed = parseFloat(((1 - (actualFree / total)) * 100).toFixed(2))
    memory_usage = global.memory_usage = percentUsed
    return
  return
get_memory_usage()
setInterval(get_memory_usage, 3000)

CORES_list = global.CORES_list = []

ROOM_all = global.ROOM_all = []
ROOM_players_oppentlist = global.ROOM_players_oppentlist = {}
ROOM_players_banned = global.ROOM_players_banned = []
ROOM_players_scores = global.ROOM_players_scores = {}
ROOM_connected_ip = global.ROOM_connected_ip = {}
ROOM_bad_ip = global.ROOM_bad_ip = {}

# ban a user manually and permanently
ban_user = global.ban_user = (name) ->
  settings.ban.banned_user.push(name)
  setting_save(settings)
  bad_ip=0
  for room in ROOM_all when room and room.established
    for player in room.players
      if player and (player.name == name or player.ip == bad_ip)
        bad_ip = player.ip
        ROOM_bad_ip[bad_ip]=99
        settings.ban.banned_ip.push(player.ip)
        ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays(player, room)
        CLIENT_kick(player)
        continue
  return

update_core_paths = global.update_core_paths = () ->
  if settings.live_core
    dirs = []
    try
      files = fs.readdirSync("./ygopro/cores")
      for file in files
        if file[0] != '.'
          filePath = "./ygopro/cores/#{file}"
          stat = fs.statSync(filePath)
          if stat.isDirectory()
            dirs.push(file)
      _.sortBy(dirs, (name)-> return name)
    CORES_list = dirs[..]

get_latest_core_path = global.get_latest_core_path = () ->
    if settings.live_core
        return CORES_list[..].pop()

delete_outdated_cores = global.delete_outdated_cores = () ->
    if settings.live_core
        update_core_paths()
        list = CORES_list[..]
        list.pop()
        if list.length>0 && ROOM_all.length>0
            for path in list
                room = _.find ROOM_all, (room)->
                    room && path == room.core_path
                if !room
                    rmdir "./ygopro/cores/#{path}", (error)->
            update_core_paths()

# automatically ban user to use random duel
ROOM_ban_player = global.ROOM_ban_player = (name, ip, reason, countadd = 1)->
  return if settings.modules.test_mode.no_ban_player
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    ip == bannedplayer.ip
  if bannedplayer
    bannedplayer.count = bannedplayer.count + countadd
    bantime = if bannedplayer.count > 3 then Math.pow(2, bannedplayer.count - 3) * 2 else 0
    bannedplayer.time = if moment() < bannedplayer.time then moment(bannedplayer.time).add(bantime, 'm') else moment().add(bantime, 'm')
    bannedplayer.reasons.push(reason) if not _.find bannedplayer.reasons, (bannedreason)->
      bannedreason == reason
    bannedplayer.need_tip = true
  else
    bannedplayer = {"ip": ip, "time": moment(), "count": countadd, "reasons": [reason], "need_tip": true}
    ROOM_players_banned.push(bannedplayer)
  #log.info("banned", name, ip, reason, bannedplayer.count)
  return

ROOM_player_win = global.ROOM_player_win = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].win = ROOM_players_scores[name].win + 1
  ROOM_players_scores[name].combo = ROOM_players_scores[name].combo + 1
  return

ROOM_player_lose = global.ROOM_player_lose = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].lose = ROOM_players_scores[name].lose + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_flee = global.ROOM_player_flee = (name)->
  if !ROOM_players_scores[name]
    ROOM_players_scores[name]={win:0, lose:0, flee:0, combo:0}
  ROOM_players_scores[name].flee = ROOM_players_scores[name].flee + 1
  ROOM_players_scores[name].combo = 0
  return

ROOM_player_get_score = global.ROOM_player_get_score = (player)->
  name = player.name_vpass
  score = ROOM_players_scores[name] 
  if !score
    return "#{player.name} ${random_score_blank}"
  total = score.win + score.lose
  if score.win < 2 and total < 3
    return "#{player.name} ${random_score_not_enough}"
  if score.combo >= 2
    return "${random_score_part1}#{player.name} ${random_score_part2} #{Math.ceil(score.win/total*100)}${random_score_part3} #{Math.ceil(score.flee/total*100)}${random_score_part4_combo}#{score.combo}${random_score_part5_combo}"
    #return player.name + " 的今日战绩：胜率" + Math.ceil(score.win/total*100) + "%，逃跑率" + Math.ceil(score.flee/total*100) + "%，" + score.combo + "连胜中！"
  else
    return "${random_score_part1}#{player.name} ${random_score_part2} #{Math.ceil(score.win/total*100)}${random_score_part3} #{Math.ceil(score.flee/total*100)}${random_score_part4}"
  return

if settings.modules.random_duel.post_match_scores
  setInterval(()->
    scores_pair = _.pairs ROOM_players_scores
    scores_by_lose = _.sortBy(scores_pair, (score)-> return score[1].lose).reverse() # 败场由高到低
    scores_by_win = _.sortBy(scores_by_lose, (score)-> return score[1].win).reverse() # 然后胜场由低到高，再逆转，就是先排胜场再排败场
    scores = _.first(scores_by_win, 10)
    #log.info scores
    request.post { url : settings.modules.random_duel.post_match_scores , form : {
      accesskey: settings.modules.random_duel.post_match_accesskey,
      rank: JSON.stringify(scores)
    }}, (error, response, body)=>
      if error
        log.warn 'RANDOM SCORE POST ERROR', error
      else
        if response.statusCode != 204 and response.statusCode != 200
          log.warn 'RANDOM SCORE POST FAIL', response.statusCode, response.statusMessage, body
        #else
        #  log.info 'RANDOM SCORE POST OK', response.statusCode, response.statusMessage
      return
    return
  , 60000)

ROOM_find_or_create_by_name = global.ROOM_find_or_create_by_name = (name, player_ip)->
  uname=name.toUpperCase()
  if settings.modules.random_duel.enabled and (uname == '' or uname == 'S' or uname == 'M' or uname == 'T')
    return ROOM_find_or_create_random(uname, player_ip)
  if room = ROOM_find_by_name(name)
    return room
  else if memory_usage >= 90
    return null
  else
    return new Room(name)

ROOM_find_or_create_random = global.ROOM_find_or_create_random = (type, player_ip)->
  bannedplayer = _.find ROOM_players_banned, (bannedplayer)->
    return player_ip == bannedplayer.ip
  if bannedplayer
    if bannedplayer.count > 6 and moment() < bannedplayer.time
      return {"error": "${random_banned_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_banned_part2}#{moment(bannedplayer.time).fromNow(true)}${random_banned_part3}"}
    if bannedplayer.count > 3 and moment() < bannedplayer.time and bannedplayer.need_tip and type != 'T'
      bannedplayer.need_tip = false
      return {"error": "${random_deprecated_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_deprecated_part2}#{moment(bannedplayer.time).fromNow(true)}${random_deprecated_part3}"}
    else if bannedplayer.need_tip
      bannedplayer.need_tip = false
      return {"error": "${random_warn_part1}#{bannedplayer.reasons.join('${random_ban_reason_separator}')}${random_warn_part2}"}
    else if bannedplayer.count > 2
      bannedplayer.need_tip = true
  max_player = if type == 'T' then 4 else 2
  playerbanned = (bannedplayer and bannedplayer.count > 3 and moment() < bannedplayer.time)
  result = _.find ROOM_all, (room)->
    return room and room.random_type != '' and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and
    ((type == '' and (room.random_type == 'S' or (settings.modules.random_duel.blank_pass_match and room.random_type != 'T'))) or room.random_type == type) and
    room.get_playing_player().length < max_player and
    (settings.modules.random_duel.no_rematch_check or room.get_host() == null or
    room.get_host().ip != ROOM_players_oppentlist[player_ip]) and
    (playerbanned == room.deprecated or type == 'T')
  if result
    result.welcome = '${random_duel_enter_room_waiting}'
    #log.info 'found room', player_name
  else if memory_usage < 90
    type = if type then type else 'S'
    name = type + ',RANDOM#' + Math.floor(Math.random() * 100000)
    result = new Room(name)
    result.random_type = type
    result.max_player = max_player
    result.welcome = '${random_duel_enter_room_new}'
    result.deprecated = playerbanned
    #log.info 'create room', player_name, name
  else
    return null
  if result.random_type=='M' then result.welcome = result.welcome + '\n${random_duel_enter_room_match}'
  return result

ROOM_find_by_name = global.ROOM_find_by_name = (name)->
  result = _.find ROOM_all, (room)->
    return room and room.name == name
  return result

ROOM_find_by_title = global.ROOM_find_by_title = (title)->
  result = _.find ROOM_all, (room)->
    return room and room.title == title
  return result

ROOM_find_by_port = global.ROOM_find_by_port = (port)->
  _.find ROOM_all, (room)->
    return room and room.port == port

ROOM_find_by_pid = global.ROOM_find_by_pid = (pid)->
  _.find ROOM_all, (room)->
    return room and room.process_pid == pid

ROOM_find_by_game_id = global.ROOM_find_by_game_id = (id)->
  _.find ROOM_all, (room)->
    return room and room.game_id == id

ROOM_validate = global.ROOM_validate = (name)->
  client_name_and_pass = name.split('$', 2)
  client_name = client_name_and_pass[0]
  client_pass = client_name_and_pass[1]
  return true if !client_pass
  !_.find ROOM_all, (room)->
    return false unless room
    room_name_and_pass = room.name.split('$', 2)
    room_name = room_name_and_pass[0]
    room_pass = room_name_and_pass[1]
    client_name == room_name and client_pass != room_pass

ROOM_unwelcome = global.ROOM_unwelcome = (room, bad_player, reason)->
  return unless room
  for player in room.players
    if player and player == bad_player
      ygopro.stoc_send_chat(player, "${unwelcome_warn_part1}#{reason}${unwelcome_warn_part2}", ygopro.constants.COLORS.RED)
    else if player and player.pos!=7 and player != bad_player
      player.flee_free=true
      ygopro.stoc_send_chat(player, "${unwelcome_tip_part1}#{reason}${unwelcome_tip_part2}", ygopro.constants.COLORS.BABYBLUE)
  return

CLIENT_kick = global.CLIENT_kick = (client) ->
  if !client
    return false
  client.system_kicked = true
  if settings.modules.reconnect.enabled and client.closed
    if client.server and !client.had_new_reconnection
      client.server.destroy()
  else
    client.destroy()
  return true

release_disconnect = global.release_disconnect = (dinfo, reconnected) ->
  if dinfo.old_client and !reconnected
    dinfo.old_client.destroy()
  if dinfo.old_server and !reconnected
    dinfo.old_server.destroy()
  clearTimeout(dinfo.timeout)
  return

CLIENT_get_authorize_key = global.CLIENT_get_authorize_key = (client) ->
  if client.vpass
    return client.name_vpass
  else if client.is_local
    return client.name
  else
    return client.ip + ":" + client.name

CLIENT_reconnect_unregister = global.CLIENT_reconnect_unregister = (client, reconnected, exact) ->
  if !settings.modules.reconnect.enabled
    return false
  if disconnect_list[CLIENT_get_authorize_key(client)]
    if exact and disconnect_list[CLIENT_get_authorize_key(client)].old_client != client
      return false
    release_disconnect(disconnect_list[CLIENT_get_authorize_key(client)], reconnected)
    delete disconnect_list[CLIENT_get_authorize_key(client)]
    return true
  return false

CLIENT_reconnect_register = global.CLIENT_reconnect_register = (client, room_id, error) ->
  room = ROOM_all[room_id]
  if client.had_new_reconnection
    return false
  if !settings.modules.reconnect.enabled or !room or client.system_kicked or client.flee_free or disconnect_list[CLIENT_get_authorize_key(client)] or client.is_post_watcher or !CLIENT_is_player(client, room) or room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or (settings.modules.reconnect.auto_surrender_after_disconnect and room.hostinfo.mode != 1) or (room.random_type and room.get_disconnected_count() > 1)
    return false
  # for player in room.players
  #   if player != client and CLIENT_get_authorize_key(player) == CLIENT_get_authorize_key(client)
  #     return false # some issues may occur in this case, so return false
  dinfo = {
    room_id: room_id,
    old_client: client,
    old_server: client.server,
    deckbuf: client.start_deckbuf
  }
  tmot = setTimeout(() ->
    room.disconnect(client, error)
    dinfo.old_server.destroy()
    return
  , settings.modules.reconnect.wait_time)
  dinfo.timeout = tmot
  disconnect_list[CLIENT_get_authorize_key(client)] = dinfo
  #console.log("#{client.name} ${disconnect_from_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${disconnect_from_game}" + if error then ": #{error}" else '')
  if client.time_confirm_required
    client.time_confirm_required = false
    ygopro.ctos_send(client.server, 'TIME_CONFIRM')
  if settings.modules.reconnect.auto_surrender_after_disconnect and room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING
    ygopro.ctos_send(client.server, 'SURRENDER')
  return true

CLIENT_import_data = global.CLIENT_import_data = (client, old_client, room) ->
  for player,index in room.players
    if player == old_client
      room.players[index] = client
      break
  room.dueling_players[old_client.pos] = client
  if room.waiting_for_player == old_client
    room.waiting_for_player = client
  if room.waiting_for_player2 == old_client
    room.waiting_for_player2 = client
  if room.selecting_tp == old_client
    room.selecting_tp = client
  for key in import_datas
    client[key] = old_client[key]
  old_client.had_new_reconnection = true
  return

SERVER_clear_disconnect = global.SERVER_clear_disconnect = (server) ->
  return false unless settings.modules.reconnect.enabled
  for k,v of disconnect_list
    if v and server == v.old_server
      release_disconnect(v)
      delete disconnect_list[k]
      return true
  return false

ROOM_clear_disconnect = global.ROOM_clear_disconnect = (room_id) ->
  return false unless settings.modules.reconnect.enabled
  for k,v of disconnect_list
    if v and room_id == v.room_id
      release_disconnect(v)
      delete disconnect_list[k]
      return true
  return false

CLIENT_is_player = global.CLIENT_is_player = (client, room) ->
  is_player = false
  for player in room.players
    if client == player
      is_player = true
      break
  return is_player and client.pos <= 3

CLIENT_is_able_to_reconnect = global.CLIENT_is_able_to_reconnect = (client, deckbuf) ->
  unless settings.modules.reconnect.enabled
    return false
  if client.system_kicked
    return false
  disconnect_info = disconnect_list[CLIENT_get_authorize_key(client)]
  unless disconnect_info
    return false
  room = ROOM_all[disconnect_info.room_id]
  if !room
    CLIENT_reconnect_unregister(client)
    return false
  if deckbuf and !_.isEqual(deckbuf, disconnect_info.deckbuf)
    return false
  return true

CLIENT_get_kick_reconnect_target = global.CLIENT_get_kick_reconnect_target = (client, deckbuf) ->
  for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
    for player in room.get_playing_player() when !player.closed and player.name == client.name and (player.pass == client.pass) and (player.ip == client.ip or (client.vpass and client.vpass == player.vpass)) and (!deckbuf or _.isEqual(player.start_deckbuf, deckbuf))
      return player
  return null

CLIENT_is_able_to_kick_reconnect = global.CLIENT_is_able_to_kick_reconnect = (client, deckbuf) ->
  unless settings.modules.reconnect.enabled and settings.modules.reconnect.allow_kick_reconnect
    return false
  if !CLIENT_get_kick_reconnect_target(client, deckbuf)
    return false
  return true

CLIENT_send_pre_reconnect_info = global.CLIENT_send_pre_reconnect_info = (client, room, old_client) ->
  ygopro.stoc_send_chat(client, "${pre_reconnecting_to_room}", ygopro.constants.COLORS.BABYBLUE)
  ygopro.stoc_send(client, 'JOIN_GAME', room.join_game_buffer)
  req_pos = old_client.pos
  if old_client.is_host
    req_pos += 0x10
  ygopro.stoc_send(client, 'TYPE_CHANGE', {
    type: req_pos
  })
  for player in room.players
    ygopro.stoc_send(client, 'HS_PLAYER_ENTER', {
      name: player.name,
      pos: player.pos,
    })
  return

CLIENT_send_reconnect_info = global.CLIENT_send_reconnect_info = (client, server, room) ->
  client.reconnecting = true
  ygopro.stoc_send_chat(client, "${reconnecting_to_room}", ygopro.constants.COLORS.BABYBLUE)
  switch room.duel_stage
    when ygopro.constants.DUEL_STAGE.FINGER
      ygopro.stoc_send(client, 'DUEL_START')
      if (room.hostinfo.mode != 2 or client.pos == 0 or client.pos == 2) and !client.selected_preduel
        ygopro.stoc_send(client, 'SELECT_HAND')
      client.reconnecting = false
      break
    when ygopro.constants.DUEL_STAGE.FIRSTGO
      ygopro.stoc_send(client, 'DUEL_START')
      if client == room.selecting_tp # and !client.selected_preduel
        ygopro.stoc_send(client, 'SELECT_TP')
      client.reconnecting = false
      break
    when ygopro.constants.DUEL_STAGE.SIDING
      ygopro.stoc_send(client, 'DUEL_START')
      if !client.selected_preduel
        ygopro.stoc_send(client, 'CHANGE_SIDE')
      client.reconnecting = false
      break
    else
      ygopro.ctos_send(server, 'REQUEST_FIELD')
      break
  return

CLIENT_pre_reconnect = global.CLIENT_pre_reconnect = (client) ->
  if CLIENT_is_able_to_reconnect(client)
    dinfo = disconnect_list[CLIENT_get_authorize_key(client)]
    client.pre_reconnecting = true
    client.pos = dinfo.old_client.pos
    client.setTimeout(300000)
    CLIENT_send_pre_reconnect_info(client, ROOM_all[dinfo.room_id], dinfo.old_client)
  else if CLIENT_is_able_to_kick_reconnect(client)
    player = CLIENT_get_kick_reconnect_target(client)
    client.pre_reconnecting = true
    client.pos = player.pos
    client.setTimeout(300000)
    CLIENT_send_pre_reconnect_info(client, ROOM_all[player.rid], player)
  return

CLIENT_reconnect = global.CLIENT_reconnect = (client) ->
  if !CLIENT_is_able_to_reconnect(client)
    ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
    CLIENT_kick(client)
    return
  client.pre_reconnecting = false
  dinfo = disconnect_list[CLIENT_get_authorize_key(client)]
  room = ROOM_all[dinfo.room_id]
  current_old_server = client.server
  client.server = dinfo.old_server
  client.server.client = client
  dinfo.old_client.server = null
  current_old_server.client = null
  current_old_server.had_new_reconnection = true
  current_old_server.destroy()
  client.established = true
  client.pre_establish_buffers = []
  if room.random_type
    room.last_active_time = moment()
  CLIENT_import_data(client, dinfo.old_client, room)
  CLIENT_send_reconnect_info(client, client.server, room)
  #console.log("#{client.name} ${reconnect_to_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${reconnect_to_game}")
  CLIENT_reconnect_unregister(client, true)
  return

CLIENT_kick_reconnect = global.CLIENT_kick_reconnect = (client, deckbuf) ->
  if !CLIENT_is_able_to_kick_reconnect(client)
    ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
    CLIENT_kick(client)
    return
  client.pre_reconnecting = false
  player = CLIENT_get_kick_reconnect_target(client, deckbuf)
  room = ROOM_all[player.rid]
  current_old_server = client.server
  client.server = player.server
  client.server.client = client
  ygopro.stoc_send_chat(player, "${reconnect_kicked}", ygopro.constants.COLORS.RED)
  player.server = null
  player.had_new_reconnection = true
  CLIENT_kick(player)
  current_old_server.client = null
  current_old_server.had_new_reconnection = true
  current_old_server.destroy()
  client.established = true
  client.pre_establish_buffers = []
  if room.random_type
    room.last_active_time = moment()
  CLIENT_import_data(client, player, room)
  CLIENT_send_reconnect_info(client, client.server, room)
  #console.log("#{client.name} ${reconnect_to_game}")
  ygopro.stoc_send_chat_to_room(room, "#{client.name} ${reconnect_to_game}")
  CLIENT_reconnect_unregister(client, true)
  return

if settings.modules.reconnect.enabled
  disconnect_list = {} # {old_client, old_server, room_id, timeout, deckbuf}

CLIENT_heartbeat_unregister = global.CLIENT_heartbeat_unregister = (client) ->
  if !settings.modules.heartbeat_detection.enabled or !client.heartbeat_timeout
    return false
  clearTimeout(client.heartbeat_timeout)
  delete client.heartbeat_timeout
  #log.info(2, client.name)
  return true

CLIENT_heartbeat_register = global.CLIENT_heartbeat_register = (client, send) ->
  if !settings.modules.heartbeat_detection.enabled or client.closed or client.is_post_watcher or client.pre_reconnecting or client.reconnecting or client.waiting_for_last or client.pos > 3 or client.heartbeat_protected
    return false
  if client.heartbeat_timeout
    CLIENT_heartbeat_unregister(client)
  client.heartbeat_responsed = false
  if send
    ygopro.stoc_send(client, "TIME_LIMIT", {
      player: 0,
      left_time: 0
    })
    ygopro.stoc_send(client, "TIME_LIMIT", {
      player: 1,
      left_time: 0
    })
  client.heartbeat_timeout = setTimeout(() ->
    CLIENT_heartbeat_unregister(client)
    client.destroy() unless client.closed or client.heartbeat_responsed
    return
  , settings.modules.heartbeat_detection.wait_time)
  #log.info(1, client.name)
  return true

CLIENT_is_banned_by_mc = global.CLIENT_is_banned_by_mc = (client) ->
  return client.ban_mc and client.ban_mc.banned and moment().isBefore(client.ban_mc.until)

CLIENT_send_replays = global.CLIENT_send_replays = (client, room) ->
  return false unless settings.modules.replay_delay and room.replays.length and room.hostinfo.mode == 1 and !client.replays_sent and !client.closed
  client.replays_sent = true
  i = 0
  for buffer in room.replays
    ++i
    if buffer
      ygopro.stoc_send_chat(client, "${replay_hint_part1}" + i + "${replay_hint_part2}", ygopro.constants.COLORS.BABYBLUE)
      ygopro.stoc_send(client, "REPLAY", buffer)
  return true

SOCKET_flush_data = global.SOCKET_flush_data = (sk, datas) ->
  if !sk or sk.closed
    return false
  for buffer in datas
    sk.write(buffer)
  datas.splice(0, datas.length)
  return true

class Room
  constructor: (info) ->
    @name = info.name
    @pass = info.pass
    @notes = info.notes
    @hostinfo = {}
    @hostinfo.lflist = info.info.lflist
    @hostinfo.rule = info.info.rule
    @hostinfo.mode = info.info.mode
    @hostinfo.duel_rule = info.info.duel_rule
    @hostinfo.no_check_deck = info.info.no_check_deck
    @hostinfo.no_shuffle_deck = info.info.no_shuffle_deck
    @hostinfo.start_lp = info.info.start_lp
    @hostinfo.start_hand = info.info.start_hand
    @hostinfo.draw_count = info.info.draw_count
    @hostinfo.time_limit = info.info.time_limit
    @hostinfo.handshake = info.info.handshake
    @hostinfo.team1 = info.info.team1
    @hostinfo.team2 = info.info.team2
    @hostinfo.best_of = info.info.best_of
    @hostinfo.duel_flag = info.info.duel_flag
    @hostinfo.forbidden_types = info.info.forbidden_types
    @hostinfo.extra_rules = info.info.extra_rules
    #@alive = true
    @players = []
    @player_datas = []
    @status = 'starting'
    #@started = false
    @established = false
    @watcher_buffers = []
    @recorder_buffers = []
    @watchers = []
    @random_type = ''
    @welcome = ''
    @scores = {}
    @decks = {}
    @duel_count = 0
    @death = 0
    @turn = 0
    @duel_stage = ygopro.constants.DUEL_STAGE.BEGIN
    @replays = []
    @first_list = []
    update_core_paths()
    @core_path = get_latest_core_path()
    #now = new Date().getTime();
    @game_id = (((Math.floor(new Date().getTime() / 4) + Math.floor(Math.random()*100000000)) & 0xffffffff) >>> 0)
    ROOM_all.push this

    #if lflists.length
     # if @hostinfo.rule == 1 and @hostinfo.lflist == 0
       # @hostinfo.lflist = _.findIndex lflists, (list)-> list.tcg
    #else
     # @hostinfo.lflist =  -1
    try
      @process = spawn (if @core_path then './cores/'+@core_path+'/./ygopro' else './ygopro'), [], {cwd: 'ygopro'}
      @process_pid = @process.pid
      @process.on 'error', (err)=>
        _.each @players, (player)->
          ygopro.stoc_die(player, err)
        this.delete()
        return
      @process.on 'exit', (code)=>
        @disconnector = 'server' unless @disconnector
        this.delete()
        return
      @process.stdout.setEncoding('utf8')
      @process.stdout.once 'data', (data)=>
        @established = true
        @port = parseInt data
        if @port == settings.port
          @process.kill()
          _.each @players, (player)->
            ygopro.stoc_die(player, "${create_room_failed}")
          return
        _.each @players, (player)=>
          player.server.connect @port, '127.0.0.1', ->
            player.server.write buffer for buffer in player.pre_establish_buffers
            player.established = true
            player.pre_establish_buffers = []
            return
          return
        return
      @process.stderr.on 'data', (data)=>
        data = "Debug: " + data
        data = data.replace(/\n$/, "")
        botServer.write2(data,@)
        log.info "YGOPRO " + data
        ygopro.stoc_send_chat_to_room this, data, ygopro.constants.COLORS.RED
        @has_ygopro_error = true
        @ygopro_error_length = if @ygopro_error_length then @ygopro_error_length + data.length else data.length
        if @ygopro_error_length > 10000
          @send_replays()
          @process.kill()
        return
    catch
      @error = "${create_room_failed}"
  delete: ->
    return if @deleted
    #log.info 'room-delete', this.name, ROOM_all.length
    score_array=[]
    for name, score of @scores
      score_form = { name: name.split('$')[0], score: score, deck: null, name_vpass: name }
      if @decks[name]
        score_form.deck = @decks[name]
      score_array.push score_form
    if settings.modules.random_duel.record_match_scores and @random_type == 'M'
      if score_array.length == 2
        if score_array[0].score != score_array[1].score
          if score_array[0].score > score_array[1].score
            ROOM_player_win(score_array[0].name_vpass)
            ROOM_player_lose(score_array[1].name_vpass)
          else
            ROOM_player_win(score_array[1].name_vpass)
            ROOM_player_lose(score_array[0].name_vpass)
      if score_array.length == 1 # same name
          #log.info score_array[0].name
          ROOM_player_win(score_array[0].name_vpass)
          ROOM_player_lose(score_array[0].name_vpass)
    @watcher_buffers = []
    @recorder_buffers = []
    @players = []
    @watcher.destroy() if @watcher
    @recorder.destroy() if @recorder
    @deleted = true
    index = _.indexOf(ROOM_all, this)
    if settings.modules.reconnect.enabled
      ROOM_clear_disconnect(index)
    ROOM_all[index] = null unless index == -1
    #ROOM_all.splice(index, 1) unless index == -1
    roomlist.delete this if @established and settings.modules.http.websocket_roomlist
    delete_outdated_cores()
    return

  get_playing_player: ->
    playing_player = []
    _.each @players, (player)->
      if player.pos < 4 then playing_player.push player
      return
    return playing_player

  get_host: ->
    host_player = null
    _.each @players, (player)->
      if player.is_host then host_player = player
      return
    return host_player

  set_duel_info: (@hostinfo)->
    ROOM_all.push this

  get_disconnected_count: ->
    if !settings.modules.reconnect.enabled
      return 0
    found = 0
    for player in @get_playing_player() when player.closed
      found++
    return found

  get_old_hostinfo: () -> # Just for supporting websocket roomlist in old MyCard client....
    ret = _.clone(@hostinfo)
    ret.enable_priority = (@hostinfo.duel_rule != 4)
    return ret

  send_replays: () ->
    return false unless settings.modules.replay_delay and @replays.length and @hostinfo.mode == 1
    for player in @players
      CLIENT_send_replays(player, this)
    for player in @watchers
      CLIENT_send_replays(player, this)
    return true

  update_spectator_buffer: () ->
    @watcher_buffers[..] = []
    watcher=@watcher
    struct = ygopro.structs[ygopro.proto_structs.STOC['JOIN_GAME']]
    struct.allocate()
    struct.set(@join_game_buffer)
    buffer = struct.buffer()
    header = Buffer.allocUnsafe(3)
    header.writeUInt16LE(buffer.length + 1, 0)
    header.writeUInt8(0x12, 2)
    @watcher_buffers.push(header)
    @watcher_buffers.push(buffer)

    struct = ygopro.structs[ygopro.proto_structs.STOC['TYPE_CHANGE']]
    struct.allocate()
    struct.set({
        type: 7
    })
    buffer = struct.buffer()
    header = Buffer.allocUnsafe(3)
    header.writeUInt16LE(buffer.length + 1, 0)
    header.writeUInt8(0x13, 2)
    @watcher_buffers.push(header)
    @watcher_buffers.push(buffer)
	
    for player in @players
      struct = ygopro.structs[ygopro.proto_structs.STOC['HS_PLAYER_ENTER']]
      struct.allocate();
      struct.set({
       name: player.name,
       pos: player.pos
      });
      buffer = struct.buffer()
      header = Buffer.allocUnsafe(3)
      header.writeUInt16LE(buffer.length + 1, 0)
      header.writeUInt8(0x20, 2)
      @watcher_buffers.push(header)
      @watcher_buffers.push(buffer)
    header = Buffer.allocUnsafe(3)
    header.writeUInt16LE(1, 0)
    header.writeUInt8(0x15, 2)
    @watcher_buffers.push(header)
    header = Buffer.allocUnsafe(3)
    header.writeUInt16LE(1, 0)
    header.writeUInt8(0x8, 2)
    @watcher_buffers.push(header)
    return

  connect: (client)->
    @players.push client
    client.join_time = moment()
    if @random_type
      client.abuse_count = 0
      host_player = @get_host()
      if host_player && (host_player != client)
        # 进来时已经有人在等待了，互相记录为匹配过
        ROOM_players_oppentlist[host_player.ip] = client.ip
        ROOM_players_oppentlist[client.ip] = host_player.ip
      else
        # 第一个玩家刚进来，还没就位
        ROOM_players_oppentlist[client.ip] = null

    if @established
      roomlist.update(this) if @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.http.websocket_roomlist
      client.server.connect @port, '127.0.0.1', ->
        client.server.write buffer for buffer in client.pre_establish_buffers
        client.established = true
        client.pre_establish_buffers = []
        return
    return

  disconnect: (client, error)->
    if client.had_new_reconnection
      return
    if client.is_post_watcher
      ygopro.stoc_send_chat_to_room this, "#{client.name} ${quit_watch}" + if error then ": #{error}" else ''
      index = _.indexOf(@watchers, client)
      @watchers.splice(index, 1) unless index == -1
      #client.room = null
      client.server.destroy()
    else
      #log.info(client.name, @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN, @disconnector, @random_type, @players.length)
      index = _.indexOf(@players, client)
      @players.splice(index, 1) unless index == -1
      if @duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and @disconnector != 'server' and client.pos < 4
        @finished = true
        if !@finished_by_death
          @scores[client.name_vpass] = -9
          if @random_type and not client.flee_free and (!settings.modules.reconnect.enabled or @get_disconnected_count() == 0)
            ROOM_ban_player(client.name, client.ip, "${random_ban_reason_flee}")
            if settings.modules.random_duel.record_match_scores and @random_type == 'M'
              ROOM_player_flee(client.name_vpass)
      if @players.length and client.is_host and !(@duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and client.pos <= 3)
        left_name = (if settings.modules.hide_name and @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN then "********" else client.name)
        # ygopro.stoc_send_chat_to_room this, "#{left_name} ${left_game}" + if error then ": #{error}" else ''
        roomlist.update(this) if  @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and settings.modules.http.websocket_roomlist
        #client.room = null
      else
        @send_replays()
        @process.kill()
        #client.room = null
        this.delete()
      if !CLIENT_reconnect_unregister(client, false, true)
        client.server.destroy()
    return

  start_death: () ->
    if @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or @death
      return false
    oppo_pos = if @hostinfo.mode == 2 then 2 else 1
    if @duel_stage == ygopro.constants.DUEL_STAGE.DUELING
      switch settings.modules.http.quick_death_rule
        when 3
          @death = -2
          ygopro.stoc_send_chat_to_room(this, "${death_start_phase}", ygopro.constants.COLORS.BABYBLUE)
        else
          @death = (if @turn then @turn + 4 else 5)
          ygopro.stoc_send_chat_to_room(this, "${death_start}", ygopro.constants.COLORS.BABYBLUE)
    else                                           # Extra duel started in siding
      switch settings.modules.http.quick_death_rule
        when 2,3
          if @scores[@dueling_players[0].name_vpass] == @scores[@dueling_players[oppo_pos].name_vpass]
            if settings.modules.http.quick_death_rule == 3
              @death = -1
              ygopro.stoc_send_chat_to_room(this, "${death_start_quick}", ygopro.constants.COLORS.BABYBLUE)
            else
              @death = 5
              ygopro.stoc_send_chat_to_room(this, "${death_start_siding}", ygopro.constants.COLORS.BABYBLUE)
          else
            win_pos = if @scores[@dueling_players[0].name_vpass] > @scores[@dueling_players[oppo_pos].name_vpass] then 0 else oppo_pos
            @finished_by_death = true
            ygopro.stoc_send_chat_to_room(this, "${death2_finish_part1}" + @dueling_players[win_pos].name + "${death2_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
            CLIENT_send_replays(@dueling_players[oppo_pos - win_pos], this) if @hostinfo.mode == 1
            ygopro.stoc_send(@dueling_players[oppo_pos - win_pos], 'DUEL_END')
            ygopro.stoc_send(@dueling_players[oppo_pos - win_pos + 1], 'DUEL_END') if @hostinfo.mode == 2
            @scores[@dueling_players[oppo_pos - win_pos].name_vpass] = -1
            CLIENT_kick(@dueling_players[oppo_pos - win_pos])
            CLIENT_kick(@dueling_players[oppo_pos - win_pos + 1]) if @hostinfo.mode == 2
        when 1
          @death = -1
          ygopro.stoc_send_chat_to_room(this, "${death_start_quick}", ygopro.constants.COLORS.BABYBLUE)
        else
          @death = 5
          ygopro.stoc_send_chat_to_room(this, "${death_start_siding}", ygopro.constants.COLORS.BABYBLUE)
    return true

  cancel_death: () ->
    if @duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or !@death
      return false
    @death = 0
    ygopro.stoc_send_chat_to_room(this, "${death_cancel}", ygopro.constants.COLORS.BABYBLUE)
    return true

# 网络连接
net.createServer (client) ->
  client.ip = client.remoteAddress
  client.is_local = client.ip and (client.ip.includes('127.0.0.1'))

  connect_count = ROOM_connected_ip[client.ip] or 0
  if !settings.modules.test_mode.no_connect_count_limit and !client.is_local
    connect_count++
  ROOM_connected_ip[client.ip] = connect_count
  #log.info "connect", client.ip, ROOM_connected_ip[client.ip]

  # server stand for the connection to ygopro server process
  server = new net.Socket()
  client.server = server
  server.client = client

  client.setTimeout(2000) #连接前超时2秒

  # 释放处理
  client.on 'close', (had_error) ->
    #log.info "client closed", client.name, had_error
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    #log.info "disconnect", client.ip, ROOM_connected_ip[client.ip]
    unless client.closed
      client.closed = true
      if settings.modules.heartbeat_detection.enabled
        CLIENT_heartbeat_unregister(client)
      if room
        if !CLIENT_reconnect_register(client, client.rid)
          room.disconnect(client)
      else if !client.had_new_reconnection
        client.server.destroy()
    return

  client.on 'error', (error)->
    #log.info "client error", client.name, error
    room=ROOM_all[client.rid]
    connect_count = ROOM_connected_ip[client.ip]
    if connect_count > 0
      connect_count--
    ROOM_connected_ip[client.ip] = connect_count
    #log.info "err disconnect", client.ip, ROOM_connected_ip[client.ip]
    unless client.closed
      client.closed = true
      if room
        if !CLIENT_reconnect_register(client, client.rid, error)
          room.disconnect(client, error)
      else if !client.had_new_reconnection
        client.server.destroy()
    return

  client.on 'timeout', ()->
    unless settings.modules.reconnect.enabled and (disconnect_list[CLIENT_get_authorize_key(client)] or client.had_new_reconnection)
      client.destroy()
    return

  server.on 'close', (had_error) ->
    #log.info "server closed", server.client.name, had_error
    room=ROOM_all[server.client.rid]
    #log.info "server close", server.client.ip, ROOM_connected_ip[server.client.ip]
    room.disconnector = 'server' if room
    server.closed = true unless server.closed
    if !server.client
      return
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_closed}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  server.on 'error', (error)->
    #log.info "server error", client.name, error
    room=ROOM_all[server.client.rid]
    #log.info "server err close", client.ip, ROOM_connected_ip[client.ip]
    room.disconnector = 'server' if room
    server.closed = error
    if !server.client
      return
    unless server.client.closed
      ygopro.stoc_send_chat(server.client, "${server_error}: #{error}", ygopro.constants.COLORS.RED)
      #if room and settings.modules.replay_delay
      #  room.send_replays()
      CLIENT_kick(server.client)
      SERVER_clear_disconnect(server)
    return

  if ROOM_bad_ip[client.ip] > 5 or ROOM_connected_ip[client.ip] > 10
    log.info 'BAD IP', client.ip
    CLIENT_kick(client)
    return

  # 需要重构
  # 客户端到服务端(ctos)协议分析

  client.pre_establish_buffers = new Array()

  client.on 'data', (ctos_buffer) ->
    if client.is_post_watcher
      room=ROOM_all[client.rid]
      room.watcher.write ctos_buffer if room and !CLIENT_is_banned_by_mc(client)
    else
      #ctos_buffer = Buffer.alloc(0)
      ctos_message_length = 0
      ctos_proto = 0
      #ctos_buffer = Buffer.concat([ctos_buffer, data], ctos_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

      datas = []

      looplimit = 0

      while true
        if ctos_message_length == 0
          if ctos_buffer.length >= 2
            ctos_message_length = ctos_buffer.readUInt16LE(0)
          else
            log.warn("bad ctos_buffer length", client.ip) unless ctos_buffer.length == 0
            break
        else if ctos_proto == 0
          if ctos_buffer.length >= 3
            ctos_proto = ctos_buffer.readUInt8(2)
          else
            log.warn("bad ctos_proto length", client.ip)
            break
        else
          if ctos_buffer.length >= 2 + ctos_message_length
            #console.log "CTOS", ygopro.constants.CTOS[ctos_proto]
            cancel = false
            if settings.modules.reconnect.enabled and client.pre_reconnecting and ygopro.constants.CTOS[ctos_proto] != 'UPDATE_DECK'
              cancel = true
            b = ctos_buffer.slice(3, ctos_message_length - 1 + 3)
            info = null
            struct = ygopro.structs[ygopro.proto_structs.CTOS[ygopro.constants.CTOS[ctos_proto]]]
            if struct and !cancel
              struct._setBuff(b)
              info = _.clone(struct.fields)
            if ygopro.ctos_follows_before[ctos_proto] and !cancel
              for ctos_event in ygopro.ctos_follows_before[ctos_proto]
                result = ctos_event.callback b, info, client, client.server, datas
                if result and ctos_event.synchronous
                  cancel = true
            if struct and !cancel
              struct._setBuff(b)
              info = _.clone(struct.fields)
            if ygopro.ctos_follows[ctos_proto] and !cancel
              result = ygopro.ctos_follows[ctos_proto].callback b, info, client, client.server, datas
              if result and ygopro.ctos_follows[ctos_proto].synchronous
                cancel = true
            if struct and !cancel
              struct._setBuff(b)
              info = _.clone(struct.fields)
            if ygopro.ctos_follows_after[ctos_proto] and !cancel
              for ctos_event in ygopro.ctos_follows_after[ctos_proto]
                result = ctos_event.callback b, info, client, client.server, datas
                if result and ctos_event.synchronous
                  cancel = true
            datas.push ctos_buffer.slice(0, 2 + ctos_message_length) unless cancel
            ctos_buffer = ctos_buffer.slice(2 + ctos_message_length)
            ctos_message_length = 0
            ctos_proto = 0
          else
            log.warn("bad ctos_message length", client.ip, ctos_buffer.length, ctos_message_length, ctos_proto) if ctos_message_length != 17735
            break

        looplimit++
        #log.info(looplimit)
        if looplimit > 800 or ROOM_bad_ip[client.ip] > 5
          log.info("error ctos", client.name, client.ip)
          bad_ip_count = ROOM_bad_ip[client.ip]
          if bad_ip_count
            ROOM_bad_ip[client.ip] = bad_ip_count + 1
          else
            ROOM_bad_ip[client.ip] = 1
          CLIENT_kick(client)
          break
      if !client.server
        return
      if client.established
        client.server.write buffer for buffer in datas
      else
        client.pre_establish_buffers.push buffer for buffer in datas

    return

  # 服务端到客户端(stoc)
  server.on 'data', (stoc_buffer)->
    #stoc_buffer = Buffer.alloc(0)
    stoc_message_length = 0
    stoc_proto = 0
    #stoc_buffer = Buffer.concat([stoc_buffer, data], stoc_buffer.length + data.length) #buffer的错误使用方式，好孩子不要学

    #unless ygopro.stoc_follows[stoc_proto] and ygopro.stoc_follows[stoc_proto].synchronous
    #server.client.write data
    datas = []

    looplimit = 0

    while true
      if stoc_message_length == 0
        if stoc_buffer.length >= 2
          stoc_message_length = stoc_buffer.readUInt16LE(0)
        else
          log.warn("bad stoc_buffer length", server.client.ip) unless stoc_buffer.length == 0
          break
      else if stoc_proto == 0
        if stoc_buffer.length >= 3
          stoc_proto = stoc_buffer.readUInt8(2)
        else
          log.warn("bad stoc_proto length", server.client.ip)
          break
      else
        if stoc_buffer.length >= 2 + stoc_message_length
          #console.log "STOC", ygopro.constants.STOC[stoc_proto]
          cancel = false
          b = stoc_buffer.slice(3, stoc_message_length - 1 + 3)
          info = null
          struct = ygopro.structs[ygopro.proto_structs.STOC[ygopro.constants.STOC[stoc_proto]]]
          if struct and !cancel
            struct._setBuff(b)
            info = _.clone(struct.fields)
          if ygopro.stoc_follows_before[stoc_proto] and !cancel
            for stoc_event in ygopro.stoc_follows_before[stoc_proto]
              result = stoc_event.callback b, info, server.client, server, datas
              if result and stoc_event.synchronous
                cancel = true
          if struct and !cancel
            struct._setBuff(b)
            info = _.clone(struct.fields)
          if ygopro.stoc_follows[stoc_proto] and !cancel
            result = ygopro.stoc_follows[stoc_proto].callback b, info, server.client, server, datas
            if result and ygopro.stoc_follows[stoc_proto].synchronous
              cancel = true
          if struct and !cancel
            struct._setBuff(b)
            info = _.clone(struct.fields)
          if ygopro.stoc_follows_after[stoc_proto] and !cancel
            for stoc_event in ygopro.stoc_follows_after[stoc_proto]
              result = stoc_event.callback b, info, server.client, server, datas
              if result and stoc_event.synchronous
                cancel = true
          datas.push stoc_buffer.slice(0, 2 + stoc_message_length) unless cancel
          stoc_buffer = stoc_buffer.slice(2 + stoc_message_length)
          stoc_message_length = 0
          stoc_proto = 0
        else
          log.warn("bad stoc_message length", server.client.ip)
          break

      looplimit++
      #log.info(looplimit)
      if looplimit > 800
        log.info("error stoc", server.client.name)
        server.destroy()
        break
    if server.client and !server.client.closed
      server.client.write buffer for buffer in datas

    return
  return
.listen settings.port, ->
  log.info "server started", settings.port
  return

if settings.modules.stop
  log.info "NOTE: server not open due to config, ", settings.modules.stop

# 功能模块
# return true to cancel a synchronous message

ygopro.ctos_follow 'PLAYER_INFO', true, (buffer, info, client, server, datas)->
  # checkmate use username$password, but here don't
  # so remove the password
  name_full =info.name.split("$")
  name = name_full[0]
  vpass = name_full[1]
  if vpass and !vpass.length
    vpass = null
  if (_.any(settings.ban.illegal_id, (badid) ->
    regexp = new RegExp(badid, 'i')
    matchs = name.match(regexp)
    if matchs
      name = matchs[1]
      return true
    return false
  , name))
    client.rag = true
  struct = ygopro.structs["CTOS_PlayerInfo"]
  struct._setBuff(buffer)
  struct.set("name", name)
  buffer = struct.buffer
  client.name = name
  client.vpass = vpass
  client.name_vpass = if vpass then name + "$" + vpass else name

  if not settings.modules.i18n.auto_pick or client.is_local
    client.lang=settings.modules.i18n.default
  else
    geo = geoip.lookup(client.ip)
    if not geo
      log.warn("fail to locate ip", client.name, client.ip)
      client.lang=settings.modules.i18n.fallback
    else
      if lang=settings.modules.i18n.map[geo.country]
        client.lang=lang
      else
        #log.info("Not in map", geo.country, client.name, client.ip)
        client.lang=settings.modules.i18n.fallback
  return false

ygopro.ctos_follow 'CREATE_GAME', false, (buffer, info, client, server, datas)->
  info.pass=info.pass.trim()
  client.pass = info.pass
  
  if !client.name or client.name==""
    ygopro.stoc_die(client, "${bad_user_name}")

  else if ROOM_connected_ip[client.ip] > 5
    log.warn("MULTI LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${too_much_connection}" + client.ip)

  else if _.indexOf(settings.ban.banned_user, client.name) > -1 #账号被封
    settings.ban.banned_ip.push(client.ip)
    setting_save(settings)
    log.warn("BANNED USER LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_user_login}")

  else if _.indexOf(settings.ban.banned_ip, client.ip) > -1 #IP被封
    log.warn("BANNED IP LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_ip_login}")

  else if _.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if _.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if _.any(badwords.level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level1}")

  else if _.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = info.notes)
    log.warn("BAD NOTES LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_notes_level3}")

  else if _.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = info.notes)
    log.warn("BAD NOTES LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_notes_level2}")

  else if _.any(badwords.level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = info.notes)
    log.warn("BAD NOTES LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_notes_level1}")
  else
    room = new Room(info)
    if !room
      ygopro.stoc_die(client, "${server_full}")
    client.setTimeout(300000) #连接后超时5分钟
    client.rid = _.indexOf(ROOM_all, room)
    room.connect(client)
    ygopro.stoc_send(client, 'CREATE_GAME', {
      gameid: room.game_id
    })
  return

ygopro.ctos_follow 'JOIN_GAME', false, (buffer, info, client, server, datas)->
#log.info info
  info.pass=info.pass.trim()
  client.pass = info.pass
  # if CLIENT_is_able_to_reconnect(client) or CLIENT_is_able_to_kick_reconnect(client)
    # CLIENT_pre_reconnect(client)
    # return
  # else 
  if !client.name or client.name==""
    ygopro.stoc_die(client, "${bad_user_name}")
	
  else if info.version2 != settings.version # and (info.version < 9020 or settings.version != 4927) #强行兼容23333版
    ygopro.stoc_send client, 'ERROR_MSG', {
      msg: 5
      code: settings.version
    }
    CLIENT_kick(client)

  else if ROOM_connected_ip[client.ip] > 5
    log.warn("MULTI LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${too_much_connection}" + client.ip)

  else if _.indexOf(settings.ban.banned_user, client.name) > -1 #账号被封
    settings.ban.banned_ip.push(client.ip)
    setting_save(settings)
    log.warn("BANNED USER LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_user_login}")

  else if _.indexOf(settings.ban.banned_ip, client.ip) > -1 #IP被封
    log.warn("BANNED IP LOGIN", client.name, client.ip)
    ygopro.stoc_die(client, "${banned_ip_login}")

  else if _.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 3", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level3}")

  else if _.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 2", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level2}")

  else if _.any(badwords.level1, (badword) ->
    regexp = new RegExp(badword, 'i')
    return name.match(regexp)
  , name = client.name)
    log.warn("BAD NAME LEVEL 1", client.name, client.ip)
    ygopro.stoc_die(client, "${bad_name_level1}")

  #else if info.pass.length && !ROOM_validate(info.pass)
  #  ygopro.stoc_die(client, "${invalid_password_room}")

  else
    #if info.version >= 9020 and settings.version == 4927 #强行兼容23333版
    #  info.version = settings.version
    #  struct = ygopro.structs["CTOS_JoinGame"]
    #  struct._setBuff(buffer)
    #  struct.set("version", info.version)
    #  buffer = struct.buffer
    #  #ygopro.stoc_send_chat(client, "看起来你是YGOMobile的用户，请记得更新先行卡补丁，否则会看到白卡", ygopro.constants.COLORS.GREEN)

    #log.info 'join_game',info.pass, client.name
    room = ROOM_find_by_game_id(info.gameid)
    if !room
      ygopro.stoc_die(client, "${room_not_found}")
    else if room.error
      ygopro.stoc_die(client, room.error)
    else if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
      if !room.hostinfo.no_watch
        client.setTimeout(300000) #连接后超时5分钟
        client.rid = _.indexOf(ROOM_all, room)
        client.is_post_watcher = true
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${watch_join}")
        room.watchers.push client
        ygopro.stoc_send_chat(client, "${watch_watching}", ygopro.constants.COLORS.BABYBLUE)
        # room.connect(client)
        ygopro.stoc_send(client, 'CATCHUP', {
              val: 1
            })
        for buffer in room.watcher_buffers
            client.write buffer
        ygopro.stoc_send(client, 'CATCHUP', {
              val: 0
            })
      else
        ygopro.stoc_die(client, "${watch_denied}")
    else if room.hostinfo.no_watch and room.players.length >= (if room.hostinfo.mode == 2 then 4 else 2)
      ygopro.stoc_die(client, "${watch_denied_room}")
    else
      client.setTimeout(300000) #连接后超时5分钟
      client.rid = _.indexOf(ROOM_all, room)
      room.connect(client)
  return

ygopro.stoc_follow 'JOIN_GAME', false, (buffer, info, client, server, datas)->
  #欢迎信息
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  if !room.join_game_buffer
    room.join_game_buffer = buffer
  if settings.modules.welcome
    ygopro.stoc_send_chat(client, settings.modules.welcome, ygopro.constants.COLORS.GREEN)
  if room.welcome
    ygopro.stoc_send_chat(client, room.welcome, ygopro.constants.COLORS.BABYBLUE)
  if settings.modules.random_duel.record_match_scores and room.random_type == 'M'
    ygopro.stoc_send_chat_to_room(room, ROOM_player_get_score(client), ygopro.constants.COLORS.GREEN)
    for player in room.players when player.pos != 7 and player != client
      ygopro.stoc_send_chat(client, ROOM_player_get_score(player), ygopro.constants.COLORS.GREEN)
  if !room.recorder
    room.recorder = recorder = net.connect room.port, ->
      ygopro.ctos_send recorder, 'PLAYER_INFO', {
        name: "Marshtomp"
      }
      ygopro.ctos_send recorder, 'JOIN_GAME', {
        version: settings.version,
        pass: "Marshtomp"
      }
      ygopro.ctos_send recorder, 'HS_TOOBSERVER'
      return

    recorder.on 'data', (data)->
      room=ROOM_all[client.rid]
      return unless room
      room.recorder_buffers.push data
      return

    recorder.on 'error', (error)->
      return

  if !room.watcher and !room.hostinfo.no_watch
    room.watcher = watcher = if settings.modules.test_mode.watch_public_hand then room.recorder else net.connect room.port, ->
      ygopro.ctos_send watcher, 'PLAYER_INFO', {
        name: "the Big Brother"
      }
      ygopro.ctos_send watcher, 'JOIN_GAME', {
        version2: settings.version,
        pass: room.pass
      }
      ygopro.ctos_send watcher, 'HS_TOOBSERVER'
      return

    watcher.on 'data', (data)->
      room=ROOM_all[client.rid]
      return unless room
      room.watcher_buffers.push data
      for w in room.watchers
        w.write data if w #a WTF fix
      return

    watcher.on 'error', (error)->
#log.error "watcher error", error
      return
  return

# 登场台词
load_dialogues = global.load_dialogues = () ->
  request
    url: settings.modules.dialogues.get
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "dialogues bad json", body
    else if error or !body
      log.warn 'dialogues error', error, response
    else
      setting_change(dialogues, "dialogues", body)
      log.info "dialogues loaded", _.size dialogues.dialogues
    return
  return

if settings.modules.dialogues.get
  load_dialogues()

ygopro.stoc_follow_after 'GAME_MSG', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  msg = buffer.readInt8(0)

  if ygopro.constants.MSG[msg] == 'SELECT_YESNO'
    stringid = buffer.readUInt32LE(2)
    if stringid == 1989
      room.update_spectator_buffer()
  return false

ygopro.stoc_follow_after 'CHANGE_SIDE', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  room.update_spectator_buffer()
  return false

ygopro.stoc_follow 'GAME_MSG', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  msg = buffer.readInt8(0)
  if settings.modules.retry_handle.enabled
    if ygopro.constants.MSG[msg] == 'RETRY'
      if !client.retry_count?
        client.retry_count = 0
      client.retry_count++
      log.warn "MSG_RETRY detected", client.name, client.ip, msg, client.retry_count
      if settings.modules.retry_handle.max_retry_count and client.retry_count >= settings.modules.retry_handle.max_retry_count
        ygopro.stoc_send_chat_to_room(room, client.name + "${retry_too_much_room_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_room_part2}", ygopro.constants.COLORS.BABYBLUE)
        ygopro.stoc_send_chat(client, "${retry_too_much_part1}" + settings.modules.retry_handle.max_retry_count + "${retry_too_much_part2}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays(client, room)
        CLIENT_kick(client)
        return true
      if client.last_game_msg
        if settings.modules.retry_handle.max_retry_count
          ygopro.stoc_send_chat(client, "${retry_part1}" + client.retry_count + "${retry_part2}" + settings.modules.retry_handle.max_retry_count + "${retry_part3}", ygopro.constants.COLORS.RED)
        else
          ygopro.stoc_send_chat(client, "${retry_not_counted}", ygopro.constants.COLORS.BABYBLUE)
        if client.last_hint_msg
          ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
        ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
        return true
    else
      client.last_game_msg = buffer
      client.last_game_msg_title = ygopro.constants.MSG[msg]
      # log.info(client.name, client.last_game_msg_title)
  else if ygopro.constants.MSG[msg] != 'RETRY'
    client.last_game_msg = buffer
    client.last_game_msg_title = ygopro.constants.MSG[msg]
    # log.info(client.name, client.last_game_msg_title)

  if (msg >= 10 and msg < 30) or msg == 132 or (msg >= 140 and msg <= 144) #SELECT和ANNOUNCE开头的消息
    room.waiting_for_player = client
    room.last_active_time = moment()
  #log.info("#{ygopro.constants.MSG[msg]}等待#{room.waiting_for_player.name}")

  #log.info 'MSG', ygopro.constants.MSG[msg]
  if ygopro.constants.MSG[msg] == 'START'
    playertype = buffer.readUInt8(1)
    client.is_first = !(playertype & 0xf)
    if client.is_first and (room.hostinfo.mode != 2 or client.pos == 0 or client.pos == 2)
      room.first_list[room.duel_count - 1] = client.name_vpass
    client.lp = room.hostinfo.start_lp
    client.card_count = 0 if room.hostinfo.mode != 2
    room.duel_stage = ygopro.constants.DUEL_STAGE.DUELING
    if client.pos == 0
      room.turn = 0
      room.duel_count++
      if room.death and room.duel_count > 1
        if room.death == -1
          ygopro.stoc_send_chat_to_room(room, "${death_start_final}", ygopro.constants.COLORS.BABYBLUE)
        else
          ygopro.stoc_send_chat_to_room(room, "${death_start_extra}", ygopro.constants.COLORS.BABYBLUE)
    if settings.modules.retry_handle.enabled
      client.retry_count = 0
      client.last_game_msg = null

  #ygopro.stoc_send_chat_to_room(room, "LP跟踪调试信息: #{client.name} 初始LP #{client.lp}")

  if ygopro.constants.MSG[msg] == 'HINT'
    hint_type = buffer.readUInt8(1)
    if hint_type == 3
      client.last_hint_msg = buffer

  if ygopro.constants.MSG[msg] == 'NEW_TURN'
    if client.pos == 0
      room.turn++
      if room.death and room.death != -2
        if room.turn >= room.death
          oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
          if room.dueling_players[0].lp != room.dueling_players[oppo_pos].lp and room.turn > 1
            win_pos = if room.dueling_players[0].lp > room.dueling_players[oppo_pos].lp then 0 else oppo_pos
            ygopro.stoc_send_chat_to_room(room, "${death_finish_part1}" + room.dueling_players[win_pos].name + "${death_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
            if room.hostinfo.mode == 2
              room.finished_by_death = true
              ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
              ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END')
              room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
              CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
              CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1])
            else
              ygopro.ctos_send(room.dueling_players[oppo_pos - win_pos].server, 'SURRENDER')
          else
            room.death = -1
            ygopro.stoc_send_chat_to_room(room, "${death_remain_final}", ygopro.constants.COLORS.BABYBLUE)
        else
          ygopro.stoc_send_chat_to_room(room, "${death_remain_part1}" + (room.death - room.turn) + "${death_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    if client.surrend_confirm
      client.surrend_confirm = false
      ygopro.stoc_send_chat(client, "${surrender_canceled}", ygopro.constants.COLORS.BABYBLUE)

  if ygopro.constants.MSG[msg] == 'NEW_PHASE'
    phase = buffer.readInt16LE(1)
    oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
    if client.pos == 0 and room.death == -2 and not (phase == 0x1 and room.turn < 2)
      if room.dueling_players[0].lp != room.dueling_players[oppo_pos].lp
        win_pos = if room.dueling_players[0].lp > room.dueling_players[oppo_pos].lp then 0 else oppo_pos
        ygopro.stoc_send_chat_to_room(room, "${death_finish_part1}" + room.dueling_players[win_pos].name + "${death_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
        if room.hostinfo.mode == 2
          room.finished_by_death = true
          ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
          ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END')
          room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
          CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
          CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1])
        else
          ygopro.ctos_send(room.dueling_players[oppo_pos - win_pos].server, 'SURRENDER')
      else
        room.death = -1
        ygopro.stoc_send_chat_to_room(room, "${death_remain_final}", ygopro.constants.COLORS.BABYBLUE)

  if ygopro.constants.MSG[msg] == 'WIN' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first or pos == 2 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    reason = buffer.readUInt8(2)
    #log.info {winner: pos, reason: reason}
    #room.duels.push {winner: pos, reason: reason}
    room.winner = pos
    room.turn = 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.END
    if settings.modules.heartbeat_detection.enabled
      for player in room.players
        player.heartbeat_protected = false
      delete room.long_resolve_card
      delete room.long_resolve_chain
    if room and !room.finished and room.dueling_players[pos]
      room.winner_name = room.dueling_players[pos].name_vpass
      #log.info room.dueling_players, pos
      room.scores[room.winner_name] = room.scores[room.winner_name] + 1
      if room.match_kill
        room.match_kill = false
        room.scores[room.winner_name] = 99
    if room.death
      if settings.modules.http.quick_death_rule == 1 or settings.modules.http.quick_death_rule == 3
        room.death = -1
      else
        room.death = 5

  if ygopro.constants.MSG[msg] == 'MATCH_KILL' and client.pos == 0
    room.match_kill = true

  #lp跟踪
  if ygopro.constants.MSG[msg] == 'DAMAGE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_opponent}", ygopro.constants.COLORS.PINK)

  if ygopro.constants.MSG[msg] == 'RECOVER' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp += val

  if ygopro.constants.MSG[msg] == 'LPUPDATE' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp = val

  if ygopro.constants.MSG[msg] == 'PAY_LPCOST' and client.pos == 0
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    pos = pos * 2 if pos >= 0 and room.hostinfo.mode == 2
    val = buffer.readInt32LE(2)
    room.dueling_players[pos].lp -= val
    room.dueling_players[pos].lp = 0 if room.dueling_players[pos].lp < 0
    if 0 < room.dueling_players[pos].lp <= 100
      ygopro.stoc_send_chat_to_room(room, "${lp_low_self}", ygopro.constants.COLORS.PINK)

  #track card count
  #todo: track card count in tag mode
  if ygopro.constants.MSG[msg] == 'MOVE' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(5)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(6)
    client.card_count-- if (loc & 0xe) and pos == 0
    pos = buffer.readUInt8(9)
    pos = 1 - pos unless client.is_first
    loc = buffer.readUInt8(10)
    client.card_count++ if (loc & 0xe) and pos == 0

  if ygopro.constants.MSG[msg] == 'DRAW' and room.hostinfo.mode != 2
    pos = buffer.readUInt8(1)
    pos = 1 - pos unless client.is_first
    if pos == 0
      count = buffer.readInt8(2)
      client.card_count += count

  # check panel confirming cards in heartbeat
  if settings.modules.heartbeat_detection.enabled and ygopro.constants.MSG[msg] == 'CONFIRM_CARDS'
    check = false
    count = buffer.readInt8(2)
    max_loop = 3 + (count - 1) * 7
    deck_found = 0
    limbo_found = 0 # support custom cards which may be in location 0 in KoishiPro or EdoPro
    for i in [3..max_loop] by 7
      loc = buffer.readInt8(i + 5)
      if (loc & 0x41) > 0
        deck_found++
      else if loc == 0
        limbo_found++
      if (deck_found > 0 and count > 1) or limbo_found > 0
        check = true
        break
    if check
      #console.log("Confirming cards:" + client.name)
      client.heartbeat_protected = true

  # chain detection
  if settings.modules.heartbeat_detection.enabled and client.pos == 0
    if ygopro.constants.MSG[msg] == 'CHAINING'
      card = buffer.readUInt32LE(1)
      found = false
      for id in long_resolve_cards when id == card
        found = true
        break
      if found
        room.long_resolve_card = card
        # console.log(0,card)
      else
        delete room.long_resolve_card
    else if ygopro.constants.MSG[msg] == 'CHAINED' and room.long_resolve_card
      chain = buffer.readInt8(1)
      if !room.long_resolve_chain
        room.long_resolve_chain = []
      room.long_resolve_chain[chain] = true
      # console.log(1,chain)
      delete room.long_resolve_card
    else if ygopro.constants.MSG[msg] == 'CHAIN_SOLVING' and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(2,chain)
      if room.long_resolve_chain[chain]
        for player in room.get_playing_player()
          player.heartbeat_protected = true
    else if (ygopro.constants.MSG[msg] == 'CHAIN_NEGATED' or ygopro.constants.MSG[msg] == 'CHAIN_DISABLED') and room.long_resolve_chain
      chain = buffer.readInt8(1)
      # console.log(3,chain)
      delete room.long_resolve_chain[chain]
    else if ygopro.constants.MSG[msg] == 'CHAIN_END'
      # console.log(4,chain)
      delete room.long_resolve_card
      delete room.long_resolve_chain

  #登场台词
  if settings.modules.dialogues.enabled
    if ygopro.constants.MSG[msg] == 'SUMMONING' or ygopro.constants.MSG[msg] == 'SPSUMMONING' or ygopro.constants.MSG[msg] == 'CHAINING'
      card = buffer.readUInt32LE(1)
      trigger_location = buffer.readUInt8(6)
      if dialogues.dialogues[card] and (ygopro.constants.MSG[msg] != 'CHAINING' or (trigger_location & 0x8) and client.ready_trap)
        for line in _.lines dialogues.dialogues[card][Math.floor(Math.random() * dialogues.dialogues[card].length)]
          ygopro.stoc_send_chat(client, line, ygopro.constants.COLORS.PINK)
    if ygopro.constants.MSG[msg] == 'POS_CHANGE'
      loc = buffer.readUInt8(6)
      ppos = buffer.readUInt8(8)
      cpos = buffer.readUInt8(9)
      client.ready_trap = !!(loc & 0x8) and !!(ppos & 0xa) and !!(cpos & 0x5)
    else if ygopro.constants.MSG[msg] != 'UPDATE_CARD' and ygopro.constants.MSG[msg] != 'WAITING'
      client.ready_trap = false
  return false

#房间管理
ygopro.ctos_follow 'HS_TOOBSERVER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.hostinfo.no_watch
    ygopro.stoc_send_chat(client, "${watch_denied_room}", ygopro.constants.COLORS.RED)
    return true
  if client.is_local
    return false
  for player in room.players
    if player == client
      ygopro.stoc_send_chat(client, "${cannot_to_observer}", ygopro.constants.COLORS.BABYBLUE)
      return true
  return false

ygopro.ctos_follow 'HS_KICK', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  for player in room.players
    if player and player.pos == info.pos and player != client
      client.kick_count = if client.kick_count then client.kick_count+1 else 1
      if client.kick_count>=5 and room.random_type
        ygopro.stoc_send_chat_to_room(room, "#{client.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
        CLIENT_kick(client)
        return true
      ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_player}", ygopro.constants.COLORS.RED)
  return false

ygopro.stoc_follow 'TYPE_CHANGE', true, (buffer, info, client, server, datas)->
  selftype = info.type & 0xf
  is_host = ((info.type >> 4) & 0xf) != 0
  # if room and room.hostinfo.no_watch and selftype == 7
  #   ygopro.stoc_die(client, "${watch_denied_room}")
  #   return true
  client.is_host = is_host
  client.pos = selftype
  #console.log "TYPE_CHANGE to #{client.name}:", info, selftype, is_host
  return false

ygopro.stoc_follow 'HS_PLAYER_ENTER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return false unless room and settings.modules.hide_name and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
  pos = info.pos
  if pos < 4 and pos != client.pos
    struct = ygopro.structs["STOC_HS_PlayerEnter"]
    struct._setBuff(buffer)
    struct.set("name", "********")
    buffer = struct.buffer
  return false

ygopro.stoc_follow 'HS_PLAYER_CHANGE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and room.max_player and client.is_host
  pos = info.status >> 4
  is_ready = (info.status & 0xf) == 9
  if pos < room.max_player
      room.ready_player_count_without_host = 0
      for player in room.players
        if player.pos == pos
          player.is_ready = is_ready
        unless player.is_host
          room.ready_player_count_without_host += player.is_ready
      if room.ready_player_count_without_host >= room.max_player - 1
        #log.info "all ready"
        setTimeout (()-> wait_room_start(ROOM_all[client.rid], settings.modules.random_duel.ready_time);return), 1000
  return

ygopro.stoc_follow 'DUEL_END', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and settings.modules.replay_delay and room.hostinfo.mode == 1
  SOCKET_flush_data(client, datas)
  CLIENT_send_replays(client, room)
  if !room.replays_sent_to_watchers
    room.replays_sent_to_watchers = true
    for player in room.players when player and player.pos > 3
      CLIENT_send_replays(player, room)
    for player in room.watchers when player
      CLIENT_send_replays(player, room)

wait_room_start = (room, time)->
  if room and room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN and room.ready_player_count_without_host >= room.max_player - 1
    time -= 1
    if time
      unless time % 5
        ygopro.stoc_send_chat_to_room(room, "#{if time <= 9 then ' ' else ''}#{time}${kick_count_down}", if time <= 9 then ygopro.constants.COLORS.RED else ygopro.constants.COLORS.LIGHTBLUE)
      setTimeout (()-> wait_room_start(room, time);return), 1000
    else
      for player in room.players
        if player and player.is_host
          ROOM_ban_player(player.name, player.ip, "${random_ban_reason_zombie}")
          ygopro.stoc_send_chat_to_room(room, "#{player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
          CLIENT_kick(player)
  return

#tip
ygopro.stoc_send_random_tip = (client)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat(client, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  return
ygopro.stoc_send_random_tip_to_room = (room)->
  if settings.modules.tips.enabled && tips.tips.length
    ygopro.stoc_send_chat_to_room(room, "Tip: " + tips.tips[Math.floor(Math.random() * tips.tips.length)])
  return

load_tips = global.load_tips = ()->
  request
    url: settings.modules.tips.get
    json: true
  , (error, response, body)->
    if _.isString body
      log.warn "tips bad json", body
    else if error or !body
      log.warn 'tips error', error, response
    else
      setting_change(tips, "tips", body)
      log.info "tips loaded", tips.tips.length
    return
  return

if settings.modules.tips.get
  load_tips()
  setInterval ()->
    for room in ROOM_all when room and room.established
      ygopro.stoc_send_random_tip_to_room(room) if room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING or room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN
    return
  , 30000

ygopro.stoc_follow 'DUEL_START', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and !client.reconnecting
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN #first start
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
    room.start_time = moment().format()
    room.turn = 0
    roomlist.start room if settings.modules.http.websocket_roomlist
    #room.duels = []
    room.dueling_players = []
    for player in room.players when player.pos != 7
      room.dueling_players[player.pos] = player
      room.scores[player.name_vpass] = 0
      room.player_datas.push key: CLIENT_get_authorize_key(player), name: player.name
      if room.random_type == 'T'
        # 双打房不记录匹配过
        ROOM_players_oppentlist[player.ip] = null
    if room.hostinfo.auto_death
      ygopro.stoc_send_chat_to_room(room, "${auto_death_part1}#{room.hostinfo.auto_death}${auto_death_part2}", ygopro.constants.COLORS.BABYBLUE)
  if settings.modules.hide_name and room.duel_count == 0
    for player in room.get_playing_player() when player != client
      ygopro.stoc_send(client, 'HS_PLAYER_ENTER', {
        name: player.name,
        pos: player.pos
      })
  if settings.modules.tips.enabled
    ygopro.stoc_send_random_tip(client)
  deck_text = null
  if client.main and client.main.length
    deck_text = '#ygopro-server deck log\n#main\n' + client.main.join('\n') + '\n!side\n' + client.side.join('\n') + '\n'
    room.decks[client.name] = deck_text
  return

ygopro.ctos_follow 'SURRENDER', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if room.duel_stage == ygopro.constants.DUEL_STAGE.BEGIN or room.hostinfo.mode == 2
    return true
  if room.random_type and room.turn < 3 and not client.flee_free and not settings.modules.test_mode.surrender_anytime and not (room.random_type=='M' and settings.modules.random_duel.record_match_scores)
    ygopro.stoc_send_chat(client, "${surrender_denied}", ygopro.constants.COLORS.BABYBLUE)
    return true
  return false

report_to_big_brother = global.report_to_big_brother = (roomname, sender, ip, level, content, match) ->
  return unless settings.modules.big_brother.enabled
  request.post { url : settings.modules.big_brother.post , form : {
    accesskey: settings.modules.big_brother.accesskey,
    roomname: roomname,
    sender: sender,
    ip: ip,
    level: level,
    content: content,
    match: match
  }}, (error, response, body)->
    if error
      log.warn 'BIG BROTHER ERROR', error
    else
      if response.statusCode != 200
        log.warn 'BIG BROTHER FAIL', response.statusCode, roomname, body
      #else
        #log.info 'BIG BROTHER OK', response.statusCode, roomname, body
    return
  return

ygopro.ctos_follow 'CHAT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  msg = _.trim(info.msg)
  cancel = _.startsWith(msg, "/")
  room.last_active_time = moment() unless cancel or not (room.random_type) or room.duel_stage == ygopro.constants.DUEL_STAGE.FINGER or room.duel_stage == ygopro.constants.DUEL_STAGE.FIRSTGO or room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING 
  if (msg.length>100)
    log.warn "SPAM WORD", client.name, client.ip, msg
    client.abuse_count=client.abuse_count+2 if client.abuse_count
    ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  if !(room and (room.random_type))
    return cancel
  if client.abuse_count>=5 or CLIENT_is_banned_by_mc(client)
    log.warn "BANNED CHAT", client.name, client.ip, msg
    ygopro.stoc_send_chat(client, "${banned_chat_tip}" + (if client.ban_mc and client.ban_mc.message then (": " + client.ban_mc.message) else ""), ygopro.constants.COLORS.RED)
    return true
  oldmsg = msg
  if (_.any(badwords.level3, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 3", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 3, oldmsg, RegExp.$1
    cancel = true
    if client.abuse_count>0
      ygopro.stoc_send_chat(client, "${banned_duel_tip}", ygopro.constants.COLORS.RED)
      ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
      ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}", 3)
      CLIENT_send_replays(client, room)
      CLIENT_kick(client)
      return true
    else
      client.abuse_count=client.abuse_count+4
      ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
  else if (client.rag and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN)
    client.rag = false
    #ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  else if (_.any(settings.ban.spam_word, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    #log.warn "SPAM WORD", client.name, client.ip, oldmsg
    client.abuse_count=client.abuse_count+2
    ygopro.stoc_send_chat(client, "${chat_warn_level0}", ygopro.constants.COLORS.RED)
    cancel = true
  else if (_.any(badwords.level2, (badword) ->
    regexp = new RegExp(badword, 'i')
    return msg.match(regexp)
  , msg))
    log.warn "BAD WORD LEVEL 2", client.name, client.ip, oldmsg, RegExp.$1
    report_to_big_brother room.name, client.name, client.ip, 2, oldmsg, RegExp.$1
    client.abuse_count=client.abuse_count+3
    ygopro.stoc_send_chat(client, "${chat_warn_level2}", ygopro.constants.COLORS.RED)
    cancel = true
  else
    _.each(badwords.level1, (badword) ->
      #log.info msg
      regexp = new RegExp(badword, "ig")
      msg = msg.replace(regexp, "**")
      return
    , msg)
    if oldmsg != msg
      log.warn "BAD WORD LEVEL 1", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 1, oldmsg, RegExp.$1
      client.abuse_count=client.abuse_count+1
      ygopro.stoc_send_chat(client, "${chat_warn_level1}")
      struct = ygopro.structs["chat"]
      struct._setBuff(buffer)
      struct.set("msg", msg)
      buffer = struct.buffer
    else if (_.any(badwords.level0, (badword) ->
      regexp = new RegExp(badword, 'i')
      return msg.match(regexp)
    , msg))
      log.info "BAD WORD LEVEL 0", client.name, client.ip, oldmsg, RegExp.$1
      report_to_big_brother room.name, client.name, client.ip, 0, oldmsg, RegExp.$1
  if client.abuse_count>=2
    ROOM_unwelcome(room, client, "${random_ban_reason_abuse}")
  if client.abuse_count>=5
    ygopro.stoc_send_chat_to_room(room, "#{client.name} ${chat_banned}", ygopro.constants.COLORS.RED)
    ROOM_ban_player(client.name, client.ip, "${random_ban_reason_abuse}")
  return cancel

ygopro.ctos_follow 'UPDATE_DECK', true, (buffer, info, client, server, datas)->
  if settings.modules.reconnect.enabled and client.pre_reconnecting
    if !CLIENT_is_able_to_reconnect(client) and !CLIENT_is_able_to_kick_reconnect(client)
      ygopro.stoc_send_chat(client, "${reconnect_failed}", ygopro.constants.COLORS.RED)
      CLIENT_kick(client)
    else if CLIENT_is_able_to_reconnect(client, buffer)
      CLIENT_reconnect(client)
    else if CLIENT_is_able_to_kick_reconnect(client, buffer)
      CLIENT_kick_reconnect(client, buffer)
    else
      ygopro.stoc_send_chat(client, "${deck_incorrect_reconnect}", ygopro.constants.COLORS.RED)
      ygopro.stoc_send(client, 'ERROR_MSG', {
        msg: 2,
        code: 0
      })
      ygopro.stoc_send(client, 'HS_PLAYER_CHANGE', {
        status: (client.pos << 4) | 0xa
      })
    return true
  room=ROOM_all[client.rid]
  return false unless room
  #log.info info
  if info.mainc > 256 or info.sidec > 256 # Prevent attack, see https://github.com/Fluorohydride/ygopro/issues/2174
    CLIENT_kick(client)
    return true
  buff_main = (info.deckbuf[i] for i in [0...info.mainc])
  buff_side = (info.deckbuf[i] for i in [info.mainc...info.mainc + info.sidec])
  client.main = buff_main
  client.side = buff_side
  if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN
    client.selected_preduel = true
    if client.side_tcount
      clearInterval client.side_interval
      client.side_interval = null
      client.side_tcount = null
  else
    client.start_deckbuf = Buffer.from(buffer)
  oppo_pos = if room.hostinfo.mode == 2 then 2 else 1
  if settings.modules.http.quick_death_rule >= 2 and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.death and room.scores[room.dueling_players[0].name_vpass] != room.scores[room.dueling_players[oppo_pos].name_vpass]
    win_pos = if room.scores[room.dueling_players[0].name_vpass] > room.scores[room.dueling_players[oppo_pos].name_vpass] then 0 else oppo_pos
    room.finished_by_death = true
    ygopro.stoc_send_chat_to_room(room, "${death2_finish_part1}" + room.dueling_players[win_pos].name + "${death2_finish_part2}", ygopro.constants.COLORS.BABYBLUE)
    CLIENT_send_replays(room.dueling_players[oppo_pos - win_pos], room) if room.hostinfo.mode == 1
    ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos], 'DUEL_END')
    ygopro.stoc_send(room.dueling_players[oppo_pos - win_pos + 1], 'DUEL_END') if room.hostinfo.mode == 2
    room.scores[room.dueling_players[oppo_pos - win_pos].name_vpass] = -1
    CLIENT_kick(room.dueling_players[oppo_pos - win_pos])
    CLIENT_kick(room.dueling_players[oppo_pos - win_pos + 1]) if room.hostinfo.mode == 2
    return true
  if room.random_type
    if client.pos == 0
      room.waiting_for_player = room.waiting_for_player2
    room.last_active_time = moment()
  return false

ygopro.ctos_follow 'RESPONSE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room and (room.random_type)
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'TIME_LIMIT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if settings.modules.reconnect.enabled
    if client.closed
      ygopro.ctos_send(server, 'TIME_CONFIRM')
      return true
    else
      client.time_confirm_required = true
  return unless settings.modules.heartbeat_detection.enabled and room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING
  check = false
  if room.hostinfo.mode != 2
    check = (client.is_first and info.player == 0) or (!client.is_first and info.player == 1)
  else
    cur_players = []
    switch room.turn % 4
      when 1
        cur_players[0] = 0
        cur_players[1] = 3
      when 2
        cur_players[0] = 0
        cur_players[1] = 2
      when 3
        cur_players[0] = 1
        cur_players[1] = 2
      when 0
        cur_players[0] = 1
        cur_players[1] = 3
    if !room.dueling_players[0].is_first
      cur_players[0] = cur_players[0] + 2
      cur_players[1] = cur_players[1] - 2
    check = client.pos == cur_players[info.player]
  if check
    CLIENT_heartbeat_register(client, false)
  return false

ygopro.ctos_follow 'TIME_CONFIRM', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if settings.modules.reconnect.enabled
    if client.waiting_for_last
      client.waiting_for_last = false
      if client.last_game_msg and client.last_game_msg_title != 'WAITING'
        if client.last_hint_msg
          ygopro.stoc_send(client, 'GAME_MSG', client.last_hint_msg)
        ygopro.stoc_send(client, 'GAME_MSG', client.last_game_msg)
    client.time_confirm_required = false
  if settings.modules.heartbeat_detection.enabled
    client.heartbeat_protected = false
    client.heartbeat_responsed = true
    CLIENT_heartbeat_unregister(client)
  return

ygopro.ctos_follow 'HAND_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = true
  return unless room.random_type
  if client.pos == 0
    room.waiting_for_player = room.waiting_for_player2
  room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  return

ygopro.ctos_follow 'TP_RESULT', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = true
  # room.selecting_tp = false
  return unless room.random_type
  room.last_active_time = moment()
  return

ygopro.stoc_follow 'CHAT', true, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  pid = info.player
  return unless room and pid < 4 and settings.modules.chat_color.enabled and (!settings.modules.hide_name or room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN)
  if room.duel_stage == ygopro.constants.DUEL_STAGE.DUELING and !room.dueling_players[0].is_first
    if room.hostinfo.mode == 2
      pid = {
        0: 2,
        1: 3,
        2: 0,
        3: 1
      }[pid]
    else
      pid = 1 - pid
  for player in room.players when player and player.pos == pid
    tplayer = player
  return unless tplayer
  tcolor = chat_color.save_list[CLIENT_get_authorize_key(tplayer)]
  if tcolor
    ygopro.stoc_send client, 'CHAT', {
        player: ygopro.constants.COLORS[tcolor]
        msg: tplayer.name + ": " + info.msg
      }
    return true
  return

ygopro.stoc_follow 'SELECT_HAND', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = false
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.FINGER
  return unless room.random_type
  if client.pos == 0
    room.waiting_for_player = client
  else
    room.waiting_for_player2 = client
  room.last_active_time = moment().subtract(settings.modules.random_duel.hang_timeout - 19, 's')
  return

ygopro.stoc_follow 'SELECT_TP', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  client.selected_preduel = false
  room.duel_stage = ygopro.constants.DUEL_STAGE.FIRSTGO
  room.selecting_tp = client
  if room.random_type
    room.waiting_for_player = client
    room.last_active_time = moment()
  return

ygopro.stoc_follow 'CHANGE_SIDE', false, (buffer, info, client, server, datas)->
  room=ROOM_all[client.rid]
  return unless room
  if client.pos == 0
    room.duel_stage = ygopro.constants.DUEL_STAGE.SIDING
  client.selected_preduel = false
  if settings.modules.side_timeout
    client.side_tcount = settings.modules.side_timeout
    ygopro.stoc_send_chat(client, "${side_timeout_part1}#{settings.modules.side_timeout}${side_timeout_part2}", ygopro.constants.COLORS.BABYBLUE)
    sinterval = setInterval ()->
      if not (room and client and client.side_tcount and room.duel_stage == ygopro.constants.DUEL_STAGE.SIDING)
        clearInterval sinterval
        return
      if client.side_tcount == 1
        ygopro.stoc_send_chat_to_room(room, client.name + "${side_overtime_room}", ygopro.constants.COLORS.BABYBLUE)
        ygopro.stoc_send_chat(client, "${side_overtime}", ygopro.constants.COLORS.RED)
        #room.scores[client.name_vpass] = -9
        CLIENT_send_replays(client, room)
        CLIENT_kick(client)
        clearInterval sinterval
      else
        client.side_tcount = client.side_tcount - 1
        ygopro.stoc_send_chat(client, "${side_remain_part1}#{client.side_tcount}${side_remain_part2}", ygopro.constants.COLORS.BABYBLUE)
    , 60000
    client.side_interval = sinterval

  if room.random_type
    if client.pos == 0
      room.waiting_for_player = client
    else
      room.waiting_for_player2 = client
    room.last_active_time = moment()
  return

# ygopro.stoc_follow 'REPLAY', true, (buffer, info, client, server, datas)->
  # room=ROOM_all[client.rid]
  # return settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe and settings.modules.tournament_mode.block_replay_to_player or settings.modules.replay_delay unless room
  # if settings.modules.cloud_replay.enabled and room.random_type
    # Cloud_replay_ids.push room.cloud_replay_id
  # if !room.replays[room.duel_count - 1]
    # console.log("Replay saved: ", room.duel_count - 1, client.pos)
    # room.replays[room.duel_count - 1] = buffer
  # if settings.modules.tournament_mode.enabled and settings.modules.tournament_mode.replay_safe
    # if client.pos == 0
      # dueltime=moment().format('YYYY-MM-DD HH-mm-ss')
      # replay_filename=dueltime
      # if room.hostinfo.mode != 2
        # for player,i in room.dueling_players
          # replay_filename=replay_filename + (if i > 0 then " VS " else " ") + player.name
      # else
        # for player,i in room.dueling_players
          # replay_filename=replay_filename + (if i > 0 then (if i == 2 then " VS " else " & ") else " ") + player.name
      # replay_filename=replay_filename.replace(/[\/\\\?\*]/g, '_')+".yrp"
      # duellog = {
        # time: dueltime,
        # name: room.name + (if settings.modules.tournament_mode.show_info then (" (Duel:" + room.duel_count + ")") else ""),
        # roomid: room.process_pid.toString(),
        # cloud_replay_id: "R#"+room.cloud_replay_id,
        # replay_filename: replay_filename,
        # roommode: room.hostinfo.mode,
        # players: (for player in room.dueling_players
          # name: player.name + (if settings.modules.tournament_mode.show_ip and !player.is_local then (" (IP: " + player.ip.slice(7) + ")") else "") + (if settings.modules.tournament_mode.show_info and not (room.hostinfo.mode == 2 and player.pos % 2 > 0) then (" (Score:" + room.scores[player.name_vpass] + " LP:" + (if player.lp? then player.lp else room.hostinfo.start_lp) + (if room.hostinfo.mode != 2 then (" Cards:" + (if player.card_count? then player.card_count else room.hostinfo.start_hand)) else "") + ")") else ""),
          # winner: player.pos == room.winner
        # )
      # }
      # duel_log.duel_log.unshift duellog
      # setting_save(duel_log)
      # fs.writeFile(settings.modules.tournament_mode.replay_path + replay_filename, buffer, (err)->
        # if err then log.warn "SAVE REPLAY ERROR", replay_filename, err
      # )
    # if settings.modules.cloud_replay.enabled
      # ygopro.stoc_send_chat(client, "${cloud_replay_delay_part1}R##{room.cloud_replay_id}${cloud_replay_delay_part2}", ygopro.constants.COLORS.BABYBLUE)
    # return settings.modules.tournament_mode.block_replay_to_player or settings.modules.replay_delay and room.hostinfo.mode == 1
  # else
    # return settings.modules.replay_delay and room.hostinfo.mode == 1

if settings.modules.random_duel.enabled
  setInterval ()->
    for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.random_type and room.last_active_time and room.waiting_for_player and room.get_disconnected_count() == 0 and (!settings.modules.side_timeout or room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING)
      time_passed = Math.floor((moment() - room.last_active_time) / 1000)
      #log.info time_passed
      if time_passed >= settings.modules.random_duel.hang_timeout
        room.last_active_time = moment()
        ROOM_ban_player(room.waiting_for_player.name, room.waiting_for_player.ip, "${random_ban_reason_AFK}")
        room.scores[room.waiting_for_player.name_vpass] = -9
        #log.info room.waiting_for_player.name, room.scores[room.waiting_for_player.name_vpass]
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${kicked_by_system}", ygopro.constants.COLORS.RED)
        CLIENT_send_replays(room.waiting_for_player, room)
        CLIENT_kick(room.waiting_for_player)
      else if time_passed >= (settings.modules.random_duel.hang_timeout - 20) and not (time_passed % 10)
        ygopro.stoc_send_chat_to_room(room, "#{room.waiting_for_player.name} ${afk_warn_part1}#{settings.modules.random_duel.hang_timeout - time_passed}${afk_warn_part2}", ygopro.constants.COLORS.RED)
        ROOM_unwelcome(room, room.waiting_for_player, "${random_ban_reason_AFK}")
    return
  , 1000

if settings.modules.heartbeat_detection.enabled
  setInterval ()->
    for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and (room.hostinfo.time_limit == 0 or room.duel_stage != ygopro.constants.DUEL_STAGE.DUELING)
      for player in room.get_playing_player() when player and (room.duel_stage != ygopro.constants.DUEL_STAGE.SIDING or player.selected_preduel)
        CLIENT_heartbeat_register(player, true)
    return
  , settings.modules.heartbeat_detection.interval

setInterval ()->
  current_time = moment()
  for room in ROOM_all when room and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and room.hostinfo.auto_death and !room.auto_death_triggered and current_time - moment(room.start_time) > 60000 * room.hostinfo.auto_death
    room.auto_death_triggered = true
    room.start_death()

, 1000

rebooted = false
#http
if settings.modules.http
  
  addCallback = (callback, text)->
    if not callback then return text
    return callback + "( " + text + " );"

  requestListener = (request, response)->
    parseQueryString = true
    u = url.parse(request.url, parseQueryString)

    #console.log(u.query.username, u.query.pass)
    if u.pathname == '/api/getrooms'
      response.writeHead(200)
      roomsjson = JSON.stringify rooms: (for room in ROOM_all when room and room.established
        roomid: room.game_id,
        roomname: room.name,
        roomnotes: room.notes,
        roommode: room.hostinfo.mode,
        needpass: !!room.pass,
        team1: room.hostinfo.team1,
        team2: room.hostinfo.team2,
        best_of: room.hostinfo.best_of,
        duel_flag: room.hostinfo.duel_flag,
        forbidden_types: room.hostinfo.forbidden_types,
        extra_rules: room.hostinfo.extra_rules,
        start_lp : room.hostinfo.start_lp,
        start_hand : room.hostinfo.start_hand,
        draw_count : room.hostinfo.draw_count,
        time_limit : room.hostinfo.time_limit,
        rule : room.hostinfo.rule,
        no_check : room.hostinfo.no_check_deck,
        no_shuffle : room.hostinfo.no_shuffle_deck,
        banlist_hash: room.hostinfo.lflist,
        users: _.sortBy((for player in room.players when player.pos?
          id: (-1).toString(),
          name: player.name,
          ip: if settings.modules.http.show_ip and !player.is_local then player.ip.slice(7) else null,
          status: if settings.modules.http.show_info and room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN and player.pos != 7 then (
            score: room.scores[player.name_vpass],
            lp: if player.lp? then player.lp else room.hostinfo.start_lp,
            cards: if room.hostinfo.mode != 2 then (if player.card_count? then player.card_count else room.hostinfo.start_hand) else null
          ) else null,
          pos: player.pos
        ), "pos"),
        istart: if room.duel_stage != ygopro.constants.DUEL_STAGE.BEGIN then 'start' else 'wait'
      ), null, 2
      response.end(addCallback(u.query.callback, roomsjson))
    else
      response.writeHead(400)
      response.end()
    return

  http_server = http.createServer(requestListener)
  http_server.listen settings.modules.http.port

  if settings.modules.http.ssl.enabled
    https = require 'https'
    options =
      cert: fs.readFileSync(settings.modules.http.ssl.cert)
      key: fs.readFileSync(settings.modules.http.ssl.key)
    https_server = https.createServer(options, requestListener)
    if settings.modules.http.websocket_roomlist and roomlist
      roomlist.init https_server, ROOM_all
    https_server.listen settings.modules.http.ssl.port

if not fs.existsSync('./plugins')
  fs.mkdirSync('./plugins')

plugin_list = fs.readdirSync("./plugins")
for plugin_filename in plugin_list
  plugin_path = process.cwd() + "/plugins/" + plugin_filename
  require(plugin_path)
  log.info("Plugin loaded:", plugin_filename)