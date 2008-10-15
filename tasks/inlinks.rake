require 'net/http'

namespace :inlinks do
  desc 'Send the installation command to TLA/InLinks'
  task :install => :environment do
    raise 'InLinkAds CONFIG is not set' unless InLinkAds::configured?
    url = "http://www.text-link-ads.com/post_level_sync.php?action=install&inlinks=true&inventory_key=#{InLinkAds::CONFIG[:key]}&site_url=#{InLinkAds::CONFIG[:url]}"
    res = Net::HTTP.get_response(URI.parse(url))
    raise "Request to #{url} returned #{res.code}" unless res.is_a?(Net::HTTPSuccess)
  end
end