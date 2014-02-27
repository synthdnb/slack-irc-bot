module Net
  class YAIL
    class MessageParser
      remove_const(:USER) if (defined?(USER))
      remove_const(:NICK) if (defined?(NICK))
      remove_const(:HOST) if (defined?(HOST))
      remove_const(:SERVERNAME) if (defined?(SERVERNAME))
      remove_const(:PREFIX) if (defined?(PREFIX))
      remove_const(:COMMAND) if (defined?(COMMAND))
      remove_const(:TRAILING) if (defined?(TRAILING))
      remove_const(:MIDDLE) if (defined?(MIDDLE))
      remove_const(:MESSAGE) if (defined?(MESSAGE))

      # Note that all regexes are non-greedy.  I'm scared of greedy regexes, sirs.
      USER        = /\S+?/
      # RFC suggested that a nick *had* to start with a letter, but that seems to
      # not be the case.
      #NICK        = /[\p{Word}\d\\|`'^{}\]\[-]+?/
      NICK        = /\p{Graph}+?/
      HOST        = /\S+?/
      SERVERNAME  = /\S+?/

      # This is automatically grouped for ease of use in the parsing.  Group 1 is
      # the full prefix; 2, 3, and 4 are nick/user/host; 1 is also servername if
      # there was no match to populate 2, 3, and 4.
      PREFIX      = /((#{NICK})!(#{USER})@(#{HOST})|#{SERVERNAME})/
      COMMAND     = /(\p{Word}+|\d{3})/
      TRAILING    = /\:\S*?/
      MIDDLE      = /(?: +([^ :]\S*))/

      MESSAGE     = /^(?::#{PREFIX} +)?#{COMMAND}(.*)$/
      def initialize(line)
        @params = []
        line.force_encoding('UTF-8')
        if line =~ MESSAGE
          matches = Regexp.last_match

          @prefix = matches[1]
          if (matches[2])
            @nick = matches[2]
            @user = matches[3]
            @host = matches[4]
          else
            @servername = matches[1]
          end

          @command = matches[5]

          # Args are a bit tricky.  First off, we know there must be a single
          # space before the arglist, so we need to strip that.  Then we have to
          # separate the trailing arg as it can contain nearly any character. And
          # finally, we split the "middle" args on space.
          arglist = matches[6].sub(/^ +/, '')
          arglist.sub!(/^:/, ' :')
          (middle_args, trailing_arg) = arglist.split(/ +:/, 2)
          @params.push(middle_args.split(/ +/), trailing_arg)
          @params.compact!
          @params.flatten!
        end
      end
    end

    def start_listening
      # We don't want to spawn an extra listener
      return if Thread === @ioloop_thread

      # Don't listen if socket is dead
      return if @dead_socket

      # Exit a bit more gracefully than just crashing out - allow any :outgoing_quit filters to run,
      # and even give the server a second to clean up before we fry the connection
      #
      # TODO: This REALLY doesn't belong here!  This is saying everybody who uses the lib wants
      #       CTRL+C to end the app at the YAIL level.  Not necessarily true outside bot-land.

      # Begin the listening thread
      @ioloop_thread = Thread.new {io_loop}
      @input_processor = Thread.new {process_input_loop}
      @privmsg_processor = Thread.new {process_privmsg_loop}

      # Let's begin the cycle by telling the server who we are.  This should start a TERRIBLE CHAIN OF EVENTS!!!
      dispatch OutgoingEvent.new(:type => :begin_connection, :username => @username, :address => @address, :realname => @realname)
    end
  end
end
