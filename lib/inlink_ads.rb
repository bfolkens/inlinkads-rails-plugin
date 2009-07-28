require 'net/http'
require 'cgi'
require 'timeout'
require 'active_support'

module InLinkAds
  class Config
    cattr_accessor :key, :url, :timeout
    @@timeout = 5
    
    def self.initialized?
      !key.nil? and !url.nil?
    end
  end
  
  def self.configured?
    Config::initialized?
  end
  
  module ViewHelper
    def inject_inlink_ads(post_id, str)
      return str unless InLinkAds::configured? and !@links.nil? and !@links['Link'].nil?
      
      Rails.logger.debug "Checking post #{post_id.to_s} against #{@links['Link'].map {|link| link['PostID'].to_s.to_i}.sort.join(',')}"
      returning str.dup do |out|
        @links['Link'].each do |link|
          # Only use links for this post
          next unless link['PostID'].to_s == post_id.to_s
      
          # Substitute the first instance of text at word boundaries for link
          keyword_pattern = Regexp::escape(link['Text'][0]).gsub(/\\ /, '\s+')
          match_pattern = /\b(#{keyword_pattern})\b/im
          Rails.logger.debug "InLink Ads: searching for '#{match_pattern.inspect}'"
          out.sub! match_pattern, link_to('\1', link['URL'][0])
        end
      end
    end
  end
  
  module AdController
    protected

    def textlinkads
      if params.keys.any? {|key| key.to_s =~ /^textlinkads_/ }
        render_sync_posts
        return false
      end
      
      true
    end
    
    def render_sync_posts
      unless params[:textlinkads_key] == InLinkAds::Config.key
        render :text => "Inlinks Ads: invalid key", :status => 409
        return false
      end
      
      url = request_url
      last_key = "TLA/LAST/#{url}"
      max_key = "TLA/MAX/#{url}"
            
      case params[:textlinkads_action]
      when 'debug'
        render :text => 'debug'
      when 'sync_posts'
        last = read_fragment(last_key) || 0
        max = read_fragment(max_key) || max_post_id

        if params[:textlinkads_post_id]
          posts = [read_post(params[:textlinkads_post_id])].compact
        else
          posts = read_posts(last, 100)
          last = posts.last.id
        end

        write_fragment last_key, last
        write_fragment max_key, max

        render :xml => posts_to_xml(posts)
      when 'reset_syncing'
        expire_fragment last_key
        render :text => 'reset last id'
      when 'reset_sync_limit'
        expire_fragment max_key
        render :text => 'reset max id'
      else
        render :text => "Inlinks Ads: invalid action", :status => 409
        return false
      end
      
      true
    end

    def inlink_ads_data
      return unless InLinkAds::configured?
      
      url = request_url
      time_key = "TLA/TIME/#{url}"
      data_key = "TLA/DATA/#{url}"

      # is it time to update the cache?
      time = read_fragment(time_key)
      if time.nil? or time.to_time < Time.now
        Rails.logger.debug "InLink Ads: last fragment time EXPIRED - refreshing '#{data_key}'"
        @links = requester(url)
    
        # if we can get the latest, then update the cache
        unless @links.nil? or @links['Link'].nil?
          Rails.logger.debug "InLink Ads: #{@links['Link'].size} ads retrieved from service"
          expire_fragment time_key
          expire_fragment data_key
          write_fragment time_key, Time.now + 1.hours  # used to be 6.hours but shortened it up for testing
          write_fragment(data_key, @links && @links.to_yaml)
        else
          Rails.logger.debug "InLink Ads: NO ads retrieved from service"
          # otherwise try again in 1 hour
          write_fragment time_key, Time.now + 1.hour
          data = read_fragment(data_key)
          @links = data ? YAML.load(data) : data
        end
      else
        # use the cache
        data = read_fragment(data_key)
        @links = data ? YAML.load(data) : data
      end
    end
    
		def read_post(id)
      raise 'Need to define "read_post" in ApplicationController'
		end

    def read_posts(last, limit)
      raise 'Need to define "read_posts" in ApplicationController'
    end
    
    def post_url(record)
      raise 'Need to define "post_url" in ApplicationController'
    end
    
    def max_post_id
      raise 'Need to define "max_post_id" in ApplicationController'
    end
      
    private
    
    def request_url
      "http://www.text-link-ads.com/xml.php?inventory_key=#{InLinkAds::Config.key}"
    end
  
    def requester(url)
      Timeout::timeout(InLinkAds::Config.timeout) do
        return XmlSimple.xml_in http_get(url)
      end
    rescue Timeout::Error => te
      Rails.logger.error "InLink Ads: cannot retrieve ads from service, request timed out after #{InLinkAds::Config.timeout} seconds"
      nil
    rescue
      nil
    end

    def http_get(url)
      Net::HTTP.get_response(URI.parse(url)).body.to_s
    end
    
    def posts_to_xml(records)
      xml = Builder::XmlMarkup.new
      xml.posts do
        records.each do |record|
          xml.post do
            xml.id record.id
            xml.title CGI::escape(record.title)
            xml.date record.created_at.to_s
            xml.url post_url(record)
            xml.body CGI::escape(record.body.gsub(/[\r\n]+/, ' ').gsub(%r{<.+?/?>}, ''))
          end
        end
      end
    end
  end  
end
