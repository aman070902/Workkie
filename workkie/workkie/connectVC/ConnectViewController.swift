//
//  ConnectViewController.swift
//  workkie
//
//  Created by Aman Verma on 11/9/24.
//

import UIKit
import MapKit
import BSON

class ConnectViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, MKMapViewDelegate {
    
    // define location manager for map
    let locationManager = LocationManager()
    
    // MARK: - Outlets
    @IBOutlet var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var connectionButton: UIButton!
    
    // MARK: - Properties
    var profiles: [User] = []
    var filteredProfiles: [User] = []
    
    let mongoTest = MongoTest()
    var currentUser: ObjectId?
    var currentUsername: String?
    
    // swipe down to refresh
    let swipeRefresh = UIRefreshControl()
    
    // db uri
    let dbUri = "mongodb+srv://chengli:Luncy1234567890@users.at6lb.mongodb.net/users?authSource=admin&appName=Users"
    
    
    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup delegates and data sources
        tableView.delegate = self
        tableView.dataSource = self
        searchBar.delegate = self
        mapView.delegate = self
        
        // configure swipe down to refresh
        swipeRefresh.addTarget(self, action: #selector(connectToMongoDB), for: .valueChanged)
        tableView.refreshControl = swipeRefresh
        
        tableView.register(UINib(nibName: "ProfileCell", bundle: nil), forCellReuseIdentifier: "ProfileCell")
        
        // Adjust row height for better UI
        tableView.rowHeight = 60
        
        // always load real data now
        connectToMongoDB()
        
        // Setup map view
        setupMapView()
        
        // send user current coordinates to mongo db so others can see
        Task {
            do {
                await setUserCoordinates()
            }
        }
        
        // start fetching connection requests
        startFetchConnectionRequest()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // Check whether to use real MongoDB data or pseudo data
        connectToMongoDB()
        
        
        // Setup map view
        setupMapView()
        
        // send user current coordinates to mongo db so others can see
        Task {
            do {
                await setUserCoordinates()
            }
        }
        
        // start fetching connection requests
        startFetchConnectionRequest()
    }
    
    private func setUserCoordinates() async {
        
        // get user's latitude and longitude and update it to mongo
        
        if isLoggedIn() {
            print("user logged in, setting user coordinates")
            
            Task {
                do{
                    try await mongoTest.connect(uri: dbUri)
                    let allUsers = await self.mongoTest.getUsers()
                    
                    if let gotUser = allUsers?.first(where: {$0._id?.hexString == self.currentUser?.hexString}) {
                        
                        // get current user coordinates
                        let curLat = self.locationManager.userCoordinates?.latitude
                        let curLon = self.locationManager.userCoordinates?.longitude
                        
                        // create new user object
                        if let curLat = curLat, let curLon = curLon {
                            
                            let userWithCoord = User(
                                _id: gotUser._id,
                                username: gotUser.username,
                                password: gotUser.password,
                                avatar: gotUser.avatar,
                                email: gotUser.email,
                                latitude: curLat,
                                longitude: curLon,
                                education: gotUser.education,
                                degree: gotUser.degree,
                                connections: gotUser.connections ?? [],
                                connectionRequests: gotUser.connectionRequests ?? []
                            )
                            
                            let insertResult = try await mongoTest.updateUser(newUser: userWithCoord)
                            
                            if insertResult {
                                print("user coordinates updated ")
                            }
                            else{
                                print("update user with coordinates failed")
                            }
                        }
                        else{
                            print("get user current location failed, coordinates not set")
                        }
                    }
                }
                catch {
                    print(error)
                }
            }
        }
        else{
            print("user not logged in, not setting coordinates")
            return
        }
    }
    
