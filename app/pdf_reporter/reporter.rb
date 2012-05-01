require "mysql2"
require File.expand_path(File.dirname(__FILE__) + '/view.rb')

class PdfReporter

  class Reporter
    LOG_LOCAL_FILE_PATH = "log/reporter.log"
    GEN_FILE_PATH = File.expand_path(File.dirname(__FILE__) + '/report.pdf')

    Report = Struct.new(:header, :body)


    def initialize

      @get_cell_value = {
        "quantity" => lambda { |report| get_quantity_cell_val(report) },
        "price" => lambda { |report| get_price_cell_val(report) },
        "both" => lambda { |report| get_quantity_and_price_cell_val(report) },
        "" => lambda { |report| [] }
      }

      @report = Report.new([[], []], {})

      # begin
        @client = Mysql2::Client.new(
          host: "localhost",
          username: "root",
          password: "1234",
          database: "store_development"
        )
        @client.query_options.merge!(:as => :array)
      # rescue Mysql2::Error => e

      # end
    end

    def gen_report(rows_field, columns_field, value_type)
      init_report(rows_field, columns_field, value_type)
      View.new(@report).gen_pdf(GEN_FILE_PATH)
    end

    private

      def set_header_to_report(header_type)
        @raw_reports.each { |report|
          if !@used[header_type][report[header_type].to_s]
            @report.header[header_type].push report[header_type].to_s
            @used[header_type][report[header_type].to_s] = true
          end
        }
      end

      COLUMNS_HEADER = 1
      ROWS_HEADER = 0

      def get_quantity_cell_val(report)
        [{:label => "Quantity", :value => report.last}]
      end

      def get_price_cell_val(report)
        [{:label => "Price", :value => report[-1]}]
      end

      def get_quantity_and_price_cell_val(report)
        [{:label => "Quantity", :value => report[-2]}, {:label => "Price", :value => report[-1]}]
      end


      def init_report(rows_field, columns_field, value_type)
        @used = []
        @used[COLUMNS_HEADER] = {}
        @used[ROWS_HEADER] = {}

        @raw_reports = get_report_info(rows_field, columns_field, value_type)

        set_header_to_report(ROWS_HEADER)
        if rows_field and columns_field
          set_header_to_report(COLUMNS_HEADER)
        else
          @report.header[COLUMNS_HEADER] << ""
          columns_value = ""
        end
        @used = nil

        @report.header[ROWS_HEADER].each do |first|
          @report.body[first] = {}
          @report.header[COLUMNS_HEADER].each do |second|
            @report.body[first][second] = []
          end
        end

        @raw_reports.each do |report|
          @report.body[report[ROWS_HEADER].to_s][columns_value || report[COLUMNS_HEADER].to_s] =
            @get_cell_value[value_type.to_s].call(report)
        end
      end

      REAL_ROWS_COLS_N_VALS_NAMES = {
        :user => "users.login",
        :category => "categories.name",
        :purchased_at => "carts.purchased_at",
        :quantity => "SUM(product_carts.quantity)",
        :price => "SUM(product_carts.price)",
        :both => "SUM(product_carts.quantity), SUM(product_carts.price)"
      }

      def get_report_info(rows, columns, values)
        rows = REAL_ROWS_COLS_N_VALS_NAMES[rows]
        columns = REAL_ROWS_COLS_N_VALS_NAMES[columns]
        values = REAL_ROWS_COLS_N_VALS_NAMES[values]
        return [] if rows.empty? and columns.empty?

        query =<<SQL
SELECT
  #{select_or_group_query_partial(rows, columns, values)}

FROM carts INNER JOIN users ON users.id = carts.user_id
  INNER JOIN product_carts ON product_carts.cart_id = carts.id
  INNER JOIN products ON product_carts.product_id = products.id
  INNER JOIN categories ON categories.id = products.category_id
WHERE carts.purchased_at IS NOT NULL
GROUP BY #{select_or_group_query_partial(rows, columns)}
SQL

        # begin
          report = @client.query(query)
          return report
        # rescue Mysql2::Error => e

        # end
      end

      def select_or_group_query_partial(*args)
        result = ""
        args.each do |arg|
          result += "#{arg}," if !arg.empty?
        end
        result.chop
      end

  end

end