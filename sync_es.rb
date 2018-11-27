require "csv"
require "net/http"
require "uri"
require "json"

INDEX_ID = 0
INDEX_TITLE = 1
INDEX_TITLE_YOMI = 2
INDEX_AUTHOR_SEI = 15
INDEX_AUTHOR_MEI = 16
INDEX_AUTHOR_SEI_YOMI = 17
INDEX_AUTHOR_MEI_YOMI = 18

class Book
  # 本番でこんなところに書いちゃ駄目だぞ!
  ENDPOINT = "http://localhost:9200/aozora"

  def initialize(id, title, title_yomi, author, author_yomi)
    @id = id
    @title = title
    @title_yomi = title_yomi
    @author = author
    @author_yomi = author_yomi
  end

  def post_index
    uri = URI.parse("#{ENDPOINT}/books/#{@id}")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.request_uri)
    req["Content-Type"] = "application/json"
    req.body = to_json
    res = http.request(req)
    p "#{@title} #{res.response.code}"
  end

  private

  def to_json
    # メタプロするとパラメータの追加に動的に対応できそう
    {title: @title, title_yomi: @title_yomi, auther: @author, auther_yomi: @author_yomi}.to_json
  end
end

# 本来であれば一括で挿入(bulk insert)できるのでそうした方が速い
CSV.foreach("list_person_all_extended_utf8.csv") do |line|
  next unless line[INDEX_ID] =~ /^[0-9]+/
  Book.new(
        line[INDEX_ID],
        line[INDEX_TITLE],
        line[INDEX_TITLE_YOMI],
        line[INDEX_AUTHOR_SEI] + line[INDEX_AUTHOR_MEI],
        line[INDEX_AUTHOR_SEI_YOMI] + line[INDEX_AUTHOR_MEI_YOMI]
  ).post_index
end