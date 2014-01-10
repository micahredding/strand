require 'json'
require 'digest/sha1'
require 'camlistore'
require 'open3'
require 'faraday'
require 'faraday_middleware'

module JSON
  def self.is_json?(foo)
    begin
      return false unless foo.is_a?(String)
      JSON.parse(foo).all?
    rescue JSON::ParserError
      false
    end
  end
end

module Strand
  autoload :API,           './strand/api'
  autoload :Client,        './strand/client'

  def self.new *args
    Client.new *args
  end
end
