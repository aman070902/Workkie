//
//  MongoTest.swift
//  workkie
//
//  Created by Carl on 11/5/24.
//

import Foundation
import MongoCore
import MongoKitten

class MongoTest {
    var database: MongoDatabase?
    
    // establish connection
    func connect(uri: String) async throws -> MongoDatabase {
        database = try await MongoDatabase.connect(to: uri)
        print("database is connected")
        return database!
    }
    
    // create
    func insertUser(user: User) async -> Bool{
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["users"]
        let insUser = user.toDocument()
        
        do{
            print("inserting user: \(user.username) password: \(user.password)")
            try await collection.insert(insUser)
            print("insert user: \(user.username) ok")
            return true
        }
        catch{
            print("failed to insert: \(error)")
            return false
        }
    }
    
    // get all users
    func getUsers() async -> [User]? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        let collection = database["users"]
        
        do {
            // get all user cursor
            let usersCursor = try await collection.find()
            
            var users: [User] = []
            let decoder = BSONDecoder()
            
            // go over every user
            for try await document in usersCursor {
                // Decode the document into a User instance
                if let user = try? decoder.decode(User.self, from: document) {
                    users.append(user)
                } else {
                    print("Failed to decode document: \(document)")
                }
            }
            
            return users
        } catch {
            print("Failed to retrieve users: \(error)")
            return nil
        }
    }
    
    // function get single user
    func getUser(userId: ObjectId) async throws -> User? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        let collection = database["users"]
        
        do {
            if let findResult = try await collection.findOne("_id" == userId) {
                let decoder = BSONDecoder()
                let gotUser = try decoder.decode(User.self, from: findResult)
                print("Found user ok")
                return gotUser
            }
            else{
                return nil
                print("Found user \(userId) fail")
            }
        } catch {
            print("Found user \(userId) fail")
            return nil
        }
    }
    
    // function to update user
    func updateUser(newUser: User) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["users"]
        
        let updatedUser = newUser.toDocument()
        
        do {
            let updateResult = try await collection.updateOne(where: "_id" == newUser._id, to: updatedUser)
            print("updated user count: ", updateResult.updatedCount)
            return true
        }
        catch{
            print(error)
            print("update user failed")
            return false
        }
    }
    
    // delete user
    func deleteUser(userId: ObjectId) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["users"]
        
        do {
            let deleteResult = try await collection.deleteOne(where: "_id" == userId) // delete user on condition
            //TODO: if item doesn't exist it will still say ok, but has been removed already
            print("Delete user \(userId) ok")
            return true
        } catch {
            print("Delete user \(userId) fail")
            return false
        }
    }
    
    // login user
    func loginUser(username: String, password: String) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["users"]
        let filter: Document = ["username": username]
        
        do {
            if let userDoc = try await collection.findOne(filter) {
                let decoder = BSONDecoder()
                let gotUser = try decoder.decode(User.self, from: userDoc)
                
                // compare both passwords, not the hash ones right now because it is just testing
                if gotUser.password == password {
                    print("log in user \(username) ok")
                    print("log in user \(gotUser.username) ok")
                    
                    print(UserDefaults.standard.string(forKey: "loggedInUserID"))
                    print(UserDefaults.standard.string(forKey: "loggedInUsername"))
                    
                    UserDefaults.standard.set(gotUser._id?.hexString, forKey: "loggedInUserID")
                    UserDefaults.standard.set(gotUser.username, forKey: "loggedInUsername")
                    UserDefaults.standard.set(true, forKey: "username") // TODO: change your code in other files to use the two keys above.
                    UserDefaults.standard.synchronize()
                    return true
                }
                else{
                    print("log in user \(username) fail")
                    return false
                }
            }
            else{
                print("log in user \(username) not found ")
                return false
            }
        }
        catch {
            print("log in user \(username) fail, \(error)")
            return false
        }
    }
    
    // function to get all posts
    func getAllPosts() async throws -> [Post]? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        let collection = database["posts"]
        
        do {
            // get all post cursor
            let postsCursor = try await collection.find()
            
            var posts: [Post] = []
            let decoder = BSONDecoder()
           
            // go over every post
            for try await document in postsCursor {
                // decode to post interface
                if let post = try? decoder.decode(Post.self, from: document) {
                    posts.append(post)
                } else {
                    print("Failed to decode document: \(document)")
                }
            }
            
            // debug
            print("Retrieved Posts:")
            for post in posts {
                print("Post _id: \(post._id) Post author: \(post.author) Post title: \(post.title) Post content: \(post.content) Post date: \(post.date)")
            }
            
            return posts
        } catch {
            print("Failed to retrieve posts: \(error)")
            return nil
        }
    }
    
    func getAllComments(postId: ObjectId) async throws -> [String]? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        let collection = database["posts"]
        
        do {
            // Find the post by its _id (postId) to get its comments
            let filter: Document = ["_id": postId]
            
            // Fetch the post that matches the given postId
            if let document = try await collection.findOne(filter) {
                // Extract the comments array from the document
                if let comments = document["comments"] as? [String] {
                    // Return the list of comments
                    return comments
                } else {
                    print("No comments found for post with _id: \(postId)")
                    return nil
                }
            } else {
                print("Post not found for _id: \(postId)")
                return nil
            }
        } catch {
            print("Failed to retrieve comments: \(error)")
            return nil
        }
    }

    
    // function to get specific post
    func getPost(id: ObjectId) async throws -> Post? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        print("id need to find: \(id)")
        
        let collection = database["posts"]
        
        do {
            if let postDoc = try await collection.findOne(["_id": id]) {
                let decoder = BSONDecoder()
                let gotPost = try decoder.decode(Post.self, from: postDoc)
                
                // debug
                print("got post with id \(gotPost._id) title: \(gotPost.title) author: \(gotPost.author) content: \(gotPost.content) date: \(gotPost.date)")
                
                // return result
                return gotPost
            }
            else{
                print("post with id \(id) not found")
                return nil
            }
        }
        catch {
            print("find post with id \(id) failed. \(error)")
            return nil
        }
    }
    
    // function to insert post
    func insertPost(post: Post) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["posts"]
        let insPost: Document  = ["author": post.author, "content": post.content, "date": post.date, "title": post.title, "comments": post.comments] // make document of new post
        
        do{
            print("inserting post")
            try await collection.insert(insPost)
            print("insert post of author: \(post.author) title: \(post.title) ok")
            return true
        }
        catch{
            print("failed to insert post: \(error)")
            return false
        }
    }
    
    func insertComment(postId: ObjectId, author: String, content: String) async throws -> Bool {
        
        let postId = postId
        var author = author
        var content = content
        
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        do {
            print("Inserting comment")
//            let newComment: Document = ["author": author, "content": content]
            let newComment: String
            newComment = author + ": " + content
            let collection = database["posts"]
            let filter: Document = ["_id": postId]
            let update: Document = ["$push": ["comments": newComment]]
            
            let result = try await collection.updateOne(where: filter, to: update)
            return true
            
        }
        catch {
            print("Failed to insert comment")
            return false
        }
        return true
    }
    
    // function to delete post
    func deletePost(postId: ObjectId) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        let collection = database["posts"]
        
        do {
            let deleteResult = try await collection.deleteOne(where: "_id" == postId) // delete post on condition
            //TODO: if item doesn't exist it will still say ok, but has been removed already
            print("Delete post \(postId) ok")
            return true
        } catch {
            print("Delete post \(postId) fail")
            return false
        }
    }
    
    func sendConnectionRequest(clRequest: ConnectionRequest) async throws -> Bool {
        guard let database = database else {
            print("Database is not connected.")
            return false
        }
        
        do{
            // get user to send connection request to
            let dUser = try await self.getUser(userId: clRequest.toUser)
            
            guard let dUser = dUser else {
                print("didn't find user")
                return false
            }

            let dUserNew = User(
                _id: dUser._id,
                username: dUser.username,
                password: dUser.password,
                avatar: dUser.avatar,
                email: dUser.email,
                latitude: dUser.latitude,
                longitude: dUser.longitude,
                education: dUser.education,
                degree: dUser.degree,
                connections: dUser.connections ?? [],
                connectionRequests: [clRequest]
            )

            
            // put the user back
            let updateResult = try await updateUser(newUser: dUserNew)
            
            if(updateResult) {
                print("send connection request successful")
                return true
            }
            else{
                print("send connection request failed")
                return false
            }
        }
        catch {
            print(error)
            return false
        }
    }
    
    // function to get all connection requests for a specific user
    func getConnectionRequest(userId: ObjectId) async -> [ConnectionRequest]? {
        guard let database = database else {
            print("Database is not connected.")
            return nil
        }
        
        do {
            // get user
            let gotUser = try await getUser(userId: userId)
            
            if let gUser = gotUser {
                print("got connection requests success")
                return gUser.connectionRequests ?? []
            }
            else{
                print("get connection requests fail")
                return nil
            }
        } catch {
            print("get connection requests fail")
            return nil
        }
    }
}
