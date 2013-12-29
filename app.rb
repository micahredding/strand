require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'camlistore'
require 'open3'
require 'rest_client'
require 'net/http'
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

class Blobserver
	@@camli = Camlistore.new
	@@connection = Faraday.new
	@@root_url = 'http://localhost:3179'

	# http://godoc.org/camlistore.org/pkg/search#SortType
  UnspecifiedSort   = 0
  LastModifiedDesc  = 1
  LastModifiedAsc   = 2
  CreatedDesc       = 3
  CreatedAsc        = 4

	def Blobserver.init
		response = Faraday.get @@root_url, {}, :accept => 'text/x-camli-configuration'
		if response.status == 200
			if JSON.is_json?(response.body)
				info = JSON.parse(response.body)
				@@search_root = info['searchRoot']
				@@blob_root = info['blobRoot']
			end
		end
	end

	def Blobserver.blobref blobcontent
		'sha1-' + Digest::SHA1.hexdigest(blobcontent)
	end

	def Blobserver.get blobref
		return nil if blobref.nil?
	  @@camli.get(blobref)
	end

	def Blobserver.enumerate
		@@camli.enumerate_blobs.blobs
	end

	def Blobserver.create_permanode
		`./camput permanode`
	end

	def Blobserver.update_permanode blobref, attribute, value
		blobref.delete!("\n")
		attribute.delete!("\n")
		value.delete!("\n")
		`./camput attr #{blobref} #{attribute} '#{value}'`
	end

	def Blobserver.put blobcontent
		output = nil
		cmd = "./camput blob - "
		Open3.popen3(cmd) do |stdin, stdout, stderr|
			stdin.puts blobcontent
			stdin.close
			stdout.each_line do |line|
				output = line
			end
		end
		output
	end

	def Blobserver.describe blobref
	  url = @@root_url + @@search_root + 'camli/search/describe'
	  results = Blobserver.http_get(url, {'blobref' => blobref})
	  if results.nil? || results['meta'].nil? || results['meta'][blobref].nil? then return {} end
	  results['meta'][blobref]
	end

	def Blobserver.search query
		url = @@root_url + @@search_root + 'camli/search/query'
		results = Blobserver.http_post(url, query)
	  if results.nil? || results['blobs'].nil? then return [] end
	  results['blobs']
	end

	def Blobserver.enumerate_type type
		Blobserver.search({"constraint" => {"camliType" => type}})
	end

	def Blobserver.find_permanode_by attribute, value
		Blobserver.search({
			"constraint" => {
				"camliType" => "permanode",
				"permanode" => {
					"attr" => attribute,
					"value" => value
				}
			}
		})
	end

	# @begin http
	def Blobserver.http_get url, parameters
		response = Faraday.get url, parameters
		if response.status == 200
			if JSON.is_json?(response.body)
				JSON.parse(response.body)
			end
		end
	end

	def Blobserver.http_post url, query
		query = query.to_json if query.is_a?(Hash)
		response = Faraday.post url, query
		if response.status == 200
			if JSON.is_json?(response.body)
				JSON.parse(response.body)
			end
		end
	end
	# @end http

	Blobserver.init
end

class Blob
	@@camliType = nil
	def initialize blobref, blobcontent=nil
		@blobref = blobref
		@blobcontent = blobcontent
	end
	def blobref
		@blobref
	end
	def blobcontent
		if @blobcontent.nil?
			@blobcontent = Blobserver.get(blobref)
		end
		@blobcontent
	end
	def valid?
		true
	end
	def self.get blobref
		self.new(blobref, Blobserver.get(blobref))
	end
	def self.put blobcontent
		self.new(Blobserver.put(blobcontent), blobcontent)
	end
	def self.enumerate
		Blobserver.enumerate.collect! do |blob|
			self.new(blob['blobRef'])
		end
	end
	def self.enumerate_type
		Blobserver.enumerate_type(@@camliType).collect! do |blob|
			self.new(blob['blob'])
		end
	end
end

class SchemaBlob < Blob
	@@camliType = nil
	def blobhash
		if @blobhash.nil?
			if JSON.is_json?(blobcontent)
				@blobhash = JSON.parse(blobcontent)
			else
				@blobhash = {}
			end
		end
		@blobhash
	end
	def valid?
		JSON.is_json?(blobcontent)
	end
	def self.enumerate
		super.select do |blob|
			blob.valid?
		end
	end
	def self.find_by field, value
		self.enumerate.select do |blob|
			blob.blobhash[field] == value
		end
	end
end

class Claim < SchemaBlob
	@@camliType = 'claim'
	def type() blobhash['claimType'] end
	def attribute() blobhash['attribute'] end
	def value()	blobhash['value'] end
	def time() DateTime.parse(blobhash['claimDate']).to_time end
	def time_formatted(format="%B %d, %Y %I:%M%p") time().strftime(format) end
	def valid?
		super && blobhash['camliType'] == 'claim'
	end
	def self.find_by_permanode permanode_ref
		self.find_by('permaNode', permanode_ref)
	end
end

class Permanode < SchemaBlob
	@@camliType = 'permanode'
	def self.create
		self.new(Blobserver.create_permanode)
	end
	def valid?
		super && blobhash['camliType'] == 'permanode'
	end
	def claims
		if @claims.nil?
			@claims = Claim.find_by_permanode(blobref) || []
		end
		@claims
	end
	def set_attribute attribute, value
		Blobserver.update_permanode blobref, attribute, value
	end
	def get_attribute attribute
		@description = Blobserver.describe(@blobref)
		return nil if @description.nil? || @description['permanode'].nil? || @description['permanode']['attr'].nil? || @description['permanode']['attr'][attribute].nil? || @description['permanode']['attr'][attribute].first.nil?
		@description['permanode']['attr'][attribute].first
	end
end

class Node < Permanode
	def set_title title
		set_attribute 'title', title
	end
	def set_content content
		blobcontent = content.to_json
		blobref = Blobserver.put(blobcontent)
		set_attribute 'camliContent', blobref
	end
	def time
		if claims.length > 0
			claims.last.time
		else
			Time.new
		end
	end
	def time_formatted format="%B %d, %Y %I:%M%p"
		time.strftime(format)
	end
	def title
		get_attribute('title')
	end
	def body
		content['body'] || content
	end
	def content
		@content = SchemaBlob.new(camliContent).blobhash if @content.nil?
	end
	def camliContent
		@camliContent = get_attribute('camliContent') if @camliContent.nil?
	end
end


#################
# @begin Routes #
#################

get '/node/create' do
	@title = 'Create New Entry'
	erb :form
end

post '/node/create' do
	@node = Node.create
	if @node
		@node.set_content(params[:content])
		redirect "/node/#{@node.blobref}"
	else
		redirect "/error"
	end
end

get '/node/:node_ref' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = @node.title || @node.blobref
	erb :node
end

get '/b/:blob_ref' do
	@blob = Blob.get(params[:blob_ref])
	if @blob.nil?
		redirect '/error'
	end
	@title = @blob.blobref
	erb :blob
end

get '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = 'Edit Node'
	erb :form
end

post '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	if @node.title != params[:content]["title"]
		@node.set_title(params[:content]["title"])
	end
	if @node.content != params[:content]
		@node.set_content(params[:content])
	end
	redirect "/node/#{params[:node_ref]}"
end

get '/chronicle' do
	@title = 'Timeline'
	@blobs = Claim.enumerate
	erb :chronicle_index
end

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	@title = 'All Entries'
	@nodes = Node.enumerate_type
	erb :index
end


#################
# @end Routes   #
#################
