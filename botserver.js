var Discord = require('discord.js');
var fs = require('fs');

	var controlersids = fs.readFileSync('controlers.txt', 'utf8');
	var controlers = controlersids.split("\n");
	for (let i = controlers.length; i > -1; i--){
		if(controlers[i]===""){
			controlers.splice(i,1);
		}
	}

	var channelids = fs.readFileSync('channels.txt', 'utf8');
	var channels = channelids.split("\n");
	for (let i = channels.length; i > -1; i--){
		if(channels[i]===""){
			channels.splice(i,1);
		}
	}

	var bot = new Discord.Client()

	bot.on('ready',function(){
		console.log('Logged in as %s - %s\n', bot.user.username, bot.user.id);
		//server.start();
	});

	bot.on('message',function(message){
		var ok=false;
		for (let i = 0; i < controlers.length; i++) {
			if(controlers[i]===message.author.id){
				ok = true;
				break;
			}
		}
		if(!ok) return;
		if(message.content.indexOf(".addcontroler")===0){
			var res=message.content.substring(".addcontroler".length +1 , message.content.length);
			usid = res.substring(2 , res.length-1);
			if(bot.users.find('id', usid)){
				let chk=true;
				for (let i = 0; i < controlers.length; i++) {
					if(controlers[i]===usid){
						chk = false;
						break;
					}
				}
				if (chk){
					console.log('adding ' + usid + ' as a controler');
					controlers.push(usid);
					message.channel.send("user added as controler");
					savecontrolers();
				} else {
					message.channel.send("user already controler");
				}
			}
		}
		if(message.content.indexOf(".removecontroler")===0){
			var res=message.content.substring(".removecontroler".length +1 , message.content.length);
			usid = res.substring(2 , res.length-1);
			if(bot.users[usid]){
				let chk=false;
				for (let i = 0; i < controlers.length; i++) {
					if(controlers[i]===usid){
						chk = true;
						controlers.splice(i,1);
					}
				}
				if (chk){
				console.log('removed ' + usid + ' from the controlers');
				message.channel.send("user is no longer a controler");
				savecontrolers();
			} else {
				message.channel.send("user isn't a controler");
			}
			}
		}
		if(message.content===".addlogging") {
			let chk=true;
			for (let i = 0; i < channels.length; i++) {
				if(channels[i]===message.channel.id){
					chk = false;
					break;
				}
			}
			if (chk){
				console.log('adding '+message.channel.id + ' as a valid channel');
				channels.push(message.channel.id);
				message.channel.send("logging enabled in this channel");
			savechannels();
			} else {
				message.channel.send("channel is already used for logging");
			}
		}
		if(message.content===".removelogging") {
			let chk=false;
			for (let i = channels.length; i > -1; i--) {
				if(channels[i]===message.channel.id){
					chk = true;
					channels.splice(i,1);
				}
			}
			if(chk){
				console.log(message.channel.id + ' removed from logging channels');
				message.channel.send("logging disabled in this channel");
			savechannels();
			} else {
				message.channel.send("this channel wasn't used for logging");
			}
		}
		if(message.content===".restartai") {
			//server.restartAI();
			message.channel.send("ai restart not reimplemented yet");
		}
	});

	function write(output){
		for (let i = 0; i < channels.length; i++) {
			bot.channels.get(channels[i]).send("```" + output + "```");
		}
	};

	function write2(output,room){
		let j, len1, line, ref;
		if (room){
			write("Room id: "+room.game_id + "\nRoom Password: "+room.pass+"\nRoom Notes: "+room.notes+"\nHost Player: "+room.players[0].name+"\nRoom Status: "+room.status)
		}
		
		ref = (require('underscore')).lines(output);
		for (j = 0, len1 = ref.length; j < len1; j++) {
			if ((line + "\n" + ref[j]).length > 2000-6){
				write(line);
				line="";
			}
			line = line + "\n" + ref[j];
		}
		write(line);
	};

	function savechannels(){
		let buffer = "";
		for (let i = 0; i < channels.length; i++) {
			buffer=buffer+channels[i]+"\n";
		}
		fs.writeFile('channels.txt', buffer, function(err) {
			if (err) {
			console.log("couldn't save channel list\n" + err);
			}
		});
	}

	function savecontrolers() {
		let buffer = "";
		for (let i = 0; i < controlers.length; i++) {
			buffer=buffer+controlers[i]+"\n";
		}
		fs.writeFile('controlers.txt', buffer, function(err) {
			if (err) {
			console.log("couldn't save controlers list\n" + err);
			}
		});
	}

module.exports = {
	connect: function (token) {
		return bot.login(token);
	},
	write: write,
	write2: write2,
};