require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'camlistore'
require 'rest_client'

# http://stackoverflow.com/a/9361331/3015918
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
	def Blobserver.blobref blobcontent
		'sha1-' + Digest::SHA1.hexdigest(blobcontent)
	end
	def Blobserver.get blobref
	  @@camli.get(blobref)
	end
	def Blobserver.enumerate
		@@camli.enumerate_blobs.blobs
	end
	def Blobserver.create_permanode
		system './camput permanode'
	end
	def Blobserver.update_permanode blobref, attribute, value
		system "./camput attr #{blobref} #{attribute} '#{value}'"
	end
end

class Blob
	attr_accessor :blobref, :blobcontent
	def initialize blobref, blobcontent
		@blobref = blobref
		@blobcontent = blobcontent
	end
	def self.get blobref
		blobcontent = Blobserver.get(blobref)
		self.new(blobref, blobcontent)
	end
	def self.put blobcontent
		self.new(Blobserver.put(blobcontent), blobcontent)
	end
	def self.enumerate
		blobs = []
		Blobserver.enumerate.each do |blob|
			blobs << self.get(blob['blobRef'])
		end
		blobs
	end
end

class SchemaBlob < Blob
	def blobhash
		JSON.parse(@blobcontent)
	end
	def valid?
		JSON.is_json?(@blobcontent)
	end
	def self.enumerate
		blobs = super
		blobs = blobs.select do |blob|
			blob.valid?
		end
		blobs.sort_by! { |blob| blob.blobhash["claimDate"] }
	end
	def self.find_by field, value
		blobs = self.enumerate
		blobs.select do |blob|
			blob.blobhash[field] == value
		end
	end
end

class Claim < SchemaBlob
	def Claim.find_by_permanode permanode_ref
		self.find_by('permaNode', permanode_ref)
	end
	def valid?
		super && blobhash['camliType'] == 'claim'
	end
end

class Permanode < SchemaBlob
	def valid?
		super && blobhash['camliType'] == 'permanode'
	end
	def self.create
		blobref = Blobserver.create_permanode
		self.new(blobref, self.get(blobref))
	end
	def update attribute, value
		Blobserver.update_permanode @blobref, attribute, value
	end
	def claims
		Claim.find_by_permanode(@blobref)
	end
end

class Node < Permanode
	def current
		NodeRevision.new(self, claims.length - 1)
	end
	def revision version
		NodeRevision.new(self, version)
	end
	def revisions
		r = []
		claims.each_with_index do |claim, index|
			r << NodeRevision.new(self, index)
		end
		r
	end
	def title
		current.title
	end
	def body
		current.body
	end
end

class NodeRevision
	attr_accessor :node, :version, :claims, :values, :content
	def initialize node, version
		@values = {}
		@content = {}
		@node = node
		@version = version
		@claims = @node.claims.slice(0, @version + 1)
		@claims.each do |claim|
			type = claim.blobhash['claimType']
			attribute = claim.blobhash['attribute']
			value = claim.blobhash['value']
			case type
				when 'set-attribute'
					@values[attribute] = value
				when 'add-attribute'
					@values[attribute] ||= []
					@values[attribute] << value
				when 'del-attribute'
					@values.delete(attribute)
			end
		end
		if @values['camliContent']
			blob = SchemaBlob.get(@values['camliContent'])
			if blob.valid?
				@content = blob.blobhash
			else
				@content = blob.blobcontent
		  end
		end
	end
	def title
		@content['title'] || @content['name'] || @values['title'] || @values['name'] || @node.blobref
	end
	def body
		@content['body'] || @values['body'] || @content
	end
end


# get '/node/create' do
# 	@title = 'Node'
# 	@node = Node.create
# 	redirect "/node/#{@node.blobref}"
# end

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
	@title = 'Edit Node'
	erb :form
end

post '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@node.update('title', params[:content]['title'])
	redirect "/node/#{params[:node_ref]}"
end

get '/node/:node_ref/:num' do
	@node = Node.get(params[:node_ref])
	@revision = @node.revision(params[:num].to_i)
	@title = 'Revision ' + @revision.version.to_s
	erb :node_revision
end

get '/node' do
	@title = 'All Nodes'
	@nodes = Node.enumerate
	erb :index
end

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	redirect '/node'
end