class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :feature?

  private

  # Release flags for the current business (PLT-11).
  def feature?(name) = Feature.enabled?(name)
end
