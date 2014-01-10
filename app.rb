require 'sinatra'
require 'sinatra/form_helpers'
require 'json'

class Permanode
	@@blobserver = Strand.new

	attr_reader :blobref

	def initialize blobref, blobcontent=nil
		@blobref = blobref
		@blobcontent = blobcontent
		@blobserver = Strand.new
	end

	def blobcontent
		@blobcontent ||= @blobserver.get(blobref)
	end

	def blobhash
		@blobhash ||= JSON.parse(blobcontent)
	end

	def description
		@description ||= @blobserver.describe(@blobref)
	end

	def set_attribute attribute, value
		@blobserver.update_permanode blobref, attribute, value
	end

	def get_attribute attribute
		return nil if description.nil? || description['permanode'].nil? || description['permanode']['attr'].nil? || description['permanode']['attr'][attribute].nil? || description['permanode']['attr'][attribute].first.nil?
		description['permanode']['attr'][attribute].first
	end

	def get_modtime
		return Time.new if description.nil? || description['permanode'].nil? || description['permanode']['modtime'].nil?
		DateTime.parse(description['permanode']['modtime']).to_time
	end

	def get_claims
		claims = @blobserver.enumerate_type('claim').collect! do |blob|
			blobcontent = @blobserver.get(blob['blob'])
			JSON.parse(blobcontent)
		end
		claims.select do |blob|
			blob['permaNode'] == blobref
		end
	end

	def self.create
		self.new(@@blobserver.create_permanode)
	end

	def self.get blobref
		self.new(blobref, @@blobserver.get(blobref))
	end

	def self.enumerate
		@@blobserver.enumerate_type('permanode').collect! do |blob|
			self.new(blob['blob'])
		end
	end
end

class Node < Permanode
	def set_title title
		set_attribute 'title', title
	end

	def set_content content
		set_attribute 'camliContent', @blobserver.put(content.to_json)
	end

	def time
		get_modtime
	end

	def title
		get_attribute('title')
	end

	def content
		@content ||= camliContent || {}
	end

	def camliContent
		sha = get_attribute('camliContent')
		if sha
			content = @blobserver.get(sha)
			JSON.parse(content) if JSON.is_json?(content)
		end
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

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	@title = 'All posts'
	@nodes = Node.enumerate
	erb :index
end


#################
# @end Routes   #
#################
