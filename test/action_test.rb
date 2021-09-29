require "minitest/autorun"

require "sinatra/base"
require "open3"
require "webrick"
require "pry"

# To run all tests:
# $ bundle exec m

# To run with debug info:
# $ DEBUG=true bundle exec m 

# To run one test:
# $ bundle exec m test/action_test.rb:19


class ActionTest < MiniTest::Test
  def test_immediate_polling_success
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id

    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "succeeded")]
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

  def test_immediate_polling_failure
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id

    job_status, api_requests = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "failed", message: "Error message")]
      },
    )

    refute job_status.success?

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

  def test_polling_failure_on_non_processing_status_return_message
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id

    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "other")]
      },
    )

    refute job_status.success?

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
    assert_includes error_output, "Something went wrong, please try again."
    refute_includes error_output, '\n'
  end

  def test_polling_failure_on_API_error
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id
    error_message = "Not Found"
    documentation_url = "http://api.fake.com"
    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [ErrorResponse.new(status: 404, message: error_message, documentation_url: documentation_url)]
      },
    )

    refute job_status.success?

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
    assert_includes error_output, error_message
    assert_includes error_output, documentation_url
  end

  def test_display_error_message_on_polling_failure
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id
    error_message = "Error message..."
    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "failed", message: error_message)]
      },
    )

    refute job_status.success?
    assert_equal 2, api_requests.length
    assert_includes error_output, error_message
  end

  def test_display_creation_logs_when_available_on_polling_failure
    job_id = "my-job-123"
    guid = "some-guid"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id

    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "failed", error_logs_available: true, guid: guid)]
      },
    )

    refute job_status.success?
    assert_equal 3, api_requests.length
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuilds/environments/#{guid}/logs",
      api_requests.last.path
      )

    assert_includes error_output, "Build log for #{guid}"
  end

  def test_display_blanket_error_message
    job_id = "my-job-123"
    guid = "some-guid"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id

    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "failed", error_logs_available: false, message: nil, guid: guid)]
      },
    )

    refute job_status.success?
    assert_equal 2, api_requests.length

    assert_includes error_output, "Something went wrong, please try again."
  end

  def test_polling_success
    job_id = "my-job-123"
    region = "WestUs2"
    sku_name = "futuristicQuantumComputer"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id, location: region, sku_name: sku_name
    job_status, api_requests, _, success_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => region,
        "INPUT_SKU_NAME" => sku_name,
      },
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "succeeded")
        ]
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
    assert_predicate api_requests[2], :get?
    assert_predicate api_requests[3], :get?

    assert_includes success_output, "Requesting new codespace(s) to be created & cached..."
    assert_includes success_output, "codespace caching in progress, this may take a while..."
    assert_includes success_output, "still in progress..."
    assert_includes success_output, "====== ACTION STATUS SUMMARY ======="
    assert_includes success_output, "job_id: my-job-123 | status: succeeded"
    assert_includes success_output, '{"job_status_id":"my-job-123","location":"WestUs2","sku_name":"futuristicQuantumComputer"}'
  end

  def test_optional_inputs
    job_id = "my-job-123"
    create_prebuild_template_response = CreatePrebuildTemplateResponse.new job_status_id: job_id
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
      create_prebuild_template_responses: [create_prebuild_template_response],
      status_responses: {
        job_id => [StatusResponse.new(state: "succeeded")]
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

  def test_multiple_locations_all_succeed
    create_prebuild_template_responses = [
      CreatePrebuildTemplateResponse.new(job_status_id: "west-job-id", sku_name: "futuristicQuantumComputer", location: "WestUs2"),
      CreatePrebuildTemplateResponse.new(job_status_id: "east-job-id",sku_name: "futuristicQuantumComputer", location: "EastUs1"),
    ]
    job_status, api_requests, _, success_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2 EastUs1",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: create_prebuild_template_responses,
      status_responses: {
        "west-job-id" => [StatusResponse.new(state: "succeeded")],
        "east-job-id" => [StatusResponse.new(state: "succeeded")]
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

    assert_predicate api_requests[1], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "EastUs1",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[1].body)
    )

    assert_predicate api_requests[2], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[2].path
    )

    assert_predicate api_requests[3], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[3].path
    )

    assert_includes success_output, 'job_id: east-job-id | status: succeeded | job: {"job_status_id":"east-job-id","location":"EastUs1","sku_name":"futuristicQuantumComputer"}'
    assert_includes success_output, 'job_id: west-job-id | status: succeeded | job: {"job_status_id":"west-job-id","location":"WestUs2","sku_name":"futuristicQuantumComputer"}'
  end

  def test_multiple_locations_all_fail
    create_prebuild_template_responses = [
      CreatePrebuildTemplateResponse.new(job_status_id: "west-job-id", sku_name: "futuristicQuantumComputer", location: "WestUs2"),
      CreatePrebuildTemplateResponse.new(job_status_id: "east-job-id",sku_name: "futuristicQuantumComputer", location: "EastUs1"),
    ]
    job_status, api_requests, _, success_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2 EastUs1",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: create_prebuild_template_responses,
      status_responses: {
        "west-job-id" => [StatusResponse.new(state: "failed")],
        "east-job-id" => [StatusResponse.new(state: "failed")]
      },
    )

    refute_predicate job_status, :success?

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

    assert_predicate api_requests[1], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "EastUs1",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[1].body)
    )

    assert_predicate api_requests[2], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[2].path
    )

    assert_predicate api_requests[3], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[3].path
    )

    assert_includes success_output, 'job_id: east-job-id | status: failed | job: {"job_status_id":"east-job-id","location":"EastUs1","sku_name":"futuristicQuantumComputer"}'
    assert_includes success_output, 'job_id: west-job-id | status: failed | job: {"job_status_id":"west-job-id","location":"WestUs2","sku_name":"futuristicQuantumComputer"}'
  end

  def test_multiple_locations_one_fails
    create_prebuild_template_responses = [
      CreatePrebuildTemplateResponse.new(job_status_id: "west-job-id", sku_name: "futuristicQuantumComputer", location: "WestUs2"),
      CreatePrebuildTemplateResponse.new(job_status_id: "east-job-id",sku_name: "futuristicQuantumComputer", location: "EastUs1"),
    ]
    job_status, api_requests, _, success_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2 EastUs1",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: create_prebuild_template_responses,
      status_responses: {
        "west-job-id" => [StatusResponse.new(state: "succeeded")],
        "east-job-id" => [StatusResponse.new(state: "failed")]
      },
    )

    refute_predicate job_status, :success?

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

    assert_predicate api_requests[1], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "EastUs1",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[1].body)
    )

    assert_predicate api_requests[2], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[2].path
    )

    assert_predicate api_requests[3], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[3].path
    )

    assert_includes success_output, 'job_id: east-job-id | status: failed | job: {"job_status_id":"east-job-id","location":"EastUs1","sku_name":"futuristicQuantumComputer"}'
    assert_includes success_output, 'job_id: west-job-id | status: succeeded | job: {"job_status_id":"west-job-id","location":"WestUs2","sku_name":"futuristicQuantumComputer"}'
  end

  def test_multiple_locations_keeps_polling_until_all_are_done
    create_prebuild_template_responses = [
      CreatePrebuildTemplateResponse.new(job_status_id: "west-job-id", sku_name: "futuristicQuantumComputer", location: "WestUs2"),
      CreatePrebuildTemplateResponse.new(job_status_id: "east-job-id",sku_name: "futuristicQuantumComputer", location: "EastUs1"),
    ]
    job_status, api_requests, _, success_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2 EastUs1",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      create_prebuild_template_responses: create_prebuild_template_responses,
      status_responses: {
        "west-job-id" => [
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "succeeded")
        ],
        "east-job-id" => [
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "processing"),
          StatusResponse.new(state: "succeeded")]
      },
    )

    assert_predicate job_status, :success?

    assert_equal 9, api_requests.length

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

    assert_predicate api_requests[1], :post?
    assert_equal(
      {
        "ref" => "main",
        "location" => "EastUs1",
        "sku_name" => "futuristicQuantumComputer",
        "sha" => "abcdef1234567890",
      },
      JSON.load(api_requests[1].body)
    )

    assert_predicate api_requests[2], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[2].path
    )

    assert_predicate api_requests[3], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[3].path
    )

    assert_predicate api_requests[4], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/west-job-id",
      api_requests[4].path
    )

    assert_predicate api_requests[5], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[5].path
    )

    assert_predicate api_requests[6], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[6].path
    )

    assert_predicate api_requests[7], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[7].path
    )

    assert_predicate api_requests[8], :get?
    assert_equal(
      "/vscs_internal/codespaces/repository/monalisa/smile/prebuild_templates/provisioning_statuses/east-job-id",
      api_requests[8].path
    )

    assert_predicate api_requests[9], :nil?

    assert_includes success_output, 'job_id: east-job-id | status: succeeded | job: {"job_status_id":"east-job-id","location":"EastUs1","sku_name":"futuristicQuantumComputer"}'
    assert_includes success_output, 'job_id: west-job-id | status: succeeded | job: {"job_status_id":"west-job-id","location":"WestUs2","sku_name":"futuristicQuantumComputer"}'
  end

  def test_immediate_creation_failure
    job_id = "my-job-123"
    error_message = 'The codespaces secret must be set.'
    documentation_url = "http://fake.api.com"
    create_prebuild_template_response = ErrorResponse.new(
      status: 404,
      message: error_message,
      documentation_url: documentation_url
    )

    job_status, api_requests, error_output = run_action(
      env: {
        "GITHUB_REF" => "main",
        "GITHUB_REPOSITORY" => "monalisa/smile",
        "GITHUB_SHA" => "abcdef1234567890",
        "GITHUB_TOKEN" => "my-very-secret-token",
        "INPUT_REGIONS" => "WestUs2",
        "INPUT_SKU_NAME" => "futuristicQuantumComputer",
      },
      status_responses: {},
      create_prebuild_template_responses: [create_prebuild_template_response],
    )

    refute_predicate job_status, :success?

    assert_includes error_output, error_message
    assert_includes error_output, documentation_url
  end

  def run_action(env:, create_prebuild_template_responses:, status_responses:)
    status = nil
    error_output = nil
    output = nil
    api_requests = with_fake_api_server_running(create_prebuild_template_responses, status_responses) do |fake_api_url|
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
    [status, api_requests, error_output, output]
  end

  def with_fake_api_server_running(create_prebuild_template_responses, status_responses)
    port = 8888
    queue = Queue.new

    server_thread = Thread.new do
      FakeGitHubAPI.new(create_prebuild_template_responses, status_responses, queue) do |app|
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
  attr_reader :create_prebuild_template_responses, :status_responses, :queue

  def initialize(create_prebuild_template_responses, status_responses, queue)
    @create_prebuild_template_responses = create_prebuild_template_responses
    @status_responses = status_responses
    @queue = queue
    super nil
  end

  post "/vscs_internal/codespaces/repository/:username/:repo_name/prebuild/templates" do
    queue << request
    response = create_prebuild_template_responses.shift
    status response.status
    body response.body
  end

  get "/vscs_internal/codespaces/repository/:username/:repo_name/prebuild_templates/provisioning_statuses/:job_id" do
    queue << request
    job_id_response = status_responses[params[:job_id]]
    if job_id_response
      response = job_id_response.shift
      status response.status
      body response.body
    else
      status 404
      body "Job ID not found"
    end
  end

  get "/vscs_internal/codespaces/repository/:username/:repo_name/prebuilds/environments/:guid/logs" do
    queue << request
    status 200
    body "Build log for #{params[:guid]}"
  end
end

class CreatePrebuildTemplateResponse
  attr_reader :job_status_id, :location, :sku_name

  def initialize(job_status_id:, location: nil, sku_name: nil)
    @job_status_id = job_status_id
    @location = location
    @sku_name = sku_name
  end

  def body
    response = {job_status_id: job_status_id}
    response[:location] = location if location
    response[:sku_name] = sku_name if sku_name
    response.to_json
  end

  def status
    200
  end
end

class StatusResponse

  attr_reader :state, :message, :error_logs_available, :guid

  def initialize(state:, message: nil, error_logs_available: false, guid: "guid")
    @state = state
    @message = message
    @error_logs_available = error_logs_available
    @guid = guid
  end

  def body
    {state: state, message: message, error_logs_available: error_logs_available, guid: guid}.to_json
  end

  def status
    200
  end
end

class ErrorResponse
  attr_reader :status, :message, :documentation_url

  def initialize(message:, status:, documentation_url: nil)
    @message = message
    @status = status
    @documentation_url = documentation_url
  end

  def body
    {message: message, documentation_url: documentation_url}.to_json
  end

end