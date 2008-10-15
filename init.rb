require 'inlink_ads'
ActionView::Base.send         :include, InLinkAds::ViewHelper
ActionController::Base.send   :include, InLinkAds::AdController