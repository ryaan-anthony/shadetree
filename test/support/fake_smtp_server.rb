require "socket"

# A tiny SMTP server for tests (NTF-01): answers each stage of the conversation with the reply
# given, so tests exercise what net-smtp really raises at connect, AUTH, MAIL FROM, RCPT TO
# and DATA, instead of choosing the exception themselves.
#
#   FakeSmtpServer.run(rcpt: "550 5.1.1 <dana@example.com>: no such user") { |settings| ... }
class FakeSmtpServer
  DEFAULTS = { greeting: "220 fake ESMTP", auth: "235 2.7.0 OK", mail: "250 2.1.0 OK", rcpt: "250 2.1.5 OK",
               data: "354 go ahead", message: "250 2.0.0 queued" }.freeze

  def self.run(**replies)
    server = new(**replies)
    yield server.smtp_settings
  ensure
    server&.stop
  end

  def initialize(**replies)
    @replies = DEFAULTS.merge(replies)
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { handle(@server.accept) } rescue nil } # rubocop:disable Style/RescueModifier
  end

  def smtp_settings = { address: "127.0.0.1", port: @server.addr[1], user_name: "user", password: "secret",
                        authentication: :plain, enable_starttls: false, enable_starttls_auto: false, open_timeout: 2, read_timeout: 2 }

  def stop
    @thread.kill
    @server.close
  end

  private

  def handle(client)
    client.write("#{@replies[:greeting]}\r\n")
    in_data = false
    while (line = client.gets)
      if in_data
        next unless line == ".\r\n"

        in_data = false
        client.write("#{@replies[:message]}\r\n")
        next
      end
      command = line.split.first.to_s.upcase
      if command == "QUIT"
        client.write("221 bye\r\n")
        break
      end
      reply = { "EHLO" => "250-fake\r\n250 AUTH PLAIN", "AUTH" => @replies[:auth], "MAIL" => @replies[:mail],
                "RCPT" => @replies[:rcpt], "DATA" => @replies[:data] }.fetch(command, "250 OK")
      in_data = command == "DATA" && reply.start_with?("354")
      client.write("#{reply}\r\n")
    end
  ensure
    client&.close
  end
end
