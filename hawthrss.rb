require 'net/http'
require 'uri'
require 'feedjira'
require 'pry'

class Item
  attr_accessor :id, :title, :url, :updated_at, :content, :feed, :media_url
  def initialize(id:, title:, url:, updated_at:, content:, feed:, media_url: nil)
    @title = title
    @url = url
    @updated_at = updated_at
    @content = content
    @feed = feed
    @media_url = media_url
  end
end

class BaseConsumer
  attr_reader :title, :items

  def initialize(options)
    @options = options
    @fetched = false
    @title = nil
    @items = nil
  end

  def fetched?
    @fetched
  end

  def fetch
    unless fetched?
      do_fetch
      do_filter
      do_transform
    end
  end

  def item_matches_filter(item, filter)
    case filter
    when String
      item.title.downcase.include?(filter.downcase)
    when Regex
      filter === item.title
    else
      raise "unsupported filter: #{filter.inspect}"
    end
  end

  def do_filter
    Array(@options[:only]).each do |filter|
      items.select! do |item|
        item_matches_filter(item, filter)
      end
    end
    Array(@options[:except]).each do |filter|
      items.reject! do |item|
        item_matches_filter(item, filter)
      end
    end
  end

  def do_transform
  end
end

class HttpConsumer < BaseConsumer
  attr_reader :id

  def initialize(options)
    @url = options.delete(:url) || raise("option :url required")
    @id = "#{self.class}:#{@url}"
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
        media_url: item.media_url,
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

  def do_transform
    items.each do |item|
      item.content.gsub!(%r{<br><br><a href="[^">]*">Click here to go see the bonus panel!</a>}i, '')
      item.content.gsub!(/<br><br><a href=[^>]*>New comic.*/i, '')
    end
  end
end

class YoutubeConsumer < AtomConsumer
  def initialize(options = {})
    raise "only specify one of :channel_id and :user" if options[:channel_id] && options[:user]
    url =
      if options[:channel_id]
        "https://www.youtube.com/feeds/videos.xml?channel_id=#{options[:channel_id]}"
      elsif options[:user]
        "https://www.youtube.com/feeds/videos.xml?user=#{options[:user]}"
      else
        raise "must specify either :channel_id or :user"
      end
    super({ url: url }.merge(options))
  end

  def do_transform
    items.each do |item|
      item.content = <<~HTML
        <iframe id="ytplayer" type="text/html" width="800" height="480"
         src="#{item.media_url.gsub('/v/', '/embed/')}"
         frameborder="0"></iframe>
        (<a href="http://#{item.url}">direct link</a>)
      HTML
    end
  end
end

feeds = [
  YoutubeConsumer.new(channel_id: 'UCPD_bxCRGpmmeQcbe2kpPaA', only: 'Hot Ones'),
  YoutubeConsumer.new(user: 'bgfilms', except: 'Basics with Babish'),
  YoutubeConsumer.new(channel_id: 'UCfMJ2MchTSW2kWaT0kK94Yw'),
  YoutubeConsumer.new(user: 'voxdotcom'),
  YoutubeConsumer.new(user: 'day9tv', only: 'Starcraft'),
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
