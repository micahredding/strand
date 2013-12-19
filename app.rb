require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'pry'

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
	@@type = 'schemablob'
	def initialize blobref, blobcontent
		@blobref = blobref
		@blobcontent = blobcontent
		@blobhash = JSON.parse(@blobcontent) || {}
		binding.pry
	end
	def save
		Blobserver.put(@blobcontent)
	end
	def self.create blobcontent
		blobref = Blobserver.blobref(blobcontent)
		schemablob = self.new(blobref, blobcontent)
		schemablob.save
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
			if blobhash['type'] == @@type
				schemablobs << self.new(blobref, blobcontent)
			end
		end
		schemablobs
	end
	def self.find_by field, value
		blobs = Blobserver.enumerate
		claims = []
		blobs.each do |blobref, blobcontent|
			blobhash = JSON.parse(blobcontent)
			if blobhash['type'] == @@type && blobhash[field] == value
				claims << Claim.new(blobref, blobcontent)
			end
		end
		claims
	end
end

class Permanode < SchemaBlob
	@@type = 'permanode'
	def claims
		Claim.find_by_permanode(@blobref)
	end
	def current_claim
		claims.last
	end
	def current_content
		current_claim.content
	end
	def Permanode.create
		blobcontent = {
			'type' => 'permanode',
			'random' => rand(0..1000)
		}.to_json
		SchemaBlob.create blobcontent
	end
end

class Claim < SchemaBlob
	@@type = 'claim'
	def content
		Content.get(@blobhash['content'])
	end
	def Claim.create permanode, content
		blobcontent = {
			'type' => 'claim',
			'permanode' => permanode.blobref || permanode,
			'content' => content.blobref || content,
		}.to_json
		SchemaBlob.create blobcontent
	end
	def Claim.find_by_permanode permanode_ref
		self.find_by('permanode', permanode_ref)
	end
end

class Content < SchemaBlob
	@@type = 'content'
	def title
		@blobhash['title']
	end
	def body
		@blobhash['body']
	end
	def Content.create content_hash
		blobcontent = content_hash.to_json
		SchemaBlob.create blobcontent
	end
end

# class MutableObject
# 	attr_accessor :permanode
# 	def initialize permanode
# 		@permanode = permanode || Permanode.create
# 	end

# 	def update(content_hash)
# 		content = Content.create(content_hash)
# 		claim = Claim.create(@permanode, content)
# 	end

# 	def claims
# 		Claim.find_by_permanode(@permanode)
# 	end

# 	def current_claim
# 		claims.values.last
# 	end

# 	def current_content
# 		JSON.parse(current_claim)
# 	end

# 	def MutableObject.enumerate
# 		Permanode.enumerate
# 	end

# 	def MutableObject.get blobref
# 		permanode = Blobserver.get(blobref)
# 		MutableObject.new(permanode)
# 	end
# end

# class Node
# 	attr_accessor :title, :body, :id, :permanode

# 	def json_content
# 		{'title' => @title, 'body' => @body}.to_json
# 	end

# 	def initialize(node_hash)
# 		@title = node_hash[:title] || node_hash['title'] || 'title'
# 		@body = node_hash[:body] || node_hash['body'] || 'body'
# 		@id = node_hash[:id] || node_hash['id'] || Blobserver.blobref(json_content)
# 	end

# 	def save
# 		Blobserver.put json_content
# 	end

# 	def Node.get(blobref)
# 		blobcontent = Blobserver.get(blobref)
# 		blobhash = JSON.parse(blobcontent)
# 		blobhash['id'] = blobref
# 		Node.new(blobhash)
# 	end

# 	def Node.create_new_from_scratch(node_hash)
# 		permanode = Permanode.create
# 		content = Content.create(node_hash)
# 		claim = Claim.create(permanode, content)
# 	end

# 	def Node.create(node_hash)
# 		# create a Node
# 		node = Node.new(node_hash)

# 		# create a permanode
# 		@permanode = Permanode.create

# 		# create a blob for the content
# 		content = Content.create(node_hash)

# 		# create a claim to attach
# 		claim = Claim.create(@permanode, content)
# 	end

# 	def update(node_hash)
# 		@title = node_hash[:title] || node_hash['title'] || @title
# 		@body = node_hash[:body] || node_hash['body'] || @body
# 		@permanode.put_content hash_content
# 		# @@nodes[@id] = self
# 		# Node.write_all_items
# 	end

# 	# def delete
# 	# 	@@nodes.delete(@id)
# 	# 	Node.write_all_items
# 	# end

# 	# def Node.create(node_hash)
# 	# 	node = Node.new(node_hash)
# 		# permanode.put_content node_hash
# 		# @@nodes[node.id] = node
# 		# Node.write_all_items
# 		# permanode
# 	# end


	# def Node.index
	# 	nodes = {}
	# 	Blobserver.enumerate.each do |blobref, blobcontent|
	# 		nodes[blobref] = Node.get(blobref)
	# 	end
	# 	nodes
	# end

# 	# Node.read_all_items

# end

get '/claim/create/:permanode_blobref' do
	@title = 'Add New Claim to a Permanode'
	@permanode = Permanode.get(params[:permanode_blobref])
	@content = Content.create({'title' => 'Sample Title', 'body' => 'Sample Body'})
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
	@claims = Claim.enumerate
	@claim = @claims.last
	@content = @claim
	# @content = @permanode.claims
	# @content = @permanode.current_content
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
