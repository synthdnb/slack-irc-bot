require 'net/yail'
require 'httparty'
require 'yaml'
require 'sinatra'
require 'htmlentities'
require './unicode_fix'

env = ARGV[0] || "production"
config = YAML.load_file('config.yml')[env]
irc = Net::YAIL.new(config[:irc])

irc.on_welcome do |event| 
  config[:irc][:channels].each do |channel|
    payload = config[:slack].merge(
      text: 'Bot Entered',
      username: "[irc]",
      parse: 'full',
    )
    HTTParty.get('https://slack.com/api/chat.postMessage', query: payload)
    irc.join("##{channel}") 
  end
end

irc.hearing_msg do |event| 
  puts event.raw
  begin
    payload = config[:slack].merge(
      text: event.message,
      username: "[irc]#{event.nick}",
      parse: 'full',
    )
    HTTParty.get('https://slack.com/api/chat.postMessage', query: payload)
  rescue => e
    puts e.message
    puts e.backtrace
  end
end

Thread.new do
  timeout = 10
  begin
    raise unless irc.start_listening!
  rescue
    puts "IRC Throttled"
    sleep timeout
    timeout = 60 if timeout < 60
    timeout += 10
    retry
  end
end

set :bind, '0.0.0.0'
set :port, config[:bot][:port]

def has_params *param_list
  params.map{|p| params[p].nil?}.inject(:|)
end

user_map = {}
nick_map = {}
bitbucket_map = {}

if File.exists? ('data.log')
  File.open('data.log','r') do |f|
    data = Marshal.load(f.read)
    user_map = data[:user]
    nick_map = data[:nick]
    bitbucket_map = data[:bitbucket]
  end
end

decoder = HTMLEntities.new

post '/slack/hook' do
  puts params
  if has_params :token, :user_id, :user_name, :text #from slack
    return "FILTERED" if params[:user_name] =~ /slackbot/
      user_map[params[:user_id]] = params[:user_name]
    begin
      if nick_map.has_key?(params[:user_id])
        username = nick_map[params[:user_id]] #매핑이 있으면 그걸로 추가
      else
        username = params[:user_name]
      end

      text = decoder.decode(params[:text]).gsub /<@(\w+)>/ do 
        uid = Regexp.last_match[1]
        (user_map.has_key? uid) ? "@#{user_map[uid]}": "@#{uid}"
      end.gsub /<([^\s\|]*?)?\|?([^\s\|]*)>/, '\2'
      text.split("\n").each do |line|
        config[:irc][:channels].each do |channel|
          irc.msg("##{channel}", "\u0002#{username}\u0002: #{line}")
        end
      end
      "SUCCESS"
    rescue => e
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
      nick_map[params[:user_id]] = nil
      "#{params[:user_name]}'s IRC nickname has been restored to default"
    else
      nick_map[params[:user_id]] = params[:text]
      "Registered #{params[:user_name]} as #{params[:text]}"
    end
  else
    "FAILED"
  end
end

post '/bitbucket/hook' do
  puts params
end


quithandler = lambda do
  File.open('data.log','w') do |f|
    f.write(Marshal.dump({user: user_map, nick: nick_map, bitbucket: bitbucket_map}))
  end
  payload = config[:slack].merge(
    text: 'Bot Exited',
    username: "[irc]",
    parse: 'full',
  )
  HTTParty.get('https://slack.com/api/chat.postMessage', query: payload)
end

trap("INT", quithandler)
trap("TERM", quithandler)


