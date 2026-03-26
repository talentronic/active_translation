require "test_helper"

class ActiveTranslationTest < ActiveSupport::TestCase
  setup do
    stubs
  end

  test "it has a version number" do
    assert ActiveTranslation::VERSION
  end

  test "non-mock environments can be configured" do
    assert ActiveTranslation.configuration.non_mock_environments

    ActiveTranslation.configuration.non_mock_environments = [ :production, :staging ]

    assert_equal [ :production, :staging ], ActiveTranslation.configuration.non_mock_environments

    assert ActiveTranslation::GoogleTranslate.mock_api_responses?
  end

  test "invalid non-mock environment configurations set only production to non-mock" do
    ActiveTranslation.configuration.non_mock_environments = nil

    assert ActiveTranslation::GoogleTranslate.mock_api_responses?

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not ActiveTranslation::GoogleTranslate.mock_api_responses?
    end

    ActiveTranslation.configuration.non_mock_environments = true

    assert ActiveTranslation::GoogleTranslate.mock_api_responses?

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not ActiveTranslation::GoogleTranslate.mock_api_responses?
    end

    ActiveTranslation.configuration.non_mock_environments = false

    assert ActiveTranslation::GoogleTranslate.mock_api_responses?

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not ActiveTranslation::GoogleTranslate.mock_api_responses?
    end

    ActiveTranslation.configuration.non_mock_environments = TrueClass

    assert ActiveTranslation::GoogleTranslate.mock_api_responses?

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_not ActiveTranslation::GoogleTranslate.mock_api_responses?
    end
  end

  test "maintain_initial_capital maintains initial capital" do
    ActiveTranslation.configuration.non_mock_environments = [ :test ]

    translated_text = ActiveTranslation::GoogleTranslate.translate(
      target_language_code: :fr,
      text: "gardener",
    )

    assert_equal "jardinier", translated_text

    translated_text = ActiveTranslation::GoogleTranslate.translate(
      target_language_code: :fr,
      text: "Gardener",
    )

    assert_equal "Jardinier", translated_text

    ActiveTranslation.configuration.non_mock_environments = [ :production ]
  end

  test "real requests are only made in non-mock environments" do
    ActiveTranslation.configuration.non_mock_environments = [ :production, :staging ]

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ActiveTranslation::GoogleTranslate.translate(
        target_language_code: :fr,
        text: "gardener",
      )

      assert_requested @token_stub
      assert_requested @translate_stub
    end

    WebMock::RequestRegistry.instance.reset!

    Rails.stub(:env, ActiveSupport::StringInquirer.new("staging")) do
      ActiveTranslation::GoogleTranslate.translate(
        target_language_code: :fr,
        text: "gardener",
      )

      assert_requested @token_stub
      assert_requested @translate_stub
    end

    WebMock::RequestRegistry.instance.reset!

    Rails.stub(:env, ActiveSupport::StringInquirer.new("demo")) do
      ActiveTranslation::GoogleTranslate.translate(
        target_language_code: :fr,
        text: "gardener",
      )

      assert_not_requested @token_stub
      assert_not_requested @translate_stub
    end

    WebMock::RequestRegistry.instance.reset!

    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      ActiveTranslation::GoogleTranslate.translate(
        target_language_code: :fr,
        text: "gardener",
      )

      assert_not_requested @token_stub
      assert_not_requested @translate_stub
    end
  end

  private

  def stubs
    @token_stub = stub_request(:post, "https://www.googleapis.com/oauth2/v4/token").to_return(
      status: 200,
      body: '{"access_token": "fake_access_token", "token_type": "Bearer", "expires_in": 3600}',
      headers: {
        "Content-Type" => "application/json",
      },
    )

    @translate_stub = stub_request(:post, "https://translation.googleapis.com/language/translate/v2").to_return(
      status: 200,
      body: {
        data: {
          translations: [
            translatedText: "jardinier"
          ],
        },
      }.to_json,
      headers: {
        "Content-Type" => "application/json",
      }
    )
  end
end
