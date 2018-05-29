# frozen_string_literal: true
# $LOAD_PATH.unshift File.dirname(__FILE__)

require 'adp_client/version'
require 'httparty'
require 'logger'

##
# Basic ADP Api Client
# Basic Api client that uses client credentials for authentication. The PEM
# certificate details must contain include the private key appended.
#
# @example
#
#   client = AdpClient.new(
#     client_id: ENV['ADP_CLIENT_ID'],
#     client_secret: ENV['ADP_CLIENT_SECRET'],
#     base_ur: ENV['ADP_API_HOST'],
#     pem: File.read(ENV['ADP_SSL_CERT_PATH'])
#   )
#
class AdpClient
  class << self
    attr_accessor :base_url,
                  :client_id,
                  :client_secret,
                  :logger,
                  :pem

    ##
    # Configures default AdpClient settings.
    #
    # @example configuring the client defaults
    #   AdpClient.configure do |config|
    #     config.base_url = 'https://api.adp.com'
    #     config.client_id = 'client_id'
    #     config.client_secret = 'client_secret'
    #     config.pem = '{cert and key data}'
    #     config.logger = Logger.new(STDOUT)
    #   end
    #
    # @example using the client
    #   client = AdpClient.new
    def configure
      yield self
      true
    end
  end

  class Error < StandardError
    attr_reader :data

    def initialize(message, data = nil)
      @data = data

      super(message)
    end
  end
  class BadRequest < Error; end
  class InvalidRequest < StandardError; end
  class ResourceNotFound < StandardError; end
  class Unauthorized < StandardError; end
  Token = Struct.new(:access_token, :token_type, :expires_in, :scope)

  def initialize(options = {})
    options = default_options.merge(options)

    @client_id = options[:client_id]
    @client_secret = options[:client_secret]
    @base_url = options[:base_url]
    @options = { pem: options[:pem] }
    @logger = options.fetch(:logger, Logger.new(STDOUT))
  end

  ##
  # Default options
  # A {Hash} of default options populate by attributes set during configuration.
  #
  # @return [Hash] containing the default options
  def default_options
    {
      base_url: AdpClient.base_url,
      client_id: AdpClient.client_id,
      client_secret: AdpClient.client_secret,
      logger: AdpClient.logger,
      pem: AdpClient.pem
    }
  end

  ##
  # OAuth token
  # Performs authentication using client credentials against the ADP Api.
  #
  # @return [Token] token details
  def token
    return @token if @token

    options = @options.merge(
      body: {
        client_id: @client_id,
        client_secret: @client_secret,
        grant_type: 'client_credentials'
      },
      headers: {
        'Accept' => 'application/json',
        'Host' => uri.host
      }
    )
    url = "#{@base_url}/auth/oauth/v2/token"

    @logger.debug("Request token from #{url}")

    response = raises_unless_success do
      HTTParty.post(url, options)
    end.parsed_response

    @token = Token.new(
      *response.values_at('access_token', 'token_type', 'expires_in', 'scope')
    )
  end

  ##
  # Get a resource
  # Makes a request for a resource from ADP and returns the response as a
  # raw {Hash}.
  #
  # @param [String] the resource endpoint
  # @return [Hash] response data
  def get(resource)
    url = "#{@base_url}/#{resource}"

    @logger.debug("GET request Url: #{url}")
    @logger.debug("-- Headers: #{base_headers}")

    raises_unless_success do
      HTTParty
        .get(url, headers: base_headers)
    end.parsed_response
  end

  ##
  # Post a resource
  # Makes a request to post new resource details to ADP amd returns the
  # response as a raw {Hash}.
  #
  # @param [String] the resource endpoint
  # @param [Hash] the resource data
  # @return [Hash] response data
  def post(resource, data)
    headers = base_headers
              .merge('Content-Type' => 'application/json')
    url = "#{@base_url}/#{resource}"

    @logger.debug("POST request Url: #{url}")
    @logger.debug("-- Headers: #{headers}")
    @logger.debug("-- JSON #{data.to_json}")

    raises_unless_success do
      HTTParty
        .post(url, body: data.to_json, headers: headers)
    end.parsed_response
  end

  protected

  def base_headers
    {
      'Accept' => 'application/json',
      'Authorization' => "Bearer #{token.access_token}",
      'Connection' => 'Keep-Alive',
      'Host' => uri.host,
      'User-Agent' => 'AdpClient'
    }
  end

  def raises_unless_success
    httparty = yield

    [
      ErrorHandler,
      InvalidRequestHandler,
      ResourceNotFoundHandler,
      UnauthorizedHandler,
      BadRequestHandler,
      UnknownErrorHandler
    ].each do |response_handler_type|
      response_handler_type.new(httparty).call
    end

    httparty
  end

  class BaseErrorHandler
    def initialize(httparty)
      @httparty = httparty
    end

    def call
      fail error if fail?
    end
  end

  class ErrorHandler < BaseErrorHandler
    def error
      Error.new(
        @httparty
          .parsed_response
          .fetch('confirmMessage', {})
          .fetch('resourceMessages', [{}])[0]
          .fetch('processMessages', [{}])[0]
          .fetch('userMessage', {})
          .fetch('messageTxt', 'No userMessage messageTxt found'),
        @httparty.parsed_response
      )
    end

    def fail?
      @httparty.code == 500
    end
  end

  class BadRequestHandler < BaseErrorHandler
    def error
      BadRequest.new('Looks like a Bad Request', @httparty.parsed_response)
    end

    def fail?
      @httparty.parsed_response['error'].nil? && @httparty.code == 400
    end
  end

  class InvalidRequestHandler < BaseErrorHandler
    def error
      InvalidRequest.new(
        format('%<error>s: %<description>s',
               error: @httparty.parsed_response['error'],
               description: @httparty.parsed_response['error_description'])
      )
    end

    def fail?
      @httparty.parsed_response['error'] == 'invalid_request' &&
        @httparty.code == 400
    end
  end

  class ResourceNotFoundHandler < BaseErrorHandler
    def error
      ResourceNotFound.new(
        @httparty
          .parsed_response
          .fetch('confirmMessage', {})
          .fetch('processMessages', [{}])
          .first
          .fetch('userMessage', {})
          .fetch('messageTxt', 'No userMessage messageTxt found')
      )
    end

    def fail?
      @httparty.code == 404
    end
  end

  class UnauthorizedHandler < BaseErrorHandler
    def error
      Unauthorized.new(
        format('%<error>s: %<description>s',
               error: @httparty.parsed_response['error'],
               description: @httparty.parsed_response['error_description'])
      )
    end

    def fail?
      @httparty.code == 401
    end
  end

  class UnknownErrorHandler < BaseErrorHandler
    def error
      HTTParty::Error.new("Code #{@httparty.code} - #{@httparty.body}")
    end

    def fail?
      !@httparty.response.is_a?(Net::HTTPSuccess)
    end
  end

  def uri
    @uri ||= URI.parse(@base_url)
  end
end
