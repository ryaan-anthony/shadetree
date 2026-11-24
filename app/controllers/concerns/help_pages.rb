# OPS-06: what the public help centre (HelpController) and the members' copy in the app
# (Admin::HelpArticlesController) share: the loaded articles, kept in step with the table that
# search reads, and looking an article up by its slug in that index.
module HelpPages
  extend ActiveSupport::Concern

  included do
    helper_method :help_library
    before_action { HelpArticle.ensure_current!(help_library) }
  end

  private

  def help_library = HelpCentre.library

  # The slug is only ever a key into the loaded index, never part of a file path.
  def find_article!
    help_library.find(params[:slug].to_s) || raise(ActiveRecord::RecordNotFound, "No help article")
  end
end
