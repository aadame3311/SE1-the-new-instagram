require "sinatra"
require "sinatra/namespace"
require_relative 'models.rb'
require_relative "api_authentication.rb"
require "json"
require 'fog'
require 'csv'
require "./token"


connection = Fog::Storage.new({
:provider                 => 'AWS',
:aws_access_key_id        => Keys::TOKENS['access'],
:aws_secret_access_key    => Keys::TOKENS['secret']
})

if ENV['DATABASE_URL']
	S3_BUCKET = "instagram"
else
	S3_BUCKET = "instagram-dev"
end

def placeholder
	halt 501, {message: "Not Implemented"}.to_json
end

def not_found!
	halt 404, {message: "404, not found"}.to_json
end
def not_allowed!
	halt 401, {message: "401, action not allowed"}.to_json
end

if !User.first(email: "student@student.com")
	u = User.new
	u.email = "student@student.com"
	u.password = "student"
	u.bio = "Student"
	u.profile_image_url = "https://via.placeholder.com/1080.jpg"
	u.save
end

namespace '/api/v1' do
	before do
		content_type 'application/json'
	end

	#ACCOUNT MAINTENANCE

	#returns JSON representing the currently logged in user
	get "/my_account" do
		api_authenticate!
		return current_user.to_json
	end

	#let people update their bio
	patch "/my_account" do
		api_authenticate!
		if (params["bio"])
			new_bio = params["bio"]
			current_user.bio = new_bio if current_user
			current_user.save
		end
	end

	#let people update their profile i
	patch "/my_account/profile_image" do
		api_authenticate!
		if params[:image] && params[:image][:tempfile] && params[:image][:filename]
			begin
				file       = params[:image][:tempfile]
				filename   = params[:image][:filename]
				directory = connection.directories.create(
					:key    => "fog-demo-#{Time.now.to_i}", # globally unique name
					:public => true
				)
				file2 = directory.files.create(
					:key    => filename,
					:body   => file,
					:public => true
				)
				url = file2.public_url
				current_user.profile_image_url = url
				current_user.save

				halt 200, {message: "Uploaded Image to #{url}"}.to_json
			rescue
				halt 422, {message: "Unable to Upload Image"}.to_json
			end
		end

	end

	#returns JSON representing all the posts by the current user
	#returns 404 if user not found
	get "/my_posts" do
		api_authenticate!
		return current_user.posts.to_json if current_user.posts

		not_found!
	end

	#USERS

	#returns JSON representing the user with the given id
	#returns 404 if user not found
	get "/users/:id" do
		api_authenticate!
		user = User.get(params["id"])
		return user.to_json if user

		halt 404, {"message": "User not found."}.to_json
	end

	#returns JSON representing all the posts by the user with the given id
	#returns 404 if user not found
	get "/users/:user_id/posts" do
		placeholder
	end

	# POSTS

	#returns JSON representing all the posts in the database
	get "/posts" do
		api_authenticate!
		return Post.all().to_json
	end

	#returns JSON representing the post with the given id
	#returns 404 if post not found
	get "/posts/:id" do
		api_authenticate!
		post = Post.get(params['id'])
		return post.to_json if post

		not_found! # 404
	end

	#adds a new post to the database
	#must accept "caption" and "image" parameters
	post "/posts" do
		api_authenticate!
		if current_user
			if params['caption'] && params[:image] && params[:image][:tempfile] && params[:image][:filename]
				begin
					file       = params[:image][:tempfile]
					filename   = params[:image][:filename]
					directory = connection.directories.create(
						:key    => "fog-demo-#{Time.now.to_i}", # globally unique name
						:public => true
					)
					file2 = directory.files.create(
						:key    => filename,
						:body   => file,
						:public => true
					  )
					url = file2.public_url
					new_post = Post.create(
						:caption=>params[:caption],
						:image_url=>url,
						:user_id=>current_user.id
					) if current_user
					halt 200, {message: "Uploaded Image to #{url}"}.to_json
				rescue
					halt 422, {message: "Unable to Upload Image"}.to_json
				end
			end
		end
	end

	#updates the post with the given ID
	#only allow updating the caption, not the image
	patch "/posts/:id" do
		api_authenticate!
		post = Post.get(params[:id])
		post.caption = params['caption']
		post.save
	end

	#deletes the post with the given ID
	#returns 404 if post not found
	delete "/posts/:id" do
		api_authenticate!
		post = Post.get(params[:id])
		post.destroy if current_user.id == post.user_id

		not_allowed! # 401 
	end

	#COMMENTS

	#returns JSON representing all the comments
	#for the post with the given ID
	#returns 404 if post not found
	get "/posts/:id/comments" do
		api_authenticate!
		post = Post.get(params[:id])
		return post.comments.to_json if post

		not_found!
	end

	#adds a comment to the post with the given ID
	#accepts "text" parameter
	#returns 404 if post not found
	post "/posts/:id/comments" do
		api_authenticate!
		if Post.get(params[:id]) and current_user
			Comment.create(
				:user_id=>current_user.id,
				:post_id=>params[:id],
				:text=>params["text"]
			) 
		else	
			not_found! # 404
		end

	end

	#updates the comment with the given ID
	#only allows updating "text" property
	#returns 404 if not found
	#returns 401 if comment does not belong to current user
	patch "/comments/:id" do
		api_authenticate!

		comment = Comment.get(params[:id])
		same_user = comment.user_id == current_user.id

		not_allowed! if !same_user
		not_found if !comment
		return if !comment or !same_user

		comment.text = params["text"]
		comment.save
	end

	#deletes the comment with the given ID
	#returns 404 if not found
	#returns 401 if comment does not belong to current user
	delete "/comments/:id" do
		api_authenticate!

		comment = Comment.get(params[:id])
		same_user = comment.user_id == current_user.id

		not_allowed! if !same_user
		not_found if !comment
		return if !comment or !same_user

		comment.destroy
	end

	#LIKES
	
	#get the likes for the post with the given ID
	#returns 404 if post not found
	get "/posts/:id/likes" do
		api_authenticate!
		post = Post.get(params[:id])
		return post.likes.to_json if post

		not_found!# 404
	end

	#adds a like to a post, if not already liked
	#returns 404 if post not found
	post "/posts/:id/likes" do
		api_authenticate!
		Like.create(
			:user_id=>current_user.id,
			:post_id=>params[:id]
		)

		not_found! if !Post.get(params[:id]) # 404
	end

	#deletes a like from the post with
	#the given ID, if the like exists
	#returns 404 if not found
	#returns 401 if like does not belong to current user
	delete "/posts/:id/likes" do
		api_authenticate!
		like = Like.first(:post_id=>params[:id])
		if like 
			like.destroy if current_user
			return
		end

		not_found! # 404
	end
end
