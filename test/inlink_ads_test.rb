$:.unshift(File.dirname(__FILE__) + '/../lib')

require File.dirname(__FILE__) + '/../../../../config/environment'
require 'test/unit'
require 'rubygems'

require 'action_controller/test_process'

ActionController::Base.logger = nil
ActionController::Routing::Routes.reload rescue nil

silence_warnings do
  Post = Struct.new("Post", :title, :body)
  class Post
    alias_method :title_before_type_cast, :title unless respond_to?(:title_before_type_cast)
    alias_method :body_before_type_cast, :body unless respond_to?(:body_before_type_cast)
    
    def self.example
      returning Post.new do |post|
        def post.id; 123; end
        def post.id_before_type_cast; 123; end
        post.title = "Hello World"
        post.body = "Some text here that should get replaced\n   with links."
      end
    end
    
    def created_at; Time.at(0); end
  end
end

# Override requester method with mock
module InLinkAds::AdController
  private
  
  def requester(url)
    XmlSimple.xml_in <<-XML
    <Links>
      <Link>
        <PostID>123</PostID>
        <Text>replaced with</Text>
        <URL>http://www.linkexample.com</URL>
      </Link>
    </Links>
    XML
  end
end
  
class InLinkAdsTest < Test::Unit::TestCase
  def perform_action; nil; end
  def params; @params; end
  def render(params); @rendered = params; end
  include ActionController::Caching
  include ActionView::Helpers::UrlHelper
  
  include InLinkAds::ViewHelper
  include InLinkAds::AdController
  
  InLinkAds::Config.url = 'http://www.mysite.com/'
  InLinkAds::Config.key = '01234567890123456789'
  
  def setup    
    @post = Post.example
  end
  
  
  def test_should_detect_configuration
    assert InLinkAds::configured?
  end

  def test_should_populate_links
    inlink_ads_data
    assert @links.any?
  end

  def test_should_inject_ads
    inlink_ads_data
    assert_equal %Q{Some text here that should get <a href="http://www.linkexample.com">replaced\n   with</a> links.},
                 inject_inlink_ads(@post.id, @post.body)
  end
  
  def test_should_respond_with_sync_posts
    @params = { :textlinkads_key => InLinkAds::Config.key,
                :textlinkads_action => 'sync_posts' }
    render_sync_posts
    assert_equal <<-XML.strip, @rendered[:xml]
<posts><post><id>123</id><title>Hello+World</title><date>Wed Dec 31 18:00:00 -0600 1969</date><url>http://www.mysite.com/posts/123</url><body>Some+text+here+that+should+get+replaced++++with+links.</body></post></posts>
    XML
  end
  
  def test_should_respond_with_sync_one_post
    @params = { :textlinkads_key => InLinkAds::Config.key,
                :textlinkads_action => 'sync_posts',
                :textlinkads_post_id => '123' }
    render_sync_posts
    assert_equal <<-XML.strip, @rendered[:xml]
<posts><post><id>123</id><title>Hello+World</title><date>Wed Dec 31 18:00:00 -0600 1969</date><url>http://www.mysite.com/posts/123</url><body>Some+text+here+that+should+get+replaced++++with+links.</body></post></posts>
    XML
  end
  
  def test_should_respond_to_debug
    @params = { :textlinkads_key => InLinkAds::Config.key,
                :textlinkads_action => 'debug' }
    render_sync_posts
    assert_equal <<-XML.strip, @rendered[:xml]
<debug><last_id>0</last_id><max_id>123</max_id><last_updated></last_updated></debug>
    XML
  end
  
  protected
  
  def max_post_id; Post.example.id; end
  def read_posts(last, limit); [Post.example]; end
  def read_post(id); Post.example; end
  def post_url(record); "http://www.mysite.com/posts/#{record.id}"; end
end
