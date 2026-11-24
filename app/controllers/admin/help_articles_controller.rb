# OPS-06: the help articles for members, in the app (noindex, with a canonical link to the
# public copy at /help). /admin/help stays the list of their questions (OPS-05).
class Admin::HelpArticlesController < Admin::BaseController
  include HelpPages
  impersonation :read_only # OPS-03: support can read what the member reads
  allow_any_member
  leaves_session_alone only: :suggestions
  rate_limit to: 120, within: 1.minute, only: :suggestions, with: -> { head :too_many_requests }

  def index
    search_articles
  end

  def show
    @article = find_article!
  end

  # OPS-06: articles offered on the ticket form as the subject is typed (POST keeps it out of
  # URLs). The page is the one the question is being sent from.
  def suggestions
    @suggestions = HelpCentre.suggestions(subject: params[:subject].to_s.first(150), page: params[:page])
    render turbo_stream: turbo_stream.replace("help-suggestions", partial: "admin/support_tickets/suggestions", locals: { suggestions: @suggestions })
  end
end
