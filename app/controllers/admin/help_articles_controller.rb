# OPS-06: the help articles for members, in the app (noindex, with a canonical link to the
# public copy at /help). /admin/help stays the list of their questions (OPS-05).
class Admin::HelpArticlesController < Admin::BaseController
  include HelpPages
  impersonation :read_only # OPS-03: support can read what the member reads
  allow_any_member

  def index
  end

  def show
    @article = find_article!
  end
end
