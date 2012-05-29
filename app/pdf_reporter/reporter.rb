require "mysql2"
require "digest"
require "date"
require File.expand_path(File.dirname(__FILE__) + '/view.rb')

class PdfReporter
  ROOT_DIR = "/home/max/study/projects/ruby/socket-prog-gen-pdf/app"

  class Reporter
    ERR_LOG_LOCAL_FILE_PATH = PdfReporter::ROOT_DIR + "/log/reporter_err.log"

    Report = Struct.new(:header, :body)


    def initialize(reports_dir)
      @count = 0
      @reports_dir = reports_dir

      @get_cell_value = {
        "quantity" => lambda { |report| get_quantity_cell_val(report) },
        "price" => lambda { |report| get_price_cell_val(report) },
        "both" => lambda { |report| get_quantity_and_price_cell_val(report) },
        "" => lambda { |report| [] }
      }

      @filter_str_func = {
        product_key_word: method(:single_value_filter_part),
        user_ids: method(:user_filter_part),
        category_ids: method(:category_filter_part),
        price_range_from: method(:single_value_filter_part),
        price_range_to: method(:single_value_filter_part)
      }

      @report = Report.new([[], []], {})

      begin
        @client = Mysql2::Client.new(
          host: "localhost",
          username: "root",
          password: "1234",
          database: "store_development"
        )
        @client.query_options.merge!(:as => :array)
      rescue Mysql2::Error => e
        File.open(ERR_LOG_LOCAL_FILE_PATH, "a") { |file|
          file.puts e.errno
          file.puts e.error
        }
      end
    end

    def self.gen_report_file_name(rows_field, columns_field, value_type, filter_params, reports_dir)
      name = rows_field.to_s + columns_field.to_s + value_type.to_s + Date.today.to_s + filter_params.inspect
      hash = Digest::MD5.hexdigest(name)
      return File.join(reports_dir, "#{hash}.pdf")
    end

    def gen_report(rows_field, columns_field, value_type, file_name, filter_params)
      init_report(rows_field, columns_field, value_type, filter_params)
      View.new(@report, value_type, search_query(filter_params)).gen_pdf(file_name)
    end

    private

      FILTER_STR_TEMPLATES = {
        product_key_word: "products.description LIKE \"%?%\" ",
        user_ids: "users.id IN (?) ",
        category_ids: "categories.path LIKE \"?.%\"",
        price_range_from: "product_carts.price >= ?",
        price_range_to: "product_carts.price <= ?"
      }

      def category_filter_part(key, category_ids)
        filter = "( 1 = 0"
        category_ids.each do |id|
          cur_filter = FILTER_STR_TEMPLATES[:category_ids].clone

          value = @client.escape(id)
          cur_filter.gsub!(/\?/, value)

          filter << " OR " << cur_filter
        end

        filter += ")"
      end

      def user_filter_part(key, user_ids)
        filter_str = FILTER_STR_TEMPLATES[:user_ids].clone
        value_str = ""
        user_ids.each { |e| value_str << @client.escape(e) << "," }
        value_str.chop!

        filter_str.gsub!(/\?/, value_str)
      end

      def single_value_filter_part(key, val)
        filter_str = FILTER_STR_TEMPLATES[key.to_sym].clone
        value_str = @client.escape(val)
        filter_str.gsub!(/\?/, value_str)
      end

      def search_query(params)
        @count += 1
        query_str = ""
        params.each_pair do |key, val|
          filter_str_func = @filter_str_func[key.to_sym]

          next if filter_str_func.nil? || val.is_a?(String) && val.empty? || val.nil?

          query_str << filter_str_func.call(key, val) << " AND "
        end

        query_str << "1 = 1"
      end

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
        [
          {:label => "Quantity", :value => report[-2]},
          {:label => "Price", :value => report[-1]}
        ]
      end


      def init_report(rows_field, columns_field, value_type, filter_params)
        @used = []
        @used[COLUMNS_HEADER] = {}
        @used[ROWS_HEADER] = {}

        @raw_reports = get_report_info(rows_field, columns_field, value_type, filter_params)

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

      REAL_NAMES = {
        :user => "users.login",
        :category => "categories.name",
        :purchased_at => "carts.purchased_at",
        :quantity => "SUM(product_carts.quantity)",
        :price => "SUM(product_carts.price)",
        :both => "SUM(product_carts.quantity), SUM(product_carts.price)"
      }

      def get_report_info(rows, columns, values, filter_params)
        rows = REAL_NAMES[rows]
        columns = REAL_NAMES[columns]
        values = REAL_NAMES[values]
        return [] if rows.empty? and columns.empty?

        query =<<SQL
SELECT
  #{select_or_group_query_partial(rows, columns, values)}

FROM carts INNER JOIN users ON users.id = carts.user_id
  INNER JOIN product_carts ON product_carts.cart_id = carts.id
  INNER JOIN products ON product_carts.product_id = products.id
  INNER JOIN categories ON categories.id = products.category_id
WHERE carts.purchased_at IS NOT NULL AND #{search_query(filter_params)}
GROUP BY #{select_or_group_query_partial(rows, columns)}
SQL

        begin
          report = @client.query(query)
          return report
        rescue Mysql2::Error => e
          File.open(ERR_LOG_LOCAL_FILE_PATH, "a") { |file|
            file.puts e.errno
            file.puts e.error
            file.puts query
            file.puts ""
          }
        end
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