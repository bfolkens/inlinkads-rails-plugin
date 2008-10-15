require 'net/http'
require 'cgi'

module InLinkAds
  def self.configured?
    !CONFIG.nil? and !CONFIG[:key].nil? and !CONFIG[:url].nil?
  end
  
  module ViewHelper
    def inject_inlink_ads(post_id, str)
      return str unless InLinkAds::configured? and !@links.nil? and !@links['Link'].nil?
      
      returning str.dup do |out|
        @links['Link'].each do |link|
          # Only use links for this post
          next unless link['PostID'].to_s == post_id.to_s
      
          # Substitute the first instance of text at word boundaries for link
          out.sub! /\b(#{Regexp::escape(link['Text'][0])})\b/i, link_to('\1', link['URL'][0])
        end
      end
    end
  end
  
  module AdController    
    protected
    
    def render_sync_posts
      unless params[:textlinkads_key] == InLinkAds::CONFIG[:key]
        render :text => "Inlinks Ads: '#{InLinkAds::CONFIG[:key]}' expected but '#{params[:textlinkads_key]}' received from request instead", :status => 409
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

        posts = read_posts(last, 100)
        last = posts.last.id

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
        render :text => "Inlinks Ads: invalid action '#{params[:textlinkads_action]} received from request", :status => 409
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
        @links = requester(url)
    
        # if we can get the latest, then update the cache
        unless @links.nil?
          expire_fragment time_key
          expire_fragment data_key
          write_fragment time_key, Time.now + 1.hours  # used to be 6.hours but shortened it up for testing
          write_fragment data_key, @links
        else
          # otherwise try again in 1 hour
          write_fragment time_key, Time.now + 1.hour
          @links = read_fragment(data_key)
        end
      else
        # use the cache
        @links = read_fragment(data_key)
      end
    end
    
    def read_posts
      raise 'Need to define "read_posts" in ApplicationController'
    end
    
    def post_url
      raise 'Need to define "post_url" in ApplicationController'
    end
    
    def max_post_id
      raise 'Need to define "max_post_id" in ApplicationController'
    end
      
    private
    
    def request_url
      "http://www.text-link-ads.com/xml.php?inventory_key=#{InLinkAds::CONFIG[:key]}"
    end
  
    def requester(url)
      XmlSimple.xml_in http_get(url)
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