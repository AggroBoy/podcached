require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'fileutils'
require 'yaml'
require 'builder'

require 'lumberjack'
require "lumberjack_syslog_device"

$logger = Lumberjack::Logger.new(Lumberjack::SyslogDevice.new)
$logger.set_progname "podcached"

$options = YAML.load_file("/etc/podcached/podcachedrc")

$feeds = []

# Allow open-uri to follow unsafe redirects (i.e. https to http).
# # Relevant issue:
# # http://redmine.ruby-lang.org/issues/3719
# # Source here:
# # https://github.com/ruby/ruby/blob/trunk/lib/open-uri.rb
module OpenURI
    class <<self
        alias_method :open_uri_original, :open_uri
        alias_method :redirectable_cautious?, :redirectable?

        def redirectable_baller? uri1, uri2
            valid = /\A(?:https?|ftp)\z/i
            valid =~ uri1.scheme.downcase && valid =~ uri2.scheme
        end
    end

    # The original open_uri takes *args but then doesn't do anything with them.
    # Assume we can only handle a hash.
    def self.open_uri name, options = {}
        value = options.delete :allow_unsafe_redirects

        if value
            class <<self
                remove_method :redirectable?
                alias_method :redirectable?, :redirectable_baller?
            end
        else
            class <<self
                remove_method :redirectable?
                alias_method :redirectable?, :redirectable_cautious?
            end
        end

        self.open_uri_original name, options
    end
end

def sanitize_filename(filename)
    return filename.strip.gsub(/[^:0-9A-Za-z.,\-'" ]/, '_')
end

def download_url(url)
    retries = 5

    begin 

        return open(url, :allow_unsafe_redirects => true).read

    rescue OpenURI::HTTPError, Timeout::Error
        retries -= 1
        $logger.warn "Error downloading #{url}. #{retries > 0 ? 'retrying' : ''}"
        retry if retries > 0
        $logger.error "Retry count exceeded, giving up on downloading #{url}"
        raise
    end
end

def process_rss(feedname, url)

    base_uri = $options["base_url"]

    rss = RSS::Parser.parse(download_url(url), false)

    # Some feeds leave this empty, which breaks the RSS parser's output
    rss.channel.description = "N/A" if rss.channel.description.empty?

    $feeds.push({ :feedname => feedname, :title => rss.channel.title, :link => rss.channel.link })

    for item in rss.items
        next if item.enclosure.nil?

        url = item.enclosure.url
        guid = URI::encode (item.guid.respond_to? :content) ? item.guid.content : item.guid
        guid.gsub!("/", "_")

        # NOTE: This should probably contain the guid somewhere, but I like
        # them to be human readable; so I'm hoping that pubdate to the second
        # and title is unique enough
        filename = feedname + "/" + item.pubDate.strftime("%Y-%m-%d %H:%M - ") + sanitize_filename(item.title) + File.extname(url)

        if not File::file? filename
            $logger.info "New episode found for #{feedname}. Downloading #{url} to #{filename}"

            data = download_url(url)
            FileUtils.mkdir_p(feedname)
            open(filename, 'wb') do |file|
                file << data
            end
        end

        item.enclosure.url = URI::encode(base_uri + filename)

        # Some feeds leave this out - they really *really* shouldn't.
        item.enclosure.length = File.size?(filename) if item.enclosure.length.nil?
    end

    File.open(feedname + "/feed", 'w') {|f| f.write(rss) }
end

$logger.info "podcached starting"
Dir.chdir $options["local_dir"]

feeds = File.open('/etc/podcached/podcasts').read
feeds.each_line do |feed|
    begin
        feed.strip!
        if !feed.empty? and !feed.start_with?("#")
            name, url = feed.split
            $logger.debug "processing #{name}"
            process_rss(name, url)
        end

    rescue Exception => e
        $logger.error "Error processing feed #{name}: #{e.message}"
        next
    end
end

opml_file = File.new("podcached.opml", "w")
builder = Builder::XmlMarkup.new :target => opml_file, :indent => 2
builder.instruct!
builder.opml :version => "1.0" do |opml|
    opml.head { |h| h.title "Podcached Podcasts" }
    opml.body do |body|
        $feeds.each do |feed|
            body.outline :text => feed[:title], :type => "rss", :title => feed[:title], :xmlUrl => "#{$options["base_url"]}#{feed[:feedname]}/feed", :htmlUrl => feed[:link]
        end
    end
end
opml_file.close

$logger.info "podcached done"

