ENV["RAILS_ENV"] ||= 'test'
require File.expand_path("../../config/environment",__FILE__)
require 'rspec/rails'
require 'capybara/rails'
require 'phantomjs'
require 'capybara/rspec'
require 'phantomjs/poltergeist'
require 'database_cleaner'

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, :phantomjs => Phantomjs.path, :js_errors => false, :default_wait_time => 5, :timeout => 90)
end

Capybara.javascript_driver = :poltergeist

Devise::TestHelpers
Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f}
Dir[Rails.root.join("spec/features/support/**/*.rb")].each {|f| require f}

Capybara.ignore_hidden_elements = false

RSpec.configure do |config|
  config.include Devise::TestHelpers, :type => :controller
  config.extend ControllerHelpers, :type => :controller
  config.fixture_path = "#{::Rails.root}/spec/features/fixtures"
  config.use_transactional_fixtures = false

  config.before(:each) do
    allow_any_instance_of(ApplicationController).to receive(:get_client_ip).and_return("192.1.1.1")
    allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.1.1.1')
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.infer_spec_type_from_file_location!

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    Rails.cache.clear
    #FileUtils.rm_rf(Dir["#{Rails.root}/log/test.log"])
  end

  config.before(:each) do
    DatabaseCleaner.start
  end
 
  config.after(:each) do
    DatabaseCleaner.clean
    Rails.cache.clear
  end

  config.after(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    Rails.cache.clear
    Warden.test_reset!
  end

  config.before(:all) do
    include Warden::Test::Helpers
    Warden.test_mode!
  end

  config.after(:all) do
    Warden.test_reset!
  end
end

