require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'

class Blobserver
	Filename = "public/blobs.json"

	def self.blobref blobcontent
		Digest::SHA1.hexdigest(blobcontent)
	end

	def self.put blobcontent
	  blobs = self.read_all_items
	  blobref = self.blobref(blobcontent)
	  blobs[blobref] = blobcontent
	  self.write_all_items blobs
	  blobref
	end

	def self.get blobref
	  blobs = self.read_all_items
	  blobs[blobref]
	end

	def self.enumerate
		self.read_all_items
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

class Permanode
	attr_accessor :blobref
	def initialize
		content = {
			'type' => 'permanode',
			'random' => rand(0..1000)
		}.to_json
		@blobref = Blobserver.blobref(content)
	end
end

class Node
	attr_accessor :title, :body, :id

	def hash_content
		{'title' => @title, 'body' => @body}
	end

	def json_content
		hash_content.to_json
	end

	def initialize(node_hash)
		@title = node_hash[:title] || node_hash['title'] || 'title'
		@body = node_hash[:body] || node_hash['body'] || 'body'
		@id = node_hash[:id] || node_hash['id'] || Blobserver.blobref (json_content)
	end

	def save
		Blobserver.put json_content
	end

	def Node.get(blobref)
		blobcontent = Blobserver.get blobref
		blobhash = JSON.parse(blobcontent)
		blobhash['id'] = blobref
		Node.new blobhash
	end

	def Node.create(node_hash)
		# create a Node
		node = Node.new(node_hash)
		node.save
		node
		# # create a permanode
		# permanode = Permanode.new

		# # create a blob for the content
		# content = Blobserver.put()
		# claim = Claim.new

	end

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


	def Node.index
		nodes = {}
		Blobserver.enumerate.each do |blobref, blobcontent|
			blobhash = JSON.parse(blobcontent)
			nodes[blobref] = Node.new blobhash
		end
		nodes
	end

# 	# Node.read_all_items

end


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
	# @blobs = SchemaBlob.enumerate
	@node_list = Node.index
	# @title = 'Hello and Welcome'
	erb :index
end
