%w{commands handlers server user message connection manager}.each { |x| load File.join(File.dirname(__FILE__), "#{x}.rb") }

# This is from http://github.com/raggi/ir/blob/master/lib/ir.rb -- idk where to toss it, so I tossed it here
def valid?(str)
  catch(:ok) { eval("BEGIN{throw:ok,true}; _ = #{str}") }
rescue SyntaxError
  false
end

module Rubino
  class Bot
    attr_accessor :nick, :last, :args
    def initialize(opts)
      @nick_number = 0
      @nick = opts['nicks'][@nick_number]
      @config = opts
      @last, @args = nil
      @server = Server.new(opts['server'], opts['port'])
      @connected = false
    end

    def inspect
      parts = {
       'nick'       => @nick,
       'connection' => @connection,
       'channels'   => @config['channels'].join(','),
       'last'       => @last.to_s,
       'handler'    => @handler
      }
      inspected = []
      parts.map do |k,v|
        inspected << "#{k}=#{v.inspect}"
      end
      "#<Rubino::Bot #{inspected.join(', ')}>"
    end

    def args
      @args
    end

    def last
      @last
    end

    def raw(*args)
      args.each do |message|
        puts ">> #{message}\r\n"
        @connection.send(message)
      end
    end

    def send(*args)
      message = Message.new(
                  :type  => args[0],
                  :recip => args[1],
                  :text  => args[2..-1].join(' ')
                 )
      raw message
    end

    def privmsg(recip, *args)
      send "PRIVMSG", recip, *args
    end

    def notice(recip, *args)
      send "NOTICE", recip, *args
    end

    def ctcp(recip, type, *args)
      privmsg recip, "\001#{type.to_s.upcase} #{args.join(' ')}\001"
    end

    def ctcp_reply(type, *args)
      notice @last.recip, "\001#{type.to_s.upcase} #{args.join(' ')}\001"
    end

    def action(recip, *args)
      ctcp recip, :action, *args
    end

    def reply(*args)
      privmsg @last.recip, *args
    end

    def reply_highlight(*args)
      reply "#{@last.sender.nick}:", *args
    end

    def reaction(*args)
      action @last.recip, *args
    end

    def join(*args)
      args.each do |c|
        current = c
        if current.is_a?(Array)
          current.each do |chan|
            join chan
          end
        elsif current.is_a?(String)
          send :join, c
          @config['channels'] << c
        end
      end
      #@config['channels'] << args
      @config['channels'].uniq!
    end

    def part(*args)
      send :part, args[0], args[1..-1].join(' ')
      @config['channels'].delete(args[0])
    end

    def quit(*args)
      send :quit, args.join(' ')
      @connected = false
    end

    def nick=(nickname)
      send :nick, nickname
      @nick = nickname
    end

    alias :msg :privmsg
    alias :tell :privmsg
    alias :do :action
    alias :act :action
    alias :react :reaction

    def shutdown(*args)
      if args.length > 0
        quit(*args)
      else
        quit "I have been slain!"
      end
      @connection.close
    end

    def connect
      @connection = Connection.new(@server)
      @connected = true
      @nick_number = 0
      @nick = @config['nicks'][@nick_number]
      raw "USER #{@nick} * * :Rubino IRC bot", "NICK #{@nick}"
    end

    def handle(message)
      @handler ||= Handlers.new(self, @config)
      @handler.handle(message)
    end

    def parse(line)
      %w{commands handlers}.each do |x|
        filename = File.join(File.dirname(__FILE__), "..", "custom", "#{x}.rb")
        begin
          if File.exist?(filename)
            raise ::SyntaxError, "syntax error, invalid code in #{filename}" unless valid?(open(filename).read)
            load filename
          end
        rescue Exception, SyntaxError => e
          puts "----------------------------------------------------"
          puts "Invalid code in #{filename}, details below:"
          puts "#{e.class}: #{e.message}"
          e.backtrace.each do |line|
            puts line
          end
          puts "----------------------------------------------------"
        end
      end
      message = Message.new(line)
      if message.recip == @nick && !message.sender.nil?
        message.recip = message.sender.nick
      end
      @last = message
      handle(message)
    end

    def run
      i = 1
      while @connected
        loop do
          connect if @connection.eof?
          until @connection.eof?
            i = 1
            line = @connection.readline
            parse line
          end
          sleep i*5
          i += 1
        end
      end
      @connection.close
    end

  end # class Bot
end   # module Rubino
