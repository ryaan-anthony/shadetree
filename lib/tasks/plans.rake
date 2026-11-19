# Plans (BIL-01). Operators change plans without a deploy (until the operator console, OPS-02):
#   bin/rails plans:list
#   bin/rails plans:set PLAN=free LIMIT=quotes_sent VALUE=10      # VALUE=unlimited for no limit
#   bin/rails plans:set PLAN=pro FEATURE=sms VALUE=true
#   bin/rails plans:set PLAN=starter FIELD=monthly_price VALUE=24 # or annual_price, name, public…
#   bin/rails plans:comp BUSINESS=<uid> LIMIT=quotes_sent VALUE=50 # one business's override
#   bin/rails plans:sync                                           # add plans missing from the database
# Every db:prepare adds plans missing from the database; existing plans are never overwritten.
Rake::Task["db:prepare"].enhance { Rake::Task["plans:sync"].invoke } if Rake::Task.task_defined?("db:prepare")

module PlanTasks
  module_function

  # VALUE is required; only "unlimited" means no limit.
  def value(raw)
    abort "Give VALUE= (a number, unlimited, true or false)" if raw.nil? || raw.empty?

    case raw.to_s
    when "unlimited" then nil
    when "true" then true
    when "false" then false
    when /\A\d+\z/ then raw.to_i
    else raw
    end
  end

  def set(record, column)
    key = ENV["LIMIT"] || ENV["FEATURE"]
    record[column] = record[column].merge(key => value(ENV["VALUE"]))
  end
end

namespace :plans do
  desc "Load db/seeds/plans.yml (OVERWRITE=1 replaces existing plans)"
  task sync: :environment do
    written = Plan.sync!(overwrite: ENV["OVERWRITE"] == "1")
    puts written.any? ? "Wrote plans: #{written.join(", ")}" : "Plans already up to date (OVERWRITE=1 to replace)"
  end

  desc "List plans with their prices, limits and features"
  task list: :environment do
    Plan.order(:position, :id).each do |plan|
      puts "#{plan.key}#{" (default)" if plan.default}#{" (hidden)" unless plan.public}: #{plan.name}, #{plan.monthly_price.format}/mo, #{plan.annual_price.format}/yr"
      puts "  limits: #{Plan::LIMITS.keys.map { "#{_1}=#{plan.limits.fetch(_1, nil) || "unlimited"}" }.join(", ")}"
      puts "  features: #{plan.features.select { _2 }.keys.join(", ").presence || "none"}"
    end
  end

  desc "Change a plan: PLAN=key and LIMIT=, FEATURE= or FIELD= with VALUE="
  task set: :environment do
    plan = Plan.find_by!(key: ENV.fetch("PLAN"))
    if ENV["LIMIT"] then PlanTasks.set(plan, :limits)
    elsif ENV["FEATURE"] then PlanTasks.set(plan, :features)
    elsif %w[monthly_price annual_price].include?(ENV["FIELD"]) then plan["#{ENV["FIELD"]}_cents"] = Money.parse(ENV.fetch("VALUE"), plan.currency).cents
    elsif ENV["FIELD"] == "public"
      abort "public is true or false" unless %w[true false].include?(ENV["VALUE"])
      plan.public = ENV["VALUE"] == "true"
    elsif %w[name description position provider_monthly_price provider_annual_price].include?(ENV["FIELD"]) then plan[ENV["FIELD"]] = ENV.fetch("VALUE")
    else abort "Give LIMIT=, FEATURE= or FIELD= (monthly_price, annual_price, name, description, public, position, provider_monthly_price, provider_annual_price)"
    end
    plan.save!
    puts "#{plan.key} saved."
  end

  desc "Override one business's limit or feature: BUSINESS=uid and LIMIT= or FEATURE= with VALUE= (CLEAR=1 removes it)"
  task comp: :environment do
    business = Business.find_by!(uid: ENV.fetch("BUSINESS"))
    group = ENV["LIMIT"] ? "limits" : "features"
    key = ENV["LIMIT"] || ENV.fetch("FEATURE")
    allowed = group == "limits" ? Plan::LIMITS : Plan::FEATURES
    abort "Unknown #{group.singularize} #{key}" unless allowed.key?(key)
    overrides = business.plan_overrides.deep_dup
    overrides[group] ||= {}
    ENV["CLEAR"] == "1" ? overrides[group].delete(key) : overrides[group][key] = PlanTasks.value(ENV["VALUE"])
    business.update!(plan_overrides: overrides)
    puts "#{business.name}: #{overrides.inspect}"
  end
end
