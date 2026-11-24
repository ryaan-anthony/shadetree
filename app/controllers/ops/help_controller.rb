# OPS-06: what the help articles miss: searches that found nothing (their words and how often,
# last 90 days) and each article's "Was this helpful?" counts. Nothing about who.
class Ops::HelpController < Ops::BaseController
  def show
    @misses = HelpSearchMiss.summary
    @articles = HelpArticle.where("helpful_count + unhelpful_count > 0").order(unhelpful_count: :desc, helpful_count: :asc, title: :asc)
  end
end
