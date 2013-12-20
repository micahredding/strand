require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'pry'

# @begin Data Structures
class Blobserver
	Filename = "public/blobs.json"

	def Blobserver.blobref blobcontent
		Digest::SHA1.hexdigest(blobcontent)
	end

	def Blobserver.put blobcontent
	  blobs = Blobserver.read_all_items
	  blobref = Blobserver.blobref(blobcontent)
	  blobs[blobref] = blobcontent
	  Blobserver.write_all_items blobs
	  blobref
	end

	def Blobserver.get blobref
	  blobs = Blobserver.read_all_items
	  blobs[blobref]
	end

	def Blobserver.enumerate
		Blobserver.read_all_items
	end

	def Blobserver.write_all_items blobs
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(blobs))
		end
	end

	def Blobserver.read_all_items
		blobsource = {}
	  File.open(Filename, "r") do |f|
	    blobsource = JSON.load( f )
	  end
	  blobsource
	end
end

class SchemaBlob
	attr_accessor :blobref, :blobcontent, :blobhash
	def initialize blobref, blobcontent
		@blobref = blobref
		@blobcontent = blobcontent
		@blobhash = JSON.parse(@blobcontent) || {}
	end
	def save
		Blobserver.put(@blobcontent)
	end
	def self.type
		name.downcase
	end
	def self.create blobcontent
		blobref = Blobserver.blobref(blobcontent)
		schemablob = self.new(blobref, blobcontent)
		schemablob.save
		schemablob
	end
	def self.get blobref
		blobcontent = Blobserver.get(blobref)
		self.new(blobref, blobcontent)
	end
	def self.put blobcontent
		Blobserver.put(blobcontent)
	end
	def self.enumerate
		blobs = Blobserver.enumerate
		schemablobs = []
		blobs.each do |blobref, blobcontent|
			blobhash = JSON.parse(blobcontent)
			if blobhash['type'] == self.type
				schemablobs << self.new(blobref, blobcontent)
			end
		end
		schemablobs
	end
	def self.find_by field, value
		blobs = Blobserver.enumerate
		schemablobs = []
		blobs.each do |blobref, blobcontent|
			blobhash = JSON.parse(blobcontent)
			if blobhash['type'] == self.type && blobhash[field] == value
				schemablobs << self.new(blobref, blobcontent)
			end
		end
		schemablobs
	end
end

class Permanode < SchemaBlob
	def Permanode.create
		blobcontent = {
			'type' => 'permanode',
			'random' => rand(0..1000)
		}.to_json
		super blobcontent
	end
	def claims
		Claim.find_by_permanode(@blobref)
	end
	def current_claim
		claims.last || nil
	end
	def current_content
		return nil if current_claim.nil?
		current_claim.content
	end
end

class Claim < SchemaBlob
	def Claim.create permanode, content
		blobcontent = {
			'type' => 'claim',
			'permanode' => permanode.blobref || permanode,
			'content' => content.blobref || content,
		}.to_json
		super blobcontent
	end
	def Claim.find_by_permanode permanode_ref
		self.find_by('permanode', permanode_ref)
	end
	def content
		Content.get(@blobhash['content'])
	end
end

class Content < SchemaBlob
	def Content.create content_hash
		blobcontent = content_hash.to_json
		super blobcontent
	end
end
# @end Data Structures

class MutableObject
	attr_accessor :permanode

	def initialize permanode
		@permanode = permanode
	end

	def blobref
		@permanode.blobref
	end

	def update(content_hash)
		content = Content.create(content_hash)
		claim = Claim.create(@permanode, content)
	end

	def content
		claims = Claim.find_by_permanode(@permanode.blobref)
		if claims.count > 0
			claim = claims.last
			content = claim.content
		end
		content || nil
	end

	def MutableObject.create
		@permanode = Permanode.create
	end

	def MutableObject.enumerate
		objects = []
		Permanode.enumerate.each do |permanode|
			objects << MutableObject.new(permanode)
		end
		objects
	end

	def MutableObject.get blobref
		permanode = Permanode.get(blobref)
		MutableObject.new(permanode)
	end
end

class Node < MutableObject
	attr_accessor :title, :body
end

get '/node/create' do
	@title = 'Node'
	@node = Node.create
	redirect "/node/#{@node.blobref}"
end

get '/node/:permanode_ref' do
	@title = 'Node'
	@node = Node.get(params[:permanode_ref])
	@permanode = @node.permanode
	@content = @node.content.blobhash
	erb :mutableobject
end

get '/node/:permanode_ref/edit' do
	@title = 'Edit Node'
	@node = Node.get(params[:permanode_ref])
	@permanode = @node.permanode
	@content = @node.content.blobhash
	erb :form
end

post '/node/:permanode_ref/edit' do
	@title = 'Edit Node'
	@node = Node.get(params[:permanode_ref])
	@node.update(params['content'])
	redirect "/node/#{params[:permanode_ref]}"
end

get '/claim/create/:permanode_blobref' do
	@title = 'Add New Claim to a Permanode'
	erb :form
end

post '/claim/create/:permanode_blobref' do
	@title = 'Add New Claim to a Permanode'
	@permanode = Permanode.get(params[:permanode_blobref])
	@content = Content.create(params['content'])
	Claim.create(@permanode, @content)
	redirect "/permanode/#{@permanode.blobref}"
end

get '/permanode/create' do
	@title = 'Add New Permanode'
	@permanode = Permanode.create
	redirect "/permanode/#{@permanode.blobref}"
end

get '/permanode/:blobref' do
	@title = 'Permanode'
	@permanode = Permanode.get(params[:blobref])
	@claims = @permanode.claims
	@content = @permanode.current_content
	erb :permanode
end

get '/permanode' do
	@title = 'Permanodes'
	@permanode_list = Permanode.enumerate
	erb :permanode_index
end

get '/permanode/' do
	redirect '/permanode'
end

# get '/' do
# 	redirect '/node'
# end

# get '/node/create' do
# 	@title = 'Add New Node'
# 	erb :form
# end

# post '/node/create' do
# 	Node.new(params["node"]).save
# 	redirect '/node'
# end

# get '/node/:id/edit' do
# 	@title = 'Edit Node'
# 	@node = Node.get(params[:id])
# 	erb :form
# end

# post '/node/:id/edit' do
# 	n = Node.get(params[:id])
# 	n.update(params["node"])
# 	redirect '/node'
# end

# get '/node/:id/delete' do
# 	@title = 'Are you sure you want to delete this node?'
# 	erb :form_confirm
# end

# # post '/node/:id/delete' do
# # 	n = Node.get(params[:id])
# # 	n.delete
# # 	redirect '/node'
# # end

# get '/node/:id' do
# 	@node = Node.get(params[:id]);
# 	erb :node
# end

# get '/node' do
# 	@title = 'hi'
# 	# @blobs = SchemaBlob.enumerate
# 	@node_list = Node.index
# 	# @title = 'Hello and Welcome'
# 	erb :index
# end
