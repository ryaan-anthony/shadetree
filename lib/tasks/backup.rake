# The verification half of the restore drill (PLT-09). ops/backup/docker.sh restore-drill restores
# a backup set into scratch databases and a scratch storage volume, then runs this against them in
# the app's image: COUNTS=<the set's counts file, name=count lines> (optional).
namespace :backup do
  desc "Check a restored database and storage: COUNTS=<file of name=count lines from the backup>"
  task verify_restore: :environment do
    expected = ENV["COUNTS"].present? ? File.readlines(ENV["COUNTS"], chomp: true).filter_map { _1.split("=", 2) if _1.include?("=") }.to_h : {}
    result = RestoreCheck.new(expected:).call
    puts result.lines
    abort "Restore drill FAILED: #{result.failures.size} check(s) did not pass." unless result.ok
    puts "Restore drill passed."
  end
end
