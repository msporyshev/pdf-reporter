require "socket"
require "thread"
require "json"
require File.expand_path(File.dirname(__FILE__) + "/pdf_reporter/reporter.rb")

class PdfReporter
  def self.root_dir
    File.dirname(__FILE__)
  end

  PID_LOCAL_FILE_PATH = "tmp/pid/reporter.pid"

  CLIENT_DATA_COUNT = 3

  def initialize(reports_dir, port = 30000)
    @client_data = Queue.new
    @server = TCPServer.new "localhost", port
    @server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    @reports_dir = reports_dir
  end

  def start
    @pid = nil

    @pid = fork do
      running = true
      Signal.trap("QUIT") do
        running = false
        throw "asdasd"
      end

      while running
        Thread.start(@server.accept) do |client|
          row_field = client.gets
          col_field = client.gets
          value_type = client.gets
          filter_json = client.gets

          filter = Hash.new
          filter_params = JSON.parse(filter_json)

          row_field = row_field =~ /NULL/ ? nil : row_field.chomp.to_sym
          col_field = col_field =~ /NULL/ ? nil : col_field.chomp.to_sym
          value_type = value_type =~ /NULL/ ? nil : value_type.chomp.to_sym

          file_name = Reporter.gen_report_file_name(
            row_field,
            col_field,
            value_type,
            filter_params,
            @reports_dir
          )

          client.puts File.basename(file_name)
          client.close

          @client_data << {
            row: row_field,
            col: col_field,
            val: value_type,
            file_name: file_name,
            filter_params: filter_params
          }
        end

        Thread.list.each { |t| t.join if t != Thread.current }

        while !@client_data.empty?
          data = @client_data.pop
          report = Reporter.new(@reports_dir)
          report.gen_report(data[:row], data[:col], data[:val], data[:file_name], data[:filter_params])
        end
      end

    end

    File.open(PID_LOCAL_FILE_PATH, "w") { |file| file.puts @pid }
  end

end

reporter = PdfReporter.new("/home/max/study/projects/rails_apps/store/public/reports/")
reporter.start