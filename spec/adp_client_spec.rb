# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'adp_client'
require 'webmock/rspec'
require_relative 'shared_contexts'

RSpec.describe AdpClient do
  let(:base_url) { 'https://iat-api.adp.com' }
  let(:client_id) { SecureRandom.uuid }
  let(:client_secret) { SecureRandom.uuid }
  let(:instance) do
    # These details don't really matter as we're going to mock the responses.
    AdpClient.new(
      base_url: base_url,
      client_id: client_id,
      client_secret: client_secret,
      logger: spy,
      pem: File.read("#{File.dirname(__FILE__)}/adp_api_iat.pem")
    )
  end

  describe '#token' do
    subject { instance.token }

    context 'when the details are valid' do
      let(:access_token) { SecureRandom.uuid }
      let(:response) do
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
          .with(
            body: URI.encode_www_form(
              client_id: client_id,
              client_secret: client_secret,
              grant_type: 'client_credentials'
            )
          )
          .to_return(response)
      end

      it 'returns a token' do
        expect(subject).to be_a AdpClient::Token
        expect(subject.access_token).to eq access_token
        expect(subject.expires_in).to eq 3600
        expect(subject.token_type).to eq 'Bearer'
        expect(subject.scope).to eq 'api'
      end
    end

    context 'when the client id is not valid' do
      # The actual client_id and client_secret value are irrelevant since
      # we're mocking the response...
      let(:response) do
        {
          status: 401,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: {
            error: 'invalid_client',
            error_description: 'The given client credentials were not valid'
          }.to_json
        }
      end

      before do
        stub_request(:post, "#{base_url}/auth/oauth/v2/token")
          .with(
            body: URI.encode_www_form(
              client_id: client_id,
              client_secret: client_secret,
              grant_type: 'client_credentials'
            )
          )
          .to_return(response)
      end

      it 'fails with AdpClient::Unauthorized' do
        expect { subject }
          .to raise_error(
            AdpClient::Unauthorized,
            'invalid_client: The given client credentials were not valid'
          )
      end
    end

    context 'when the certificate is not valid' do
      let(:response) do
        {
          status: 401,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: {
            error: 'invalid_request',
            error_description: 'proper client ssl certificate was not presented'
          }.to_json
        }
      end

      before do
        stub_request(:post, "#{base_url}/auth/oauth/v2/token")
          .with(
            body: URI.encode_www_form(
              client_id: client_id,
              client_secret: client_secret,
              grant_type: 'client_credentials'
            )
          )
          .to_return(response)
      end

      it 'fails with AdpClient::Unauthorized' do
        expect { subject }
          .to raise_error(
            AdpClient::Unauthorized,
            'invalid_request: proper client ssl certificate was not presented'
          )
      end
    end
  end

  describe '#get' do
    subject do
      instance.get(event_path)
    end

    let(:event_id) { SecureRandom.uuid }
    let(:event_path) do
      "events/time/v1/data-collection-entries.process/#{event_id}"
    end

    context 'when the resource exists' do
      include_context 'valid token request'

      let(:response) do
        {
          status: 200,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: response_hash.to_json
        }
      end
      let(:response_hash) do
        {
          confirmMessage: {
            createDateTime: Time.new.iso8601,
            protocolStatusCode: { codeValue: '200' },
            protocolCode: { codeValue: 'http' },
            requestStatusCode: { codeValue: 'succeeded' },
            requestMethodCode: { codeValue: 'GET' },
            resourceMessages: [
              {
                resourceMessageID: { idValue: event_id },
                resourceStatusCode: { codeValue: 'succeeded' },
                resourceLink: {
                  rel: 'alternate',
                  href: "/#{event_path}",
                  method: 'GET',
                  mediaType: 'application/json',
                  encType: 'UTF-8'
                }
              }
            ]
          }
        }
      end

      before do
        stub_request(:get, "#{base_url}/#{event_path}").to_return(response)
      end

      it 'returns the resource' do
        expect(
          JSON.parse(subject.to_json, symbolize_names: true)
        ).to eq response_hash
      end
    end

    context 'when the resource does not exist' do
      include_context 'valid token request'

      let(:response) do
        {
          status: 404,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: {
            confirmMessage: {
              createDateTime: Time.new.iso8601,
              protocolStatusCode: { codeValue: '404' },
              protocolCode: { codeValue: 'http' },
              requestStatusCode: { codeValue: 'succeeded' },
              requestMethodCode: { codeValue: 'GET' },
              processMessages: [
                {
                  processMessageID: { idValue: '1' },
                  messageTypeCode: { codeValue: 'warning' },
                  userMessage: {
                    codeValue: '404',
                    title: 'Bulk Punch Upload',
                    messageTxt: 'Requested eventid not found'
                  }
                }
              ],
              resourceMessages: [
                {
                  resourceMessageID: { idValue: event_id },
                  resourceStatusCode: { codeValue: 'warning' },
                  resourceLink: {
                    rel: 'alternate',
                    href: "/#{event_path}",
                    method: 'GET',
                    mediaType: 'application/json',
                    encType: 'UTF-8'
                  }
                }
              ]
            }
          }.to_json
        }
      end

      before do
        stub_request(:get, "#{base_url}/#{event_path}").to_return(response)
      end

      it 'fails with AdpClient::ResourceNotFound' do
        expect { subject }
          .to raise_error(
            AdpClient::ResourceNotFound,
            'Requested eventid not found'
          )
      end
    end

    context 'when the access token is not valid' do
      include_context 'valid token request'

      let(:response) do
        {
          status: 400,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: {
            error: 'invalid_request',
            error_description: 'Validation error'
          }.to_json
        }
      end

      before do
        stub_request(:get, "#{base_url}/#{event_path}").to_return(response)
      end

      it 'fails with AdpClient::InvalidRequest' do
        expect { subject }
          .to raise_error(
            AdpClient::InvalidRequest,
            'invalid_request: Validation error'
          )
      end
    end
  end

  describe '#post' do
    subject do
      instance.post(
        resource_path,
        payload
      )
    end

    context 'when the payload is valid' do
      include_context 'valid token request'

      let(:event_id) { SecureRandom.uuid }
      let(:payload) do
        {
          events: [
            {
              serviceCategoryCode: { codeValue: 'core' },
              data: {
                transform: {
                  dataCollectionEntries: [
                    {
                      itemID: 0,
                      terminalName: payload_time_clock_id,
                      workerDataCollectionEntries: [
                        {
                          entryID: 0,
                          entryCode: { codeValue: '' },
                          badgeID: payload_associate_id,
                          deviceDateTime: Time.now.iso8601,
                          entryDateTime: payload_punch_time,
                          actionCode: { codeValue: payload_punch_type }
                        }
                      ]
                    }
                  ]
                }
              }
            }
          ]
        }
      end
      let(:payload_time_clock_id) { 'RSPEC' }
      let(:payload_associate_id) { SecureRandom.urlsafe_base64(9) }
      let(:payload_punch_time) { Time.now.iso8601 }
      let(:payload_punch_type) { 'clockin' }
      let(:resource_path) { 'events/time/v1/data-collection-entries.process' }
      let(:response) do
        {
          status: 200,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: response_hash.to_json
        }
      end
      let(:response_hash) do
        time = Time.now.iso8601

        {
          events: [
            {
              eventID: event_id,
              serviceCategoryCode: { codeValue: 'time' },
              eventNameCode: {
                codeValue: "/#{resource_path}"
              },
              eventTitle: 'Data Collection Entries Process',
              eventStatusCode: { codeValue: 'complete' },
              recordDateTime: time,
              creationDateTime: time,
              effectiveDateTime: time
            }
          ],
          confirmMessage: {
            createDateTime: Time.new.iso8601,
            protocolStatusCode: { codeValue: '202' },
            protocolCode: { codeValue: 'http' },
            requestStatusCode: { codeValue: 'succeeded' },
            requestMethodCode: { codeValue: 'POST' },
            resourceMessages: [
              {
                resourceMessageID: { idValue: event_id },
                resourceStatusCode: { codeValue: 'succeeded' },
                resourceLink: {
                  rel: 'alternate',
                  href: "/#{resource_path}/#{event_id}",
                  method: 'GET',
                  mediaType: 'application/json',
                  encType: 'UTF-8'
                }
              }
            ]
          }
        }
      end

      before do
        stub_request(:post, "#{base_url}/#{resource_path}")
          .with(body: payload.to_json)
          .to_return(response)
      end

      it 'returns a response' do
        expect(
          JSON.parse(subject.to_json, symbolize_names: true)
        ).to eq response_hash
      end
    end

    # This is a simple failure, we should probably handle different types
    # of payload failures later on.
    context 'when the payload is not valid' do
      include_context 'valid token request'

      let(:payload) { {} }
      let(:resource_path) { 'events/time/v1/data-collection-entries.process' }
      let(:response) do
        {
          status: 500,
          headers: {
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
            'Host' => URI.parse(base_url).host
          },
          body: response_hash.to_json
        }
      end
      let(:response_hash) do
        time = Time.new.iso8601
        {
          confirmMessage: {
            confirmMessageID: {
              idValue: '12312321',
              schemeName: 'confirmMessageID',
              schemeAgencyName: 'APIMP'
            },
            createDateTime: time,
            requestReceiptDateTime: time,
            protocolStatusCode: { codeValue: '500' },
            protocolCode: { codeValue: 'http' },
            requestStatusCode: { codeValue: 'failed' },
            requestMethodCode: { codeValue: 'POST' },
            sessionID: {
              idValue: 'h/hkIrxExG/f0EJExVEtpQc7L64=',
              schemeName: 'sessionID',
              schemeAgencyName: 'APIMP'
            },
            requestETag: 'A1231234324',
            resourceMessages: [
              {
                processMessages: [
                  {
                    messageTypeCode: { codeValue: 'error' },
                    userMessage: {
                      messageTxt: 'Unsupported Layer Action'
                    },
                    developerMessage: { codeValue: 'invalid json' }
                  }
                ]
              }
            ]
          }
        }
      end

      before do
        stub_request(:post, "#{base_url}/#{resource_path}")
          .with(body: payload.to_json)
          .to_return(response)
      end

      it 'fails with AdpClient::Error' do
        expect { subject }
          .to raise_error do |error|
            expect(error).to be_a AdpClient::Error
            expect(error.message).to eq 'Unsupported Layer Action'
            expect(
              JSON.parse(error.data.to_json, symbolize_names: true)
            ).to eq response_hash
          end
      end
    end
  end
end
