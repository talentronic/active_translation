module ActiveTranslation
  class Configuration
    attr_accessor :type,
      :project_id,
      :private_key_id,
      :private_key,
      :client_email,
      :client_id,
      :auth_uri,
      :token_uri,
      :auth_provider_x509_cert_url,
      :client_x509_cert_url,
      :universe_domain,
      :non_mock_environments

    def initialize
      @type = nil
      @project_id = nil
      @private_key_id = nil
      @private_key = nil
      @client_email = nil
      @client_id = nil
      @auth_uri = "https://accounts.google.com/o/oauth2/auth"
      @token_uri = "https://oauth2.googleapis.com/token"
      @auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
      @client_x509_cert_url = nil
      @universe_domain = "googleapis.com"
      @non_mock_environments = [ :production ]
    end
  end
end
