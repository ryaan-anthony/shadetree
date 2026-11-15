# Runtime control of release flags (PLT-11). Business arguments take the business's uid.
#   bin/rails flags:list
#   bin/rails "flags:enable[new_quote_editor]"
#   bin/rails "flags:enable_for[new_quote_editor,bizOneUid001]"
#   bin/rails "flags:percentage[new_quote_editor,25]"
#   bin/rails "flags:disable[new_quote_editor]"
namespace :flags do
  by = -> { ENV.fetch("USER", "rake") }
  find_business = ->(uid) { Business.find_by!(uid:) }

  desc "List declared flags and their state"
  task list: :environment do
    Feature.status.each do |definition, flag|
      detail = case flag.state
      when "businesses" then " (#{flag.business_ids.size} businesses)"
      when "percentage" then " (#{flag.percentage}%)"
      else ""
      end
      puts format("%-32s %-11s owner %-18s remove by %-4s %s", definition.name, flag.state + detail, definition.owner, definition.remove_by, definition.description)
    end
  end

  desc "Turn a flag on for everyone"
  task :enable, [ :name ] => :environment do |_, args|
    Feature.enable!(args.fetch(:name), by: by.call)
    puts "#{args[:name]}: on"
  end

  desc "Turn a flag off for everyone"
  task :disable, [ :name ] => :environment do |_, args|
    Feature.disable!(args.fetch(:name), by: by.call)
    puts "#{args[:name]}: off"
  end

  desc "Turn a flag on for one business (by uid)"
  task :enable_for, [ :name, :business ] => :environment do |_, args|
    Feature.enable_for!(args.fetch(:name), find_business.call(args.fetch(:business)), by: by.call)
    puts "#{args[:name]}: on for #{args[:business]}"
  end

  desc "Turn a flag off for one business (by uid)"
  task :disable_for, [ :name, :business ] => :environment do |_, args|
    Feature.disable_for!(args.fetch(:name), find_business.call(args.fetch(:business)), by: by.call)
    puts "#{args[:name]}: off for #{args[:business]}"
  rescue Feature::UnsupportedChange => error
    abort error.message
  end

  desc "Turn a flag on for a percentage of businesses"
  task :percentage, [ :name, :percent ] => :environment do |_, args|
    Feature.enable_percentage!(args.fetch(:name), args.fetch(:percent), by: by.call)
    puts "#{args[:name]}: #{args[:percent]}% of businesses"
  end
end
