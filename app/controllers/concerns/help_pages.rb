# OPS-06: what the public help centre (HelpController) and the members' copy in the app
# (Admin::HelpArticlesController) share: the loaded articles, kept in step with the table that
# search reads, and looking an article up by its slug in that index.
module HelpPages
  extend ActiveSupport::Concern
  MISSES_PER_HOUR = 30
  VOTES_PER_HOUR = 30 # and three per article per address a day

  included do
    helper_method :help_library, :voted_param
    rate_limit to: HelpPages::VOTES_PER_HOUR, within: 1.hour, only: :vote, with: -> { vote_over_limit }, name: "help-votes"
    rate_limit to: 3, within: 1.day, by: -> { "#{request.remote_ip}:#{params[:slug]}" }, only: :vote, with: -> { vote_over_limit }, name: "help-vote-article"
    before_action { HelpArticle.ensure_current!(help_library) }
  end

  # "Was this helpful?": counted, then the thanks (and, after a no, the way to ask us).
  def vote
    article = find_article!
    voted = params[:helpful] == "yes" ? "yes" : "no"
    HelpArticle.where(slug: article.slug).update_all(voted == "yes" ? "helpful_count = helpful_count + 1" : "unhelpful_count = unhelpful_count + 1")
    answer_vote(article, voted)
  end

  private

  def help_library = HelpCentre.library

  # ?q=: the articles matching it, best first. A search that finds nothing is counted by its
  # words (HelpSearchMiss), except while typing in the app's list (its frame), where each pause
  # would count a half-typed word; and at most MISSES_PER_HOUR from one address.
  def search_articles
    @query = params[:q].to_s.squish.first(100)
    return if @query.blank?

    @results = HelpArticle.search(@query).limit(20).pluck(:slug).filter_map { help_library.find(_1) }
    return if @results.any? || turbo_frame_request? || Current.impersonator # support searching as a member isn't the member's miss

    HelpSearchMiss.record(@query) if under_limit?("help-misses", MISSES_PER_HOUR)
  end

  # Over the limit, the answer is the same thanks, without counting.
  def vote_over_limit = answer_vote(find_article!, params[:helpful] == "yes" ? "yes" : "no")

  def answer_vote(article, voted)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("help-vote", partial: "shared/help/vote", locals: { article:, voted: }) }
      format.html { redirect_to helpers.help_path_for(article.slug, voted:) + "#help-vote" }
    end
  end

  # The same counter store as rate_limit (a null store in tests: always under).
  def under_limit?(name, limit)
    count = ActionController::Base.cache_store.increment("#{name}:#{request.remote_ip}", 1, expires_in: 1.hour)
    count.nil? || count <= limit
  end

  def voted_param = params[:voted].presence_in(%w[yes no])

  # The slug is only ever a key into the loaded index, never part of a file path.
  def find_article!
    help_library.find(params[:slug].to_s) || raise(ActiveRecord::RecordNotFound, "No help article")
  end
end
