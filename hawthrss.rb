require 'net/http'
require 'uri'
require 'feedjira'
require 'pry'

class Item
  attr_accessor :id, :title, :url, :updated_at, :content, :feed
  def initialize(id:, title:, url:, updated_at:, content:, feed:)
    @title = title
    @url = url
    @updated_at = updated_at
    @content = content
    @feed = feed
  end
end

class BaseConsumer
  attr_reader :title, :items

  def initialize(options)
    @fetched = false
    @title = nil
    @items = nil
  end

  def fetched?
    @fetched
  end

  def fetch
    do_fetch unless fetched?
  end
end

class HttpConsumer < BaseConsumer
  def initialize(options)
    @url = options.delete(:url) || raise("option :url required")
    super(options)
  end

  def do_fetch
    uri = URI.parse(@url)
    response = Net::HTTP.get_response(uri)
    return response.body
  end
end

class AtomConsumer < HttpConsumer
  def initialize(options)
    super(options)
  end

  def do_fetch
    xml = super()
    feed = Feedjira.parse(xml)
    @title = feed.title
    @items = feed.entries.map do |item|
      Item.new(
        id: item.id,
        title: item.title,
        url: item.url,
        updated_at: item.published || item.updated,
        content: item.content || item.summary,
        feed: self
      )
    end
  end
end

class XkcdConsumer < AtomConsumer
  def initialize(options = {})
    super({ url: 'https://xkcd.com/atom.xml' }.merge(options))
  end
end

class SmbcConsumer < AtomConsumer
  def initialize(options = {})
    super({ url: 'https://www.smbc-comics.com/rss.php' }.merge(options))
  end

  def do_fetch
    super()
    items.each do |item|
      item.content.gsub!(%r{<br><br><a href="[^">]*">Click here to go see the bonus panel!</a>}i, '')
      item.content.gsub!(/<br><br><a href=[^>]*>New comic.*/i, '')
    end
  end
end

feeds = [
  XkcdConsumer.new,
  SmbcConsumer.new,
]

feeds.each(&:fetch)

items = feeds.flat_map(&:items)
items.sort_by!(&:updated_at)
items.reverse!

File.open("output.html", 'w') do |output|
  output.puts <<~HTML
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="UTF-8" />
      <title>HawthRSS</title>
      <meta name="viewport" content="width=device-width" />
      <link rel="stylesheet" href="assets/style.css" />
    </head>
    <body>
  HTML
  items.each do |item|
    output.puts <<~HTML
    <article>
      <h1><a href="#{item.url}">#{item.title}</a></h1>
      <time>#{item.updated_at}</time>
      <div class="body">
        #{item.content}
      </div>
    </article>
    HTML
    output.puts "<hr />"
  end
  output.puts <<~HTML
    </body>
  </html>
  HTML
end
