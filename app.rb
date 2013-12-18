require 'sinatra'
require 'sinatra/form_helpers'
require 'json'

module Storage
	Filename = "public/temp.json"
	def self.write_item key, data
	  n = self.read_all_items
	  n[key] = data
	  self.write_all_items n
	end

	def self.read_item key
	  n = self.read_all_items
	  n[key]
	end

	def self.delete_item key
		n = self.read_all_items
		n.delete(key)
		self.write_all_items n
	end

	def self.write_all_items n
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(n))
		end
	end

	def self.read_all_items
		n = {}
	  File.open(Filename, "r") do |f|
	    n = JSON.load( f )
	  end
	  n
	end
end

module Blobserver
	Filename = "public/blobs.json"
	def self.put key, data
	  n = self.read_all_items
	  n[key] = data
	  self.write_all_items n
	end

	def self.get key
	  n = self.read_all_items
	  n[key]
	end

	def self.enumerate
		self.read_all_items
	end

	def self.write_all_items n
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(n))
		end
	end

	def self.read_all_items
		blob_hashes = {}
	  File.open(Filename, "r") do |f|
	    blob_hashes = JSON.load( f )
	  end
	  blob_hashes
	end
end

class Blob
	extend Blobserver
	attr_accessor :blobref, :content
	def initialize content
		@blob_ref = rand(100000).to_s
		@content = content
		self.put @blob_ref, @content
	end

	def self.get key
		data = super key
		self.new key, data
	end

	def self.enumerate
		blobs = {}
	  self.read_all_items.each do |blobref, blobcontent|
	  	blobs[blobref] = Blob.new(blobref, blobcontent)
	  end
	  blobs
	end
end

class Permanode < Blob
	claims
end

class Claim < Blob
	def self.find_by_permanode
		blobs = self.enumerate
		blobs.select { |blob, content|
			content
		}
	end
end



class Node
	attr_accessor :title, :body, :id
	@@nodes = {}

	def initialize (node_hash)
		@title = node_hash[:title] || node_hash['title'] || 'title'
		@body = node_hash[:body] || node_hash['body'] || 'body'
		@id = node_hash[:id] || node_hash['id'] || rand(100000).to_s
	end

	def update(node_hash)
		@title = node_hash[:title] || node_hash['title'] || @title
		@body = node_hash[:body] || node_hash['body'] || @body
		@@nodes[@id] = self
		Node.write_all_items
	end

	def delete
		@@nodes.delete(@id)
		Node.write_all_items
	end

	def Node.create(node_hash)
		node = Node.new(node_hash)
		@@nodes[node.id] = node
		Node.write_all_items
		node
	end

	def Node.find (id)
		@@nodes[id]
	end

	def Node.index
		@@nodes
	end

	def Node.read_all_items
	  n = Storage.read_all_items
	  n.each do |key, node_hash|
    	node = Node.new(node_hash)
    	@@nodes[key] = node
    end
	end

	def Node.write_all_items
		@@nodes.each do |key, node|
			data = {
				'id' => key,
				'title' => node.title,
				'body' => node.body
			}
			Storage.write_item key, data
		end
	end

	Node.read_all_items

end


get '/' do
	redirect '/node'
end

get '/node/create' do
	@title = 'Add New Node'
	erb :form
end

post '/node/create' do
	n = Node.create(params["node"])
	redirect '/node'
end

get '/node/:id/edit' do
	@title = 'Edit Node'
	@node = Node.find(params[:id])
	erb :form
end

post '/node/:id/edit' do
	n = Node.find(params[:id])
	n.update(params["node"])
	redirect '/node'
end

get '/node/:id/delete' do
	@title = 'Are you sure you want to delete this node?'
	erb :form_confirm
end

post '/node/:id/delete' do
	n = Node.find(params[:id])
	n.delete
	redirect '/node'
end

get '/node/:id' do
	@node = Node.find(params[:id]);
	erb :node
end

get '/node' do
	@node_list = Node.index
	@title = 'Hello and Welcome'
	erb :index
end
