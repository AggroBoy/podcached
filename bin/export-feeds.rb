require 'rss/1.0'
require 'rss/2.0'
require 'rss/itunes'
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

$logger.info "podcached starting"

feeds = File.open('/etc/podcached/podcasts').read
feeds.each_line do |feed|
    begin
        feed.strip!
        if !feed.empty? and !feed.start_with?("#")
            name, url = feed.split
            $feeds.push({ :feedname => name, :title => name, :link => url })
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
            body.outline :text => feed[:title], :type => "rss", :title => feed[:title], :xmlUrl => feed[:link], :htmlUrl => feed[:link]
        end
    end
end
opml_file.close

$logger.info "podcached done"

