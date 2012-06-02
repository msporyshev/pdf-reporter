require "wicked_pdf"
require "action_view"
require "erb"
require "prawn"

class Array
  def sum
    result = 0
    if block_given?
      self.each { |e| result += yield(e) }
    else
      self.each { |e| result += e }
    end
    result
  end
end

class Prawn::Table
  public :natural_column_widths
end

class PdfReporter

  class View < Prawn::Document

    include ActionView::Helpers::NumberHelper

    def initialize(report, value_type, filter_string)
      super(top_matgin: 70)

      @report, @value_type, @filter_string = report, value_type, filter_string

      report_main_header
      report_table
    end

    def draw_report_table(report_rows)
      counts = []

      t = make_table report_rows

      cur_count, cur_width = 0, 0
      is_first_table = true
      t.natural_column_widths.each do |width|
        cur_count += 1
        cur_width += width

        if cur_width >= bounds.width and
          is_first_table or
          !is_first_table and
          cur_width + t.natural_column_widths[0] >= bounds.width

          counts << cur_count - 1
          cur_count, cur_width = 1, width

          is_first_table = false if is_first_table
        end

      end
      counts << cur_count

      cur_page_table = []
      cur_begin = 0
      counts.each do |count|
        report_rows.each do |row|
          cur_row = []
          cur_row << row[0] if cur_begin != 0
          cur_row += row[Range.new(cur_begin, cur_begin + count - 1)]
          cur_page_table << cur_row
        end
        cur_begin += count

        table cur_page_table, :cell_style => { align: :right} do
          row(0).font_style = :bold
          columns(0).align = :left
          self.row_colors = ["DDDDDD", "FFFFFF"]
          self.header = true
        end

        move_down 20
        cur_page_table = []
      end
    end

    def report_main_header
      text "Report for #{Time.now.to_s}", size: 30, style: :bold
      move_down 10
      text "Value type:", style: :bold
      text @value_type.to_s

      move_down 10
      text "Filter SQL:", style: :bold
      text @filter_string.to_s
    end

    def report_table
      move_down 20

      draw_report_table report_rows
    end

    def report_rows
      first_row = [""] + @report.header[1]
      result = [] << first_row

      @report.header[0].each do |r_header|
        cur_row = []
        cur_row << r_header.to_s
        @report.header[1].each do |c_header|
            cur_row << "" if @report.body[r_header][c_header].blank?

            @report.body[r_header][c_header].each do |cell|
                cur_row <<  (cell[:label] == "Price" ? number_to_currency(cell[:value]).to_s : cell[:value].to_i)
            end
        end

        result << cur_row
      end
      result
    end

    def self.gen_pdf(report, value_type, filter_string, file_path)

      pdf = View.new(report, value_type, filter_string)

      File.open(file_path, "w") { |file| file << pdf.render }
    end

  end

end