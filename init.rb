require 'inlink_ads'
ActionView::Base.send         :include, InLinkAds::ViewHelper
ActionController::Base.send   :include, InLinkAds::AdController

# Install the before_filter
ActionController::Base.before_filter :textlinkads