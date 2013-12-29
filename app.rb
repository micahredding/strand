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
  # UnspecifiedSort   = 0
  # LastModifiedDesc  = 1
  # LastModifiedAsc   = 2
  # CreatedDesc       = 3
  # CreatedAsc        = 4

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
	  @@camli.get(blobref)
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
		response = Faraday.get url, {'blobref' => blobref}
		if response.status == 200
			if JSON.is_json?(response.body)
				results = JSON.parse(response.body)
				if !results.nil? && !results['meta'].nil? && !results['meta'][blobref].nil?
					return results['meta'][blobref]
				end
			end
		end
		{}
	end

	def Blobserver.search query
		query = query.to_json if query.is_a?(Hash)
		url = @@root_url + @@search_root + 'camli/search/query'
		response = Faraday.post url, query
		if response.status == 200
			if JSON.is_json?(response.body)
				results = JSON.parse(response.body)
				if !results.nil? && !results['blobs'].nil?
					return results['blobs']
				end
			end
		end
		[]
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

	def Blobserver.enumerate_permanodes
		Blobserver.search({"constraint" => {"camliType" => 'permanode'}})
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

	Blobserver.init
end


class Permanode
	def initialize blobref, blobcontent=nil
		@blobref = blobref
		@blobcontent = blobcontent
	end

	def blobref
		@blobref
	end

	def blobcontent
		@blobcontent = Blobserver.get(blobref) if @blobcontent.nil?
		@blobcontent
	end

	def blobhash
		@blobhash = JSON.parse(blobcontent) if @blobhash.nil?
		@blobhash
	end

	def description
		@description = Blobserver.describe(@blobref) if @description.nil?
		@description
	end

	def set_attribute attribute, value
		Blobserver.update_permanode blobref, attribute, value
	end

	def get_attribute attribute
		return nil if description.nil? || description['permanode'].nil? || description['permanode']['attr'].nil? || description['permanode']['attr'][attribute].nil? || description['permanode']['attr'][attribute].first.nil?
		description['permanode']['attr'][attribute].first
	end

	def get_modtime
		return Time.new if description.nil? || description['permanode'].nil? || description['permanode']['modtime'].nil?
		DateTime.parse(description['permanode']['modtime']).to_time
	end

	def self.create
		self.new(Blobserver.create_permanode)
	end

	def self.get blobref
		self.new(blobref, Blobserver.get(blobref))
	end

	def self.enumerate
		Blobserver.enumerate_permanodes.collect! do |blob|
			self.new(blob['blob'])
		end
	end

end

class Node < Permanode
	def set_title title
		set_attribute 'title', title
	end
	def set_content content
		blobref = Blobserver.put(content.to_json)
		set_attribute 'camliContent', blobref
	end

	def time
		get_modtime
	end

	def title
		get_attribute('title')
	end

	def content
		@content = JSON.parse(Blobserver.get(get_attribute('camliContent'))) if @content.nil?
		@content
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
		@node.set_title(params[:content]["title"])
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
	@blobref = params[:blob_ref]
	@blobcontent = Blobserver.get(@blobref)
	if @blobcontent.nil?
		redirect '/error'
	end
	@title = @blobref
	erb :blob
end

get '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = 'Edit Entry'
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

# get '/chronicle' do
# 	@title = 'Timeline'
# 	@blobs = Claim.enumerate
# 	erb :chronicle_index
# end

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	@title = 'All Entries'
	@nodes = Node.enumerate
	erb :index
end


#################
# @end Routes   #
#################