    // MARK: - Map View Setup
    private func setupMapView() {
        mapView.mapType = .standard
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: true)
        mapView.showsScale = true
        locationManager.requestLocation()
    }
    
    // update map annotations for all users
    private func updateMapAnnotationsForAllUsers() {
        // remove existing
        mapView.removeAnnotations(mapView.annotations)
        
        // Add annotations for all profiles with valid latitude and longitude
        for user in profiles {
            guard let lat = user.latitude, let lon = user.longitude else { continue }
            
            // don't add annotation for the current user
            if user._id == currentUser { continue }
            
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            annotation.title = user.username
            mapView.addAnnotation(annotation)
        }
    }
    
    // set up connection
    @objc func connectToMongoDB() {
        Task {
            do {
                let client = try await mongoTest.connect(uri: dbUri)
                
                print("Connected to MongoDB successfully!")
                await loadUserProfiles()
            } catch {
                print("Failed to connect to MongoDB: \(error)")
            }
        }
    }
    
    // MARK: - Data Loading Methods
    func loadUserProfiles() async {
        if let users = await mongoTest.getUsers() {
            profiles = users
            filteredProfiles = profiles
            
            // update user coordinates
            await setUserCoordinates()
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.updateMapAnnotationsForAllUsers()  // Update map after loading data
                self.swipeRefresh.endRefreshing()
            }
        } else {
            print("No users found in MongoDB.")
        }
    }
    
    // MARK: - UITableViewDataSource Methods
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredProfiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath) as? ProfileCell else {
            return UITableViewCell()
        }
        
        // Configure the cell with user data
        let user = filteredProfiles[indexPath.row]
        cell.nameLabel?.text = user.username
        cell.designationLabel?.text = user.education
        cell.profileImageView?.image = UIImage(named: "profile_img")
        
        
        // Add an action for the Connect button
        cell.connectButton.addTarget(self, action: #selector(connectButtonTapped(_:)), for: .touchUpInside)
        cell.connectButton.tag = indexPath.row  // add tag
        
        
        return cell
    }
    
    
    @IBAction func connectionButtonPressed(_ sender: Any) {
        
        // check log in
        if isLoggedIn() {
            let connectionViewController = storyboard?.instantiateViewController(withIdentifier: "connectionViewController") as! ConnectionViewController
            connectionViewController.title = "My Connections"
            
            let navController = UINavigationController(rootViewController: connectionViewController)
            self.present(navController, animated: true, completion: nil)
        }
        else{
            let alertController = UIAlertController(
                title: "Login Required",
                message: "You need to log in to see your connections",
                preferredStyle: .alert
            )
            
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    
    @objc func connectButtonTapped(_ sender: UIButton) {
        let selectedIndex = sender.tag
        let selectedUser = filteredProfiles[selectedIndex]
        
        // check if user is logged in first
        if !isLoggedIn() {
            let alert = UIAlertController(title: "Connect Failed", message: "Log in to send a connect request", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }
        
        // check if the user is sending the request to himself
        if selectedUser._id == currentUser {
            let alert = UIAlertController(title: "Connect Failed", message: "You cannot connect with yourself", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            return
        }
        
        Task {
            do {
                
                // check if the two users are already connections
                let users = try await mongoTest.getUser(userId: currentUser!)
                
                if let connections = users?.connections {
                    for connection in connections {
                        //print("connection.username \(connection.username)")
                        //print("selecteduser.username \(selectedUser.username)")
                        if connection.username == selectedUser.username {
                            // abort because user already connections
                            DispatchQueue.main.async {
                                let alert = UIAlertController(
                                    title: "Request not sent",
                                    message: "You are already connections with \(selectedUser.username)",
                                    preferredStyle: .alert
                                )
                                alert.addAction(UIAlertAction(title: "OK", style: .default))
                                self.present(alert, animated: true)
                            }
                            return
                        }
                    }
                }
            
                let clRequest = ConnectionRequest(fromUser: currentUser!, toUser: selectedUser._id!, status: "pending", date: Date(), fromUsername: currentUsername!, toUsername: selectedUser.username)
                
                let isRequestSent = try await mongoTest.sendConnectionRequest(clRequest: clRequest)
                
                DispatchQueue.main.async {
                    if isRequestSent {
                        
                        let alert = UIAlertController(
                            title: "Request Sent",
                            message: "Connection request has been sent to \(selectedUser.username).",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    } else {
                        
                        let alert = UIAlertController(
                            title: "Request Failed",
                            message: "Could not send connection request. Please try again later.",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            } catch {
                
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "Error",
                        message: "An error occurred: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let selectedUser = filteredProfiles[indexPath.row]
        
        // guard check
        if let latitude = selectedUser.latitude, let longitude = selectedUser.longitude {
            // check if user's location is 0,0, 0,0 is invalid location
            if latitude != 0.0 && longitude != 0.0 {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                
                // focus user region
                let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
                mapView.setRegion(region, animated: true)
                
                
                mapView.removeAnnotations(mapView.annotations)
                
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = selectedUser.username
                mapView.addAnnotation(annotation)
            }
            else{
                
                let alert = UIAlertController(title: "Location Unavailable", message: "The selected user does not have a valid location.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        } else {
            
            let alert = UIAlertController(title: "Location Unavailable", message: "The selected user does not have a valid location.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            filteredProfiles = profiles
            mapView.removeAnnotations(mapView.annotations)
            updateMapAnnotationsForAllUsers()
        } else {
            
            filteredProfiles = profiles.filter { user in
                user.username.lowercased().contains(searchText.lowercased())
            }
            
            
            if let firstUser = filteredProfiles.first, let lat = firstUser.latitude, let lon = firstUser.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                
                // updates the map
                let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
                mapView.setRegion(region, animated: true)
                
                // removes old annotations and add only the matching annotations
                mapView.removeAnnotations(mapView.annotations)
                for user in filteredProfiles {
                    if let lat = user.latitude, let lon = user.longitude {
                        let annotation = MKPointAnnotation()
                        annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        annotation.title = user.username
                        mapView.addAnnotation(annotation)
                    }
                }
            } else {
                // If no results, remove annotations and reset map
                mapView.removeAnnotations(mapView.annotations)
            }
        }
        tableView.reloadData()
    }
    
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    // function to check if the user is actually logged in
    func isLoggedIn() -> Bool {
        
        if let user = UserDefaults.standard.string(forKey: "loggedInUserID"),
           !user.isEmpty,
           let username = UserDefaults.standard.string(forKey: "loggedInUsername"),
           !username.isEmpty {
            
            currentUser = ObjectId(user)
            currentUsername = username
            
            return true
        }
        return false
    }
    
    // function to fetch incoming requests every x seconds
    func startFetchConnectionRequest() {
        // schedule a timer to fetch every 1 minute
        
        //CITATION: https://www.hackingwithswift.com/articles/117/the-ultimate-guide-to-timer
        Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { timer in
            Task {
                do {
                    
                    // check if user is actually logged in
                    if self.currentUser?.hexString == nil && self.currentUsername == nil {
                        print("user not logged in, not fetching connection requests")
                    }
                    else{
                        print("fetching connection requests")
                        //print("current user", self.currentUser?.hexString)
                        let cRequests = try await self.mongoTest.getConnectionRequest(userId: self.currentUser!)
                        
                        // get all pending connection requests
                        for rq in cRequests! {
                            
                            if rq.status == "pending" {
                                let cnRequestMessage = rq.fromUsername + " wants to connect with you"
                                // show alert
                                let alert = UIAlertController(title: "New Connection Request", message: cnRequestMessage , preferredStyle: .alert)
                            
                                alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: { _ in
                                    Task {
                                        do{
                                            let gUser = try await self.mongoTest.getUser(userId: self.currentUser!)
                                            
                                            
                                            if let gUser = gUser {
                                                
                                                // create new user with removed connection request
                                                let newUser = User(
                                                    _id: gUser._id!,
                                                    username: gUser.username,
                                                    password: gUser.password,
                                                    avatar: gUser.avatar,
                                                    email: gUser.email,
                                                    latitude: gUser.latitude,
                                                    longitude: gUser.longitude,
                                                    education: gUser.education,
                                                    degree: gUser.degree,
                                                    connections: gUser.connections ?? [],
                                                    connectionRequests: []
                                                )
                                                
                                                // creates a new user to replace the old one, remove the existing connection request
                                                try await self.mongoTest.updateUser(newUser: newUser)
                                            }
                                        }
                                        catch {
                                            print(error)
                                        }
                                    }
                                }))
                                
                                alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { _ in
                                    
                                    // get the old user
                                    Task {
                                        do{
                                            let gUser = try await self.mongoTest.getUser(userId: self.currentUser!)
                                            
                                            
                                            if let gUser = gUser {
                                                
                                                var updatedConnections = gUser.connections ?? []
                                                
                                                
                                                let nConnection = Connection(username: rq.fromUsername)
                                                updatedConnections.append(nConnection)
                                                
                                                // updating the current user to insert the new connection
                                                let newUser = User(
                                                    _id: gUser._id!,
                                                    username: gUser.username,
                                                    password: gUser.password,
                                                    avatar: gUser.avatar,
                                                    email: gUser.email,
                                                    latitude: gUser.latitude,
                                                    longitude: gUser.longitude,
                                                    education: gUser.education,
                                                    degree: gUser.degree,
                                                    connections: updatedConnections,
                                                    connectionRequests: [] // clear all
                                                )
                                                
                                                // creates a new user to replace the old one, remove the existing connection request
                                                try await self.mongoTest.updateUser(newUser: newUser)
                                                
                                                // also update the user being connected
                                                let requestingUser = try await self.mongoTest.getUser(userId: rq.fromUser)
                                                if let requestingUser = requestingUser {
                                                    var updatedConnections = requestingUser.connections ?? []
                                                    let reciprocalConnection = Connection(username: self.currentUsername!)
                                                    updatedConnections.append(reciprocalConnection)
                                                    
                                                    let updatedRequestingUser = User(
                                                        _id: requestingUser._id!,
                                                        username: requestingUser.username,
                                                        password: requestingUser.password,
                                                        avatar: requestingUser.avatar,
                                                        email: requestingUser.email,
                                                        latitude: requestingUser.latitude,
                                                        longitude: requestingUser.longitude,
                                                        education: requestingUser.education,
                                                        degree: requestingUser.degree,
                                                        connections: updatedConnections,
                                                        connectionRequests: requestingUser.connectionRequests ?? []
                                                    )
                                                    
                                                    try await self.mongoTest.updateUser(newUser: updatedRequestingUser)
                                                }

                                                
                                                // show success alert
                                                let alert = UIAlertController(title: "Connected!", message: "You are connections with " + rq.fromUsername, preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "OK", style: .default))
                                                self.present(alert, animated: true)
                                            }
                                        }
                                        catch {
                                            print(error)
                                        }
                                    }
                                }))
                                
                                alert.addAction(UIAlertAction(title: "Ignore", style: .default, handler: nil))
                                
                                self.present(alert, animated: true, completion: nil)
                            }
                            // else ignore the request because it is already fulfilled
                        }
                    }
                }
                catch {
                    print(error)
                }
            }
        }
    }
}
