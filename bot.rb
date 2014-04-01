require 'net/yail'
require 'httparty'
require 'yaml'
require 'sinatra/base'
require 'htmlentities'
require './unicode_fix'


class IRCThrottledError < RuntimeError; end

class WebServer < Sinatra::Base
  def self.chan_map
    @@chan_map
  end



  def self.dump
    Marshal.dump({user: @@user_map, nick: @@nick_map, bitbucket: @@bitbucket_map, chan: @@chan_map})
  end

  configure do
    enable :logging
    @@decoder = HTMLEntities.new
    @@env = ARGV[0] || "production"
    @@config = YAML.load_file('config.yml')[@@env]
    @@irc = Net::YAIL.new(@@config[:irc])

    data = Marshal.load(File.read('data.log')) rescue {}
    @@user_map = data[:user] || {}
    @@nick_map = data[:nick] || {}
    @@chan_map = data[:chan] || {irc: {}, slack: {}}
    @@bitbucket_map = data[:bitbucket] || {}

    @@irc.on_welcome do |event| 
      @@chan_map[:slack].each do |slack_chan, irc_chan|
        @@irc.join(irc_chan)
        WebServer.send_slack("Synced with #{irc_chan}", slack_chan)
      end
    end

    @@irc.hearing_msg do |event| 
      puts event.raw
      begin
        WebServer.send_slack(event.message, @@chan_map[:irc][event.channel] ,event.nick)
      rescue => e
        puts e.message
        puts e.backtrace
      end
    end
    
    Thread.new do
      timeout = 90
      begin
        raise IRCThrottledError unless @@irc.start_listening!
      rescue => e
        puts e.class
        puts e.message
        puts e.backtrace
        sleep timeout
        timeout = 60 if timeout < 60
        timeout += 10
        retry
      end
    end
  end

  def has_params *param_list
    params.map{|p| params[p].nil?}.inject(:|)
  end

  def self.send_slack(text, channel, user = nil)
    payload = @@config[:slack].merge(
      text: text,
      channel: channel,
      username: "[irc]#{user}",
      parse: 'full',
    )
    HTTParty.get('https://slack.com/api/chat.postMessage', query: payload)
  end

  set :bind, '0.0.0.0'
  set :port, @@config[:bot][:port]

  post '/slack/ircsync' do
    if has_params :channel_id, :text #from slack
      ircchan = "##{params[:text]}"
      @@chan_map[:slack][params[:channel_id]] = ircchan
      @@chan_map[:irc][ircchan]= params[:channel_id]
      @@irc.join(ircchan)
      WebServer.send_slack("#{params[:user_name]} synced this channel to #{ircchan}", params[:channel_id])
      ""
    else
      "Failed"
    end
  end

  post '/slack/listen' do
    puts params
    if has_params :token, :user_id, :user_name, :text #from slack
      return "FILTERED" if params[:user_name] =~ /slackbot/
      return "UNREGISTERED" unless @@chan_map[:slack].has_key?(params[:channel_id])
      @@user_map[params[:user_id]] = params[:user_name]
      begin
        if @@nick_map.has_key?(params[:user_id])
          username = @@nick_map[params[:user_id]] #매핑이 있으면 그걸로 추가
        else
          username = params[:user_name]
        end

        text = @@decoder.decode(params[:text]).gsub /<@(\w+)>/ do 
          uid = Regexp.last_match[1]
          (@@user_map.has_key? uid) ? "@#{@@user_map[uid]}": "@#{uid}"
        end.gsub /<([^\s\|]*?)?\|?([^\s\|]*)>/, '\2'
        text.split("\n").each do |line|
          @@irc.msg(@@chan_map[:slack][params[:channel_id]], "\u0002#{username}\u0002: #{line}")
          sleep 0.5
        end
        "SUCCESS"
      rescue => e
        puts e.class
        puts e.message
        puts e.backtrace
        "FAILED"
      end
    end
  end

  post '/irc/map' do
    puts params
    if has_params :user_id, :user_name
      if params[:text] == ""
        @@nick_map[params[:user_id]] = nil
        "#{params[:user_name]}'s IRC nickname has been restored to default"
      else
        @@nick_map[params[:user_id]] = params[:text]
        "Registered #{params[:user_name]} as #{params[:text]}"
      end
    else
      "FAILED"
    end
  end

  post '/bitbucket/hook' do
    puts params
  end
end

at_exit do
  puts "quit"

  File.open('data.log','w') do |f|
    f.write(WebServer.dump)
  end
end



WebServer.run!

