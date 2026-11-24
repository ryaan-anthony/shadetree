# OPS-06: publish the help articles (content/help/articles) with each deploy.
Rails.application.config.after_initialize { HelpArticle.sync_at_boot unless Rails.env.test? }
