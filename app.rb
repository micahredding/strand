require 'sinatra'
require 'sinatra/form_helpers'
require 'json'

class Node
	attr_accessor :title, :body, :id
	Filename = "/var/www/sinatra/public/temp.json"
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
		Node.write
	end

	def delete
		@@nodes.delete(@id)
		Node.write
	end

	def Node.create(node_hash)
		node = Node.new(node_hash)
		@@nodes[node.id] = node
		Node.write
		node
	end

	def Node.find (id)
		@@nodes[id]
	end

	def Node.index
		@@nodes
	end

	def Node.read
	  # {"a":{"title":"title1","body":"body1"},"b":{"title":"title2","body":"body2"},"c":{"title":"title3","body":"body3"}}
	  File.open( Filename, "r" ) do |f|
	    n = JSON.load( f )
	    n.each do |key, node_hash|
	    	node = Node.new(node_hash)
	    	@@nodes[key] = node
	    end
	  end
	end

	def Node.write
		n = {}
		@@nodes.each do |key, node|
			n[key] = {
				'id' => key,
				'title' => node.title,
				'body' => node.body
			}
		end
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(n))
		end
	end

	Node.read

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
	puts n.inspect
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
