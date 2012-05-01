require "socket"
require File.expand_path(File.dirname(__FILE__) + "/pdf_reporter/reporter.rb")

class PdfReporter

  PID_LOCAL_FILE_PATH = "tmp/pid/reporter.pid"

  CLIENT_DATA_COUNT = 3

  def initialize(port = 30001)
    @server = TCPServer.new "localhost", port
    @server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
  end

  def start
    @pid = nil

    @pid = fork do
      running = true
      Signal.trap("QUIT") do
        running = false
      end

      while running
        Thread.start(@server.accept) do |client|
          row_field = client.gets
          col_field = client.gets
          value_type = client.gets
          client.close

          row_field = row_field =~ /NULL/ ? nil : row_field.chomp.to_sym
          col_field = col_field =~ /NULL/ ? nil : col_field.chomp.to_sym
          value_type = value_type =~ /NULL/ ? nil : value_type.chomp.to_sym

          report = Reporter.new
          report.gen_report(row_field, col_field, value_type)
        end
      end
    end

    File.open(PID_LOCAL_FILE_PATH, "w") { |file| file.puts @pid }
  end

end

reporter = PdfReporter.new
reporter.start