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
post '/irc/haje' do
  begin
    params[:user_name].gsub!(/^(\p{Graph})/,"\\1\u200b")
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
