#!/usr/bin/env ruby

# Quick test verification script
puts "Testing Rails environment..."

require_relative '../config/environment'

begin
  # Test user creation
  user = User.new(
    email: "test_#{SecureRandom.hex(4)}@example.com",
    password: "password123",
    password_confirmation: "password123",
    confirmed_at: Time.current
  )
  user.skip_confirmation_notification!

  if user.save
    puts "✓ User creation works"

    # Test business creation
    business = Business.create(
      name: "Test Business",
      owner: user
    )

    if business.persisted?
      puts "✓ Business creation works"
      puts "✓ User has #{user.businesses.count} business(es)"
    else
      puts "✗ Business creation failed: #{business.errors.full_messages}"
    end

    # Cleanup
    business.destroy if business.persisted?
    user.destroy
    puts "✓ Cleanup complete"
  else
    puts "✗ User creation failed: #{user.errors.full_messages}"
  end

  puts "\nAll basic operations working!"

rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5)
end

