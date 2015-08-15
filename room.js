// Generated by CoffeeScript 1.9.3
(function() {
  var Deck, Match, Room, User, _, bunyan, log, mongoose, settings, spawn, ygopro;

  _ = require('underscore');

  _.str = require('underscore.string');

  _.mixin(_.str.exports());

  spawn = require('child_process').spawn;

  ygopro = require('./ygopro.js');

  bunyan = require('bunyan');

  settings = require('./config.json');

  log = bunyan.createLogger({
    name: "mycard-room"
  });

  if (settings.modules.database) {
    mongoose = require('mongoose');
    mongoose.connect(settings.modules.database);
    User = require('./user.js');
    Deck = require('./deck.js');
    Match = require('./match.js');
  }

  Room = (function() {
    Room.all = [];

    Room.find_or_create_by_name = function(name) {
      var ref;
      return (ref = this.find_by_name(name)) != null ? ref : new Room(name);
    };

    Room.find_by_name = function(name) {
      var result;
      result = _.find(this.all, function(room) {
        return room.name === name;
      });
      return result;
    };

    Room.find_by_port = function(port) {
      return _.find(this.all, function(room) {
        return room.port === port;
      });
    };

    Room.validate = function(name) {
      var client_name, client_name_and_pass, client_pass;
      client_name_and_pass = name.split('$', 2);
      client_name = client_name_and_pass[0];
      client_pass = client_name_and_pass[1];
      return !_.find(Room.all, function(room) {
        var room_name, room_name_and_pass, room_pass;
        room_name_and_pass = room.name.split('$', 2);
        room_name = room_name_and_pass[0];
        room_pass = room_name_and_pass[1];
        return client_name === room_name && client_pass !== room_pass;
      });
    };

    function Room(name) {
      var param;
      this.name = name;
      this.alive = true;
      this.players = [];
      this.status = 'starting';
      this.established = false;
      this.watcher_buffers = [];
      this.watchers = [];
      Room.all.push(this);
      this.hostinfo = {
        lflist: 0,
        rule: 0,
        mode: 0,
        enable_priority: false,
        no_check_deck: false,
        no_shuffle_deck: false,
        start_lp: 8000,
        start_hand: 5,
        draw_count: 1,
        time_limit: 180
      };
      if (name.slice(0, 2) === 'M#') {
        this.hostinfo.mode = 1;
      } else if (name.slice(0, 2) === 'T#') {
        this.hostinfo.mode = 2;
        this.hostinfo.start_lp = 16000;
      } else if ((param = name.match(/^(\d)(\d)(T|F)(T|F)(T|F)(\d+),(\d+),(\d+)/i))) {
        this.hostinfo.rule = parseInt(param[1]);
        this.hostinfo.mode = parseInt(param[2]);
        this.hostinfo.enable_priority = param[3] === 'T';
        this.hostinfo.no_check_deck = param[4] === 'T';
        this.hostinfo.no_shuffle_deck = param[5] === 'T';
        this.hostinfo.start_lp = parseInt(param[6]);
        this.hostinfo.start_hand = parseInt(param[7]);
        this.hostinfo.draw_count = parseInt(param[8]);
      }
      param = [0, this.hostinfo.lflist, this.hostinfo.rule, this.hostinfo.mode, (this.hostinfo.enable_priority ? 'T' : 'F'), (this.hostinfo.no_check_deck ? 'T' : 'F'), (this.hostinfo.no_shuffle_deck ? 'T' : 'F'), this.hostinfo.start_lp, this.hostinfo.start_hand, this.hostinfo.draw_count];
      this.process = spawn('./ygopro', param, {
        cwd: 'ygocore'
      });
      this.process.on('exit', (function(_this) {
        return function(code) {
          if (!_this.disconnector) {
            _this.disconnector = 'server';
          }
          return _this["delete"]();
        };
      })(this));
      this.process.stdout.setEncoding('utf8');
      this.process.stdout.once('data', (function(_this) {
        return function(data) {
          _this.established = true;
          _this.port = parseInt(data);
          return _.each(_this.players, function(player) {
            return player.server.connect(_this.port, '127.0.0.1', function() {
              var buffer, i, len, ref;
              ref = player.pre_establish_buffers;
              for (i = 0, len = ref.length; i < len; i++) {
                buffer = ref[i];
                player.server.write(buffer);
              }
              return player.established = true;
            });
          });
        };
      })(this));
    }

    Room.prototype["delete"] = function() {
      var index;
      if (this.deleted) {
        return;
      }
      if (_.startsWith(this.name, 'M#') && this.started && settings.modules.database) {
        this.save_match();
      }
      index = _.indexOf(Room.all, this);
      if (index !== -1) {
        Room.all[index] = null;
      }
      if (index !== -1) {
        Room.all.splice(index, 1);
      }
      return this.deleted = true;
    };

    Room.prototype.toString = function() {
      var player, ref, ref1;
      return "room: " + this.name + " " + this.port + " " + ((ref = this.alive) != null ? ref : {
        'alive': 'not-alive'
      }) + " " + ((ref1 = this.dueling) != null ? ref1 : {
        'dueling': 'not-dueling'
      }) + " [" + ((function() {
        var i, len, ref2, results;
        ref2 = this.players;
        results = [];
        for (i = 0, len = ref2.length; i < len; i++) {
          player = ref2[i];
          results.push("client " + (typeof player.client) + " server " + (typeof player.server) + " " + player.name + " " + player.pos + ". ");
        }
        return results;
      }).call(this)) + "] " + (JSON.stringify(this.pos_name));
    };

    Room.prototype.ensure_finish = function() {
      var duel, i, len, normal_ended, player_wins, ref;
      player_wins = [0, 0, 0];
      ref = this.duels;
      for (i = 0, len = ref.length; i < len; i++) {
        duel = ref[i];
        player_wins[duel.winner] += 1;
      }
      normal_ended = player_wins[0] >= 2 || player_wins[1] >= 2;
      if (!normal_ended) {
        if (this.disconnector === 'server') {
          return false;
        }
        if (this.duels.length === 0 || _.last(this.duels).reason !== 4) {
          this.duels.push({
            winner: 1 - this.disconnector.pos,
            reason: 4
          });
        }
      }
      return true;
    };

    Room.prototype.save_match = function() {
      var match_winner;
      if (!this.ensure_finish()) {
        return;
      }
      match_winner = _.last(this.duels).winner;
      if (!(this.dueling_players[0] && this.dueling_players[1])) {
        return;
      }
      return User.findOne({
        name: this.dueling_players[0].name
      }, (function(_this) {
        return function(err, player0) {
          if (err) {

          } else if (!player0) {

          } else {
            return User.findOne({
              name: _this.dueling_players[1].name
            }, function(err, player1) {
              var loser, winner;
              if (err) {

              } else if (!player1) {

              } else {
                Deck.findOne({
                  user: player0._id,
                  card_usages: _this.dueling_players[0].deck
                }, function(err, deck0) {
                  if (err) {

                  } else if (!deck0) {
                    deck0 = new Deck({
                      name: 'match',
                      user: player0._id,
                      card_usages: _this.dueling_players[0].deck,
                      used_count: 1,
                      last_used_at: Date.now()
                    });
                    deck0.save();
                  } else {
                    deck0.used_count++;
                    deck0.last_used_at = Date.now();
                    deck0.save();
                  }
                  return Deck.findOne({
                    user: player1._id,
                    card_usages: _this.dueling_players[1].deck
                  }, function(err, deck1) {
                    if (err) {

                    } else if (!deck1) {
                      deck1 = new Deck({
                        name: 'match',
                        user: player1._id,
                        card_usages: _this.dueling_players[1].deck,
                        used_count: 1,
                        last_used_at: Date.now()
                      });
                      deck1.save();
                    } else {
                      deck1.used_count++;
                      deck1.last_used_at = Date.now();
                      deck1.save();
                    }
                    return Match.create({
                      players: [
                        {
                          user: player0._id,
                          deck: deck0._id
                        }, {
                          user: player1._id,
                          deck: deck1._id
                        }
                      ],
                      duels: _this.duels,
                      winner: match_winner === 0 ? player0._id : player1._id,
                      ygopro_version: settings.version
                    }, function(err, match) {});
                  });
                });
                if (match_winner === 0) {
                  winner = player0;
                  loser = player1;
                } else {
                  winner = player1;
                  loser = player0;
                }
                winner.points += 5;
                if (_.last(_this.duels).reason === 4) {
                  loser.points -= 8;
                } else {
                  loser.points -= 3;
                }
                winner.save();
                return loser.save();
              }
            });
          }
        };
      })(this));
    };

    Room.prototype.connect = function(client) {
      this.players.push(client);
      if (this.established) {
        return client.server.connect(this.port, '127.0.0.1', function() {
          var buffer, i, len, ref;
          ref = client.pre_establish_buffers;
          for (i = 0, len = ref.length; i < len; i++) {
            buffer = ref[i];
            client.server.write(buffer);
          }
          return client.established = true;
        });
      }
    };

    Room.prototype.disconnect = function(client, error) {
      var index;
      if (client.is_post_watcher) {
        ygopro.stoc_send_chat_to_room(this, client.name + " " + '退出了观战' + (error ? ": " + error : ''));
        index = _.indexOf(this.watchers, client);
        if (index !== -1) {
          return this.watchers.splice(index, 1);
        }
      } else {
        index = _.indexOf(this.players, client);
        if (index !== -1) {
          this.players.splice(index, 1);
        }
        if (this.players.length) {
          return ygopro.stoc_send_chat_to_room(this, client.name + " " + '离开了游戏' + (error ? ": " + error : ''));
        } else {
          this.process.kill();
          return this["delete"]();
        }
      }
    };

    return Room;

  })();

  module.exports = Room;

}).call(this);
