# MKT-01: the public home page.
class HomeController < ApplicationController
  layout "marketing"

  def index
    @plans = Plan.listed.to_a
  end
end
