require "minitest/autorun"

require "sinatra/base"
require "open3"
require "webrick"

class ActionTest < MiniTest::Test
  def test_immediate_success
    job_id = "my-job-123"
    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      job_ids: [job_id],
      status_responses: {
        job_id => ["complete"]
      },
    )

    assert_predicate job_status, :success?

    assert_equal 2, api_requests.length

    assert_predicate api_requests[0], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "WestUs2",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[0].body)
    )

    assert_predicate api_requests[1], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/#{job_id}",
      api_requests[1].path
    )
  end

  def test_polling_success
    job_id = "my-job-123"
    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      job_ids: [job_id],
      status_responses: {
        job_id => ["pending", "running", "reticulating-splines", "complete"]
      },
    )

    assert_predicate job_status, :success?

    assert_equal 5, api_requests.length

    assert_predicate api_requests[0], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "WestUs2",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[0].body)
    )

    assert_predicate api_requests[1], :get?
    assert_predicate api_requests[2], :get?
    assert_predicate api_requests[3], :get?
    assert_predicate api_requests[4], :get?
  end

  def test_optional_inputs
    job_id = "my-job-123"
    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
        "INPUT_TARGET" => "localdev",
        "INPUT_TARGET_URL" => "http://localhost/example",
      },
      job_ids: [job_id],
      status_responses: {
        job_id => ["complete"]
      },
    )

    assert_predicate job_status, :success?

    assert_equal 2, api_requests.length
    assert_predicate api_requests.first, :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "WestUs2",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
        "vscs_target" => "localdev",
        "vscs_target_url" => "http://localhost/example",
      },
      JSON.load(api_requests.first.body)
    )

    assert_predicate api_requests[1], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/#{job_id}",
      api_requests[1].path
    )
  end

  def test_multiple_locations
    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2 EastUs1",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      job_ids: ["west-job-id", "east-job-id"],
      status_responses: {
        "west-job-id" => ["complete"],
        "east-job-id" => ["complete"],
      },
    )

    assert_predicate job_status, :success?

    assert_equal 4, api_requests.length

    assert_predicate api_requests[0], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "WestUs2",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[0].body)
    )

    assert_predicate api_requests[1], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[1].path
    )

    assert_predicate api_requests[2], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "EastUs1",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[2].body)
    )

    assert_predicate api_requests[3], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[3].path
    )
  end

  def test_too_many_attempts
    job_id = "my-job-123"
    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
        "MAX_POLLING_ATTEMPTS" => "2",
      },
      job_ids: [job_id],
      status_responses: {
        job_id => ["pending", "pending", "pending"],
      },
    )

    refute_predicate job_status, :success?

    assert_equal 3, api_requests.length

    assert_predicate api_requests[0], :post?
    assert_predicate api_requests[1], :get?
    assert_predicate api_requests[2], :get?
  end

  def run_action(env:, job_ids:, status_responses:)
    status = nil
    api_requests = with_fake_api_server_running(job_ids, status_responses) do |fake_api_url|
      full_env = env.merge(
        "GITHUB_API_URL" => fake_api_url,
        "POLLING_DELAY" => "0",
      )
      output, error_output, status = Open3.capture3(
        full_env,
        File.expand_path("../../cache-codespace.sh", __FILE__),
      )

      if ENV["DEBUG"]
        puts "Standard output:\n#{output}\n"
        puts "Error output:\n#{error_output}\n"
      end
    end

    [status, api_requests]
  end

  def with_fake_api_server_running(job_ids, status_responses)
    port = 8888
    queue = Queue.new

    server_thread = Thread.new do
      FakeGitHubAPI.new(job_ids, status_responses, queue) do |app|
        webrick_options = {Port: port}

        unless ENV["DEBUG"]
          webrick_options.merge!(
            AccessLog: [],
            Logger: WEBrick::Log::new("/dev/null", 7),
          )
        end

        Rack::Handler::WEBrick.run(app, **webrick_options)
      end
    end

    server_thread.join(0.1)
    yield "http://127.0.0.1:#{port}"

    queue.close

    requests = []
    until queue.empty?
      requests << queue.pop
    end
    requests
  ensure
    server_thread.exit
    server_thread.join
  end
end

class FakeGitHubAPI < Sinatra::Base
  attr_reader :job_ids, :status_responses, :queue

  def initialize(job_ids, status_responses, queue)
    @job_ids = job_ids
    @status_responses = status_responses
    @queue = queue
    super nil
  end

  post "/vscs_internal/codespaces/repository/:username/:repo_name/prebuild/templates" do
    queue << request
    {
      job_status_id: job_ids.shift
    }.to_json
  end

  get "/vscs_internal/codespaces/repository/:username/:repo_name/prebuild_templates/provisioning_statuses/:job_id" do
    queue << request
    status = status_responses[params[:job_id]].shift
    {status: status}.to_json
  end
end
