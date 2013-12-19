require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'

class Blob
	attr_accessor :blobref, :blobcontent
	Filename = "public/blobs.json"

	def initialize blobcontent
		@blobcontent = blobcontent
		@blobref = Digest::SHA1.hexdigest(blobcontent)
	end

	def self.put blobcontent
		blob = self.new blobcontent
	  blobs = self.read_all_items
	  blobs[blob.blobref] = blobcontent
	  self.write_all_items blobs
	  blob
	end

	def self.get blobref
	  blobs = self.read_all_items
	  self.new blobs[blobref]
	end

	def self.enumerate
		blobs = {}
	  self.read_all_items.each do |blobref, blobcontent|
	  	blobs[blobref] = self.new blobcontent
	  end
	  blobs
	end

	def self.write_all_items blobs
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(blobs))
		end
	end

	def self.read_all_items
		blobsource = {}
	  File.open(Filename, "r") do |f|
	    blobsource = JSON.load( f )
	  end
	  blobsource
	end
end

class SchemaBlob < Blob
	attr_accessor :blobjson
	def initialize blobcontent
		super blobcontent
		@blobjson = JSON.parse @blobcontent
	end
end

class Permanode < SchemaBlob
	def initialize
		blobcontent = {
			'blobtype' => 'permanode',
			'random' => rand(0..1000)
		}
		super blobcontent.to_json
	end

	# def claims
	# 	Claim.find_by_permanode_ref @blobref
	# end

	# def get_content
	# 	claims.values.last.get_content
	# end

	# def put_content content
	# 	content_blob = Blob.new content
	# 	content_blob.save
	# 	claim_blob = Claim.new @blobref, content_blob.blobref
	# 	claim_blob.save
	# end
end

# class Claim < SchemaBlob
# 	attr_accessor :permanode_ref, :content_ref
# 	def hash_content
# 		{'type' => @type, 'permanode_ref' => @permanode_ref, 'content_ref' => @content_ref}
# 	end

# 	def initialize permanode_ref, content_ref
# 		@type = 'claim'
# 		@permanode_ref = permanode_ref
# 		@content_ref = content_ref
# 		super hash_content
# 	end

# 	def get_content
# 		blob = Blob.get @content_ref
# 		blob.content
# 	end

# 	def self.find_by_permanode_ref p
# 		blobs = self.enumerate
# 		blobs.select { |blobref, blob|
# 			blob.permanode_ref == p
# 		}
# 	end
# end



# class Node
# 	attr_accessor :title, :body, :id
# 	@@nodes = {}

# 	def hash_content
# 		{'title' => @title, 'body' => @body}
# 	end

# 	def initialize (node_hash)
# 		@title = node_hash[:title] || node_hash['title'] || 'title'
# 		@body = node_hash[:body] || node_hash['body'] || 'body'

# 		if(node_hash[:id] || node_hash['id'])
# 			@id = node_hash[:id] || node_hash['id']
# 			@permanode = Permanode.get @id
# 		else
# 			@permanode = Permanode.new
# 			@id = @permanode.blobref
# 		end

# 		@permanode.put_content hash_content
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

# 	def Node.get(ref)
# 		Permanode.get(ref)
# 	end

# 	def Node.index
# 		Permanode.enumerate
# 	end

# 	# def Node.read_all_items
# 		# @@nodes = Permanode.enumerate
# 	  # n = Storage.read_all_items
# 	  # n.each do |key, node_hash|
#    #  	node = Node.new(node_hash)
#    #  	@@nodes[key] = node
#    #  end
# 	# end

# 	# def Node.write_all_items
# 	# 	@@nodes.each do |key, node|
# 	# 		data = {
# 	# 			'id' => key,
# 	# 			'title' => node.title,
# 	# 			'body' => node.body
# 	# 		}
# 	# 		Storage.write_item key, data
# 	# 	end
# 	# end

# 	# Node.read_all_items

# end


# get '/' do
# 	redirect '/node'
# end

# get '/node/create' do
# 	@title = 'Add New Node'
# 	erb :form
# end

# post '/node/create' do
# 	Node.new(params["node"])
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

get '/node' do
	@title = 'hi'
	@blobs = SchemaBlob.enumerate
	# @node_list = Node.index
	# @title = 'Hello and Welcome'
	erb :index
end
