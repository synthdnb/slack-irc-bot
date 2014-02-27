require 'net/yail'
require 'httparty'
require 'yaml'
require 'sinatra'
require 'htmlentities'
require './unicode_fix'

config = YAML.load_file('config.yml')

irc = Net::YAIL.new(config[:irc])

irc.on_welcome do |event| 
  config[:irc][:channels].each do |channel|
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
  raise "IRC Throttled" unless irc.start_listening!
end

set :bind, '0.0.0.0'
set :port, 4567

def has_params *param_list
  params.map{|p| params[p].nil?}.inject(:|)
end

user_map = {}
decoder = HTMLEntities.new
post '/irc/haje' do
  puts params
  if has_params :token, :user_id, :user_name, :text #from slack
    return "FILTERED" if params[:user_name] =~ /slackbot/
    user_map[params[:user_id]] = params[:user_name]
    begin
      username = params[:user_name].gsub(/^(\p{Graph})/,"\\1.") #설호방지문자
      text = decoder.decode(params[:text]).gsub /<@(\w+)>/ do 
        uid = Regexp.last_match[1]
        (user_map.has_key? uid) ? "@#{user_map[uid]}": "@#{uid}"
      end
      text.split("\n").each do |line|
        config[:irc][:channels].each do |channel|
          irc.msg("##{channel}", "#{username}: #{line}")
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


