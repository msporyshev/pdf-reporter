require "wicked_pdf"
require "action_view"
require "erb"

class PdfReporter

  class View

    include ActionView::Helpers::NumberHelper

    def initialize(report, value_type, filter_string)
      @report, @value_type, @filter_string = report, value_type, filter_string
    end

    def gen_pdf(file_path)
      rhtml =<<HTML
<h1> Report for #{Time.now.to_s}</h1>
<strong>  Value: </strong> <%= @value_type %>
<strong>  Fitler SQL: </strong> <%= @filter_string %>

<table border="1">
  <thead>
    <th>
      <% @report.header[1].each do |header| %>
        <td><%= header.to_s %></td>
      <% end %>
    </th>
  </thead>
  <tbody>
    <% @report.header[0].each do |r_header| %>
      <tr>
        <td><%= r_header.to_s %></td>
        <% @report.header[1].each do |c_header| %>
          <td>
            <% @report.body[r_header][c_header].each do |cell| %>
              <div>
                <%= cell[:label] == "Price" ? number_to_currency(cell[:value]) : cell[:value].to_i %>
              </div>
            <% end %>
          </td>
        <% end %>
      </tr>
    <% end %>
  </tbody>
</table>
HTML

      html = ERB.new(rhtml).result(binding)
      pdf = WickedPdf.new.pdf_from_string(html)

      File.open(file_path, "w") { |file| file << pdf }
    end

  end

end