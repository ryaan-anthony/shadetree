# MKT-01: plans, prices, limits and features, all from the plan data (BIL-01).
class PricingController < ApplicationController
  public_page!
  layout "marketing"

  def index
    @plans = Plan.listed.to_a
  end
end
