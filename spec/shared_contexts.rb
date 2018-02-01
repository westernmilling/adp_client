# frozen_string_literal: true

RSpec.shared_context 'valid token request' do
  let(:access_token) { SecureRandom.uuid }
  let(:token_response) do
    {
      status: 200,
      headers: {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'Host' => URI.parse(base_url).host
      },
      body: {
        access_token: access_token,
        token_type: 'Bearer',
        expires_in: 3600,
        scope: 'api'
      }.to_json
    }
  end

  before do
    stub_request(:post, "#{base_url}/auth/oauth/v2/token")
      .to_return(token_response)
  end
end
