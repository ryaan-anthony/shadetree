# OPS-06: the public help centre at /help (marketing layout, indexed). A signed-in member is
# sent to the same page in the app (Admin::HelpArticlesController), where they can ask
# Shadetree if the article doesn't answer it.
class HelpController < ApplicationController
  include HelpPages
  public_page!
  layout "marketing"
  before_action :send_members_to_the_app

  def index
    search_articles
  end

  def show
    @article = find_article!
  end

  private

  def send_members_to_the_app
    return unless user_signed_in? && current_user.business_users.active.exists?

    redirect_to(params[:slug] ? admin_help_article_path(params[:slug]) : admin_help_articles_path(q: params[:q].presence), status: :found)
  end
end
