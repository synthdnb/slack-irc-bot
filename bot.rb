require 'net/yail'
require 'httparty'
require 'yaml'
require 'sinatra'
require './message_parser_unicode_fix'

config = YAML.load_file('config.yml')

irc = Net::YAIL.new(config[:irc])

irc.on_welcome do |event| 
  config[:irc][:channels].each do |channel|
    irc.join("##{channel}") 
  end
end

irc.hearing_msg do |event| 
  begin
    puts event.raw
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
  params.map{|p| params[p].blank?}.inject(:|)
end

user_map = {}

post '/irc/haje' do
  if has_params :token, :user_id, :user_name, :text #from slack
    user_map[params[:user_id]] = params[:user_name]
    begin
      params[:user_name].gsub!(/^(\p{Graph})/,"\\1.") #설호방지문자
      params[:text].gsub /<@(\w+)>/ do 
        uid = Regexp.last_match[1]
        user_map.has_key? uid ? "@#{user_map[uid]}": "@#{uid}"
      end
      config[:irc][:channels].each do |channel|
        irc.msg("##{channel}", "#{params[:user_name]}: #{params[:text]}")
      end
      "SUCCESS"
    rescue => e
      puts e.message
      puts e.backtrace
      "FAILED"
    end
  end
end


